#!/usr/bin/env bash
#
# check-claude-md-modified.sh — CLAUDE.md "Phase 2 progress" reminder.
#
# Inner script for the `Bash(gh pr create*)` PreToolUse hook. The
# prefix-gating is handled upstream by `scripts/hooks/gated-runner.sh`,
# so this script only runs when the runner has already confirmed the
# user-invoked command starts with `gh pr create`. Behaviour:
#
#   - If `git diff main...HEAD --name-only` shows CLAUDE.md → silent no-op
#     (exit 0 with no stdout — operator has already updated the file).
#   - Otherwise → emit a `hookSpecificOutput.additionalContext` JSON
#     reminding the operator to update "Phase 2 progress".
#
# Reads no stdin. The tool-input data is exposed via env vars by
# gated-runner.sh ($CLAUDE_HOOK_INPUT, $CLAUDE_TOOL_INPUT_COMMAND) for
# future scripts that need it; this one doesn't.
#
# Reference: PR #406/#407.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if ! git diff main...HEAD --name-only | grep -q CLAUDE.md; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      additionalContext: "CLAUDE.md not modified in this branch. Check if implementation progress needs updating."
    }
  }'
fi

exit 0
