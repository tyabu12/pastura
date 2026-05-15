#!/usr/bin/env bash
#
# check-claude-md-modified.sh — Claude Code PreToolUse Bash hook gating.
#
# Reminds the operator to update CLAUDE.md "Phase 2 progress" before
# creating a PR when the branch hasn't already touched CLAUDE.md.
#
# Self-gates on the actual tool input (`.tool_input.command`) instead of
# relying on the `if` field's permission-rule match. Background: Claude
# Code's parser falls back to **fail-open** ("the hook always runs")
# when the user-invoked Bash command is too complex to parse — common
# triggers are `&&`, `|`, `$(...)`, and heredocs. Implementation
# sessions almost always invoke complex Bash, so an `if`-based gate
# bypasses on essentially every call and the reminder fires far beyond
# its intended `gh pr create` scope.
#
# Workaround: a sidecar script reads the hook input JSON from stdin,
# checks the command prefix explicitly, and emits the
# `hookSpecificOutput.additionalContext` JSON only on match. Non-match
# = exit 0 with no stdout = silent no-op (verified against Claude Code
# docs: empty stdout is NOT dumped as raw context).
#
# Reference: https://code.claude.com/docs/en/hooks
#
# History: surfaced during PR #405's /orchestrate session
# (#406 → this PR).

set -euo pipefail

# Hook input arrives on stdin as JSON: { tool_name, tool_input: { command, ... }, ... }
# `2>/dev/null || true` swallows malformed-JSON parse errors so the script
# always falls through to the silent `*)` branch on bad input — preserves
# the silent-no-op contract instead of surfacing a non-zero hook failure.
INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

# Pattern is anchored at the start of the command string — leading
# whitespace ("  gh pr create ...") or compound prefixes ("foo && gh pr
# create ...") will NOT match. That's intentional: those shapes don't
# arise from Claude Code's tool dispatch in practice, and broadening the
# pattern would re-introduce the same false-positive class the original
# `if`-based gate exhibited under graceful-degradation.
case "$COMMAND" in
  'gh pr create'*)
    # Match the intended gate. Run the original check.
    cd "$(git rev-parse --show-toplevel)"
    if ! git diff main...HEAD --name-only | grep -q CLAUDE.md; then
      jq -n '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          additionalContext: "CLAUDE.md not modified in this branch. Check if implementation progress needs updating."
        }
      }'
    fi
    ;;
  *)
    # Non-matching command — silent no-op. Empty stdout is NOT
    # interpreted as raw context per the docs.
    ;;
esac

exit 0
