#!/usr/bin/env bash
#
# block-force-push-and-pr-ready.sh — PreToolUse(Bash) guard.
#
# Blocks (exit 2) any Bash tool call that
#   - force-pushes: a `git push` carrying a force flag (--force,
#     --force-with-lease, --force-if-includes, short -f/-uf/-fv cluster,
#     or a +refspec), or
#   - runs `gh pr ready` (flips a Draft PR to reviewable).
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
# Force-flag detection is TOKENIZED, not substring-based. The command is
# split into segments (`; & | && || newline`, backslash-continuations
# rejoined) and each segment is walked token by token as a small state
# machine:
#   1. wrapper phase — skip a leading run of `VAR=value` assignments and
#      command wrappers (`env`/`sudo`/`command`/`nohup`/`doas`, and the
#      arg-taking `timeout`/`nice`/`ionice`/`stdbuf` with one positional
#      arg). Any other bare word (e.g. `echo`) means this segment is not a
#      git invocation → stop, so quoted/heredoc prose mentioning
#      "git push" is never scanned.
#   2. subcommand phase — first word is `git`; skip git GLOBAL options,
#      including separate-arg ones (`-c k=v`, `-C dir`, `--git-dir dir`,
#      `--work-tree dir`, `--namespace x`, `--super-prefix x`,
#      `--config-env x`). Scan for force only if the subcommand is `push`.
#   3. force phase — any `--force*`, an `-*f*` short cluster, or a
#      `+refspec` in the push args → block.
# Tokenizing (not the old literal `git push` substring gate) closes
# `git -c k=v push --force`, `git --no-pager push -f`, `timeout 5 git push
# -f`, and double-space `git␠␠push --force` — standard shapes an agent
# emits that the substring gate let sail through — and it also drops the
# false-fire on prose that merely mentions the flag (`echo "git push
# --force"` is now ALLOWED).
#
# Residuals — two kinds, one over-blocking (benign) and one under-blocking
# (the deliberate trade-off for dropping the old whole-command false-fire):
#   - Over-block: segmentation is quote-blind, so a `git push … --force`
#     that lives INSIDE a quoted --body / heredoc payload still trips the
#     guard. Use `--body-file` / `git commit -F file`, split the compound,
#     or run it manually in a terminal; hooks gate the agent, never the
#     human.
#   - Under-block: a push behind a wrapper the machine cannot see through —
#     `ssh host …` (runs on the REMOTE, a different threat model), a
#     `bash -c "…"` whose push is nested in a quoted string, or an unknown
#     wrapper — falls through UNSCANNED, so even `--force` is missed there.
#     (The known wrappers env/sudo/command/nohup/doas ARE seen through,
#     including their `-u`/`--user`/`-g`/`--group` option+arg.) The old
#     whole-command `--force` arm caught these, but only by false-firing on
#     ANY prose that mentioned the flag; tokenizing trades that miss for no
#     false-fire. The real threat model — an allowlisted `git push -u origin
#     agent/*` prefix with a force flag appended — is fully covered.
#     Regression coverage (incl. these pinned residuals):
#     scripts/tests/block-force-push-test.sh.
#
# bash 3.2-safe (ships to a macOS bash 3.2 machine): no here-strings,
# no `${var^^}` / `${var,,}`, no `mapfile`, no arrays. awk / tr / process
# substitution are all 3.2-safe. The CI self-test runs on ubuntu bash 5+,
# so it CANNOT catch a 3.2 regression — keep new constructs 3.2-clean.
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

# scan_segment — tokenize ONE command segment and block if it is a
# force-push. Walks words in a single pass with a 3-phase state machine
# (wrapper -> subcmd -> force); see the header for the phase contract.
# `set -f` stops the unquoted `for word in $1` from globbing against cwd.
scan_segment() {
  set -f
  local state=wrapper skip_next=0 argwrap=0 word
  for word in $1; do
    if [ "$skip_next" = 1 ]; then skip_next=0; continue; fi
    case "$state" in
      wrapper)
        case "$word" in
          git)                          state=subcmd ;;
          [A-Za-z_]*=*)                 : ;;              # VAR=value assignment
          env|sudo|command|nohup|doas)  argwrap=0 ;;      # no-arg wrapper
          timeout|nice|ionice|stdbuf)   argwrap=1 ;;      # takes a positional arg
          -u|--user|-g|--group)         skip_next=1 ;;    # sudo/env user|group option: consumes a separate arg (so `sudo -u bob git push -f` is still scanned)
          -*)                           : ;;              # a wrapper's own option (no separate arg)
          *)
            # A bare non-git word: the positional arg of an arg-taking
            # wrapper (`timeout 5`), else a foreign command (`echo`) that
            # means this segment is not a git invocation — stop scanning.
            if [ "$argwrap" = 1 ]; then argwrap=0
            else set +f; return 0; fi
            ;;
        esac
        ;;
      subcmd)
        case "$word" in
          -c|-C|--git-dir|--work-tree|--namespace|--super-prefix|--config-env)
                    skip_next=1 ;;                        # global opt + separate arg
          -*)       : ;;                                  # other global opt (--no-pager, -p, =-attached)
          push)     state=force ;;
          *)        set +f; return 0 ;;                   # some other subcommand — not a push
        esac
        ;;
      force)
        case "$word" in
          --force*)     set +f; block "force push (--force*) is forbidden for agent sessions." ;;
          -[A-Za-z]*)   case "$word" in *f*) set +f; block "force push (-f cluster: $word) is forbidden for agent sessions." ;; esac ;;
          +*)           set +f; block "force push via +refspec ($word) is forbidden for agent sessions." ;;
        esac
        ;;
    esac
  done
  set +f
  return 0
}

# `gh pr ready` block — independent of the push scan (a ready-making
# command carries no `push`, so it must be checked separately, NOT behind
# the force scan's push fast-path).
case "$COMMAND" in
  *"gh pr ready"*)
    block "PRs opened by agents stay Draft; ready-for-review is a human action."
    ;;
esac

# Force-push tokenized scan — only when `push` appears anywhere (keeps the
# common Bash call cheap). Split COMMAND into segments and scan each:
#   1. awk rejoins `\`-continued lines so a push whose force flag is on the
#      next physical line stays in one segment.
#   2. tr splits on `; & |` (so `&&` / `||` break too); embedded newlines
#      are themselves separators. Quote-blind by design — over-splitting a
#      quoted body only ever shrinks a segment's word set, never lets a
#      push flag escape its segment.
#   3. `while read` over PROCESS SUBSTITUTION (not a pipe) keeps the loop in
#      the current shell so block()'s `exit 2` propagates.
#   4. The `*git*` pre-filter skips non-git segments cheaply; scan_segment
#      itself bails on any segment whose command is not `git`.
case "$COMMAND" in
  *push*)
    while IFS= read -r seg; do
      case "$seg" in
        *git*) scan_segment "$seg" ;;
      esac
    done < <(printf '%s' "$COMMAND" \
      | awk '{ if (sub(/\\$/, "")) printf "%s ", $0; else print }' \
      | tr ';&|' '\n\n\n')
    ;;
esac

exit 0
