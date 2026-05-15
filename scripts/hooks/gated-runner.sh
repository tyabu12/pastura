#!/usr/bin/env bash
#
# gated-runner.sh — generic Claude Code hook command-prefix gating.
#
# Usage:
#   bash gated-runner.sh "<bash-prefix>" -- <inner-cmd> [args...]
#
# Reads Claude Code's hook input JSON from stdin, extracts the actual
# Bash command via `.tool_input.command`, and runs <inner-cmd> only
# when the command string starts with <bash-prefix>. Non-match: silent
# no-op (exit 0 with no stdout — Claude Code does NOT dump empty
# stdout as raw context).
#
# Why this exists:
#   Claude Code's hook `if` field uses permission-rule syntax for
#   prefix gating, but the parser fails-open on complex Bash commands
#   (`&&`, `|`, `$(...)`, heredoc, etc.) — "For Bash commands too
#   complex to parse, the hook always runs" per the docs. That means
#   `if: "Bash(gh pr create*)"` doesn't actually gate the way it reads
#   when the actual command is complex (which is essentially every
#   implementation-session invocation). gated-runner.sh bypasses the
#   `if`-field path entirely by parsing the tool input itself.
#
# Inner-command interface:
#   - Exec'd directly (no stdin forward) so the inner command can read
#     fresh stdin if needed.
#   - The captured tool input is exposed to the inner command via two
#     env vars (forward-compat for future inner scripts):
#       CLAUDE_HOOK_INPUT          — full JSON
#       CLAUDE_TOOL_INPUT_COMMAND  — pre-parsed `.tool_input.command`
#   - Inner-cmd's exit code propagates as the hook's exit code via
#     `exec`. Non-zero from the inner cmd surfaces a hook failure to
#     the operator.
#
# Prefix-matching semantics:
#   - Bash `case` glob, anchored at position 0.
#   - Trailing wildcard `*` is implicit (the runner appends it),
#     so `"gh pr create"` matches `gh pr create --title foo` etc.
#   - Leading whitespace, compound prefixes (`foo && gh pr create`),
#     and other complex shapes do NOT match — intentional, mirrors
#     the trade-off documented in `check-claude-md-modified.sh`.
#
# Reference: memory `reference_claudecode_hook_matcher.md`
#            (Graceful degradation section) + PR #407.
#
# Example wiring:
#   .claude/settings.json
#   {
#     "type": "command",
#     "command": "cd $(git rev-parse --show-toplevel) && bash scripts/hooks/gated-runner.sh 'gh pr create' -- bash scripts/hooks/check-claude-md-modified.sh"
#   }

set -euo pipefail

# --- arg parsing ------------------------------------------------------------

if [[ $# -lt 3 ]]; then
  echo "gated-runner.sh: usage: bash gated-runner.sh <prefix> -- <inner-cmd> [args...]" >&2
  exit 2
fi

PREFIX="$1"
shift

if [[ "$1" != "--" ]]; then
  echo "gated-runner.sh: expected '--' separator after prefix, got: $1" >&2
  exit 2
fi
shift

if [[ $# -eq 0 ]]; then
  echo "gated-runner.sh: missing inner-cmd after '--'" >&2
  exit 2
fi

# --- input parsing ----------------------------------------------------------

# `2>/dev/null || true` swallows malformed-JSON parse errors so the
# script always falls through to the silent no-op branch on bad input.
INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

# --- gate -------------------------------------------------------------------

case "$COMMAND" in
  "$PREFIX"*)
    export CLAUDE_HOOK_INPUT="$INPUT"
    export CLAUDE_TOOL_INPUT_COMMAND="$COMMAND"
    exec "$@"
    ;;
esac

# Non-match — silent no-op. Empty stdout is NOT interpreted as raw
# context by Claude Code (verified during PR #407 docs research).
exit 0
