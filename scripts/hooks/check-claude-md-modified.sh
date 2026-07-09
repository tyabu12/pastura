#!/usr/bin/env bash
#
# check-claude-md-modified.sh — project-knowledge update reminder.
#
# Inner script for the `Bash(gh pr create*)` PreToolUse hook. The
# prefix-gating is handled upstream by `scripts/hooks/gated-runner.sh`,
# so this script only runs when the runner has already confirmed the
# user-invoked command starts with `gh pr create`. Behaviour:
#
#   - If `git diff main...HEAD --name-only` shows CLAUDE.md OR any
#     `.claude/rules/` file → silent no-op (exit 0 with no stdout — the
#     operator already touched a project-knowledge file, so assume it
#     was considered).
#   - Otherwise → emit a `hookSpecificOutput.additionalContext` JSON
#     nudging the operator to record any new convention / trap /
#     Phase 2 progress entry (CLAUDE.md for project-wide / phase
#     progress, `.claude/rules/` for scoped conventions).
#
# Note: touching a `.claude/rules/` file also silences the CLAUDE.md
# "Phase 2 progress" nudge even if progress itself was not updated — an
# intentional "you edited conventions, you likely considered it"
# trade-off, matching the pre-existing CLAUDE.md-silences behaviour.
#
# Reads no stdin. The tool-input data is exposed via env vars by
# gated-runner.sh ($CLAUDE_HOOK_INPUT, $CLAUDE_TOOL_INPUT_COMMAND) for
# future scripts that need it; this one doesn't.
#
# Reference: PR #406/#407; broadened to .claude/rules/ in #1026.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if ! git diff main...HEAD --name-only | grep -qE 'CLAUDE\.md|\.claude/rules/'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      additionalContext: "Neither CLAUDE.md nor .claude/rules/ was modified in this branch. If this change adds or alters a convention, trap, or Phase 2 progress entry, record it — CLAUDE.md for project-wide / phase progress, .claude/rules/ for scoped conventions."
    }
  }'
fi

exit 0
