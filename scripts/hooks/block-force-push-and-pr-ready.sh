#!/usr/bin/env bash
#
# block-force-push-and-pr-ready.sh — PreToolUse(Bash) guard.
#
# Blocks (exit 2) any Bash tool call whose command contains
#   - a `git push` together with a force flag (--force,
#     --force-with-lease, --force-if-includes, or short -f), or
#   - `gh pr ready` (flips a Draft PR to reviewable).
#
# Why: the queue-consumer skill runs unattended at night with allowlist
# entries like `Bash(git push -u origin agent/*)` and
# `Bash(gh pr create --draft*)`. Permission allowlists are PREFIX
# matches — they cannot forbid a suffix, so `git push -u origin
# agent/x --force` or `gh pr create --draft ... && gh pr ready` would
# sail through. This hook is the mechanical guard behind the skill's
# hard rules (never force push, PRs stay Draft).
#
# Draft-invariant residual (#1026): the allowlist now also carries
# `Bash(gh pr create --base*)` for the attended `/orchestrate` ready-PR
# path, so a non-draft `gh pr create --base …` is no longer mechanically
# blocked for ANY session. This hook still blocks `gh pr ready`, so a
# *created* Draft cannot be flipped — but the "unattended skills only
# ever open Draft PRs" guarantee now rests on those skills leading their
# create with `--draft` (a SKILL.md convention: queue-consumer,
# consistency-audit), not on the allowlist excluding a non-draft create.
# A mechanical block cannot tell an attended `/orchestrate` create from
# an unattended bug, so this residual is documented rather than blocked.
#
# Scope of the force-flag scan (#616): the unambiguous `--force*` long
# form is matched against the WHOLE command. The ambiguous shapes
# (`-f` short-flag clusters, `+refspec`) are scanned ONLY within a
# `git push` sub-command segment, so a `+`-leading or `-f`-clustered
# token in a sibling `gh pr create --body "…"` or a heredoc payload no
# longer false-fires. A segment counts as a push after a leading run of
# `VAR=value` assignments and `env`/`sudo`/`command` wrappers is
# stripped, so `env X=y git push -uf` / `sudo git push +x` (which the
# old whole-command scan blocked) are still caught. Example now
# ALLOWED: `git push origin x && rm -f y`.
#
# Residual (still conservative): the `--force*` literal anywhere in the
# command still blocks — so a PR/commit body that must contain the text
# `--force` trips the guard. Use `--body-file` / `git commit -F file`,
# or split the compound, or run it manually in a terminal; hooks only
# gate Claude's tool calls, never the human. Regression coverage:
# scripts/tests/block-force-push-test.sh.
#
# bash 3.2-safe (ships to a macOS bash 3.2 machine): no here-strings,
# no `${var^^}` / `${var,,}`, no `mapfile`. awk / tr / process
# substitution are all 3.2-safe. The CI self-test runs on ubuntu bash
# 5+, so it CANNOT catch a 3.2 regression — keep new constructs 3.2-clean.
#
# Mirrors gated-runner.sh's input handling (PR #407): malformed JSON
# falls through to a silent allow (exit 0), matching its fail-open
# trade-off for non-Bash/garbage input — the real gate for those is
# the permission system itself.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[ -z "$COMMAND" ] && exit 0

block() {
  echo "BLOCKED by scripts/hooks/block-force-push-and-pr-ready.sh: $1" \
       "If a human genuinely intends this, run it manually in a terminal." >&2
  exit 2
}

# Inspect ONE command segment that is a `git push` invocation for the
# AMBIGUOUS force shapes only — short-flag clusters containing `f`
# (-f / -uf / -fv) and `+refspec` pushes. The unambiguous `--force*`
# long form is caught globally by the caller, before segmentation.
# `set -f` stops the unquoted expansion from globbing against cwd.
scan_push_segment() {
  set -f
  for word in $1; do
    case "$word" in
      --*) : ;;  # long options handled by the global --force arm
      -[A-Za-z]*)
        case "$word" in
          *f*) block "force push (-f, possibly bundled as $word) is forbidden for Claude sessions." ;;
        esac
        ;;
      +*) block "force push via +refspec ($word) is forbidden for Claude sessions." ;;
    esac
  done
  set +f
}

case "$COMMAND" in
  *"git push"*)
    # Unambiguous long force flag — matched against the WHOLE command so
    # an `env FOO=bar git push --force` / `sudo git push --force` (first
    # word not `git`) is still blocked.
    case "$COMMAND" in
      *--force*) block "force push (--force*) is forbidden for Claude sessions." ;;
    esac

    # Ambiguous shapes (-f clusters, +refspec) cannot be matched against
    # the whole command without false-firing on a sibling subcommand's
    # body or a heredoc payload (#616). Scope the scan to the `git push`
    # segment(s) only:
    #   1. awk joins `\`-continued lines so a push whose force flag is on
    #      the next physical line stays in one segment.
    #   2. tr splits the joined text on `; & |` (so `&&` / `||` break too);
    #      embedded newlines are themselves command separators. The split
    #      is deliberately quote-blind — a `;`/`&`/`|` inside a quoted
    #      body splits too, but over-splitting only ever shrinks a
    #      segment's word set, never lets a push flag escape its segment.
    #   3. `while read` over PROCESS SUBSTITUTION (not a pipe) keeps the
    #      loop in the current shell so block()'s `exit 2` propagates.
    #   4. A segment is scanned only if it contains `git push` AND —
    #      after stripping leading VAR=value assignments and the
    #      env/sudo/command wrappers — its first word is `git`, so
    #      quoted/heredoc prose mentioning "git push" is not scanned.
    while IFS= read -r seg; do
      case "$seg" in
        *"git push"*)
          # Strip a leading run of `VAR=value` assignments and the
          # wrappers env/sudo/command so a prefix-wrapped push
          # (`env X=y git push -uf`, `sudo git push +x`, `FOO=bar git
          # push -uf`) is still scanned. Wrappers that take their own
          # args (`timeout 5 …`, `nice -n 10 …`, `env -i …`) stop the
          # strip early and fall through unscanned — a conservative
          # residual of the same class as the heredoc-prose case.
          rest=${seg#"${seg%%[![:space:]]*}"}
          while :; do
            w=${rest%%[[:space:]]*}
            case "$w" in
              env|sudo|command) : ;;  # command wrapper — drop
              [A-Za-z_]*=*) : ;;      # VAR=value assignment — drop
              *) break ;;             # `git` or anything else — stop
            esac
            rest=${rest#"$w"}
            rest=${rest#"${rest%%[![:space:]]*}"}
          done
          case "$rest" in
            # Pass the full $seg, NOT $rest — the strip loop only gates
            # whether to scan; the scan itself must see every arg so a
            # force flag after the wrapper run is never hidden.
            git\ *|git) scan_push_segment "$seg" ;;
          esac
          ;;
      esac
    done < <(printf '%s' "$COMMAND" \
      | awk '{ if (sub(/\\$/, "")) printf "%s ", $0; else print }' \
      | tr ';&|' '\n\n\n')
    ;;
esac

case "$COMMAND" in
  *"gh pr ready"*)
    block "PRs opened by agents stay Draft; ready-for-review is a human action."
    ;;
esac

exit 0
