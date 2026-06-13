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
# Conservative by design: matching is substring/glob-based, so a
# compound command like `git push origin x && rm -f y` is also blocked
# (the " -f" could belong to the push). False positives are cheap —
# split the compound or run the command manually in a terminal; hooks
# only gate Claude's tool calls, never the human.
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

case "$COMMAND" in
  *"git push"*)
    case "$COMMAND" in
      *--force*) block "force push (--force*) is forbidden for Claude sessions." ;;
      *" -f"|*" -f "*|*" -f"$'\t'*|*" -f"$'\n'*)
        block "force push (-f) is forbidden for Claude sessions." ;;
    esac
    ;;
esac

case "$COMMAND" in
  *"gh pr ready"*)
    block "PRs opened by agents stay Draft; ready-for-review is a human action."
    ;;
esac

exit 0
