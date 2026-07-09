#!/usr/bin/env bash
#
# pr-created-reflection.sh — post-PR-creation reflection reminder.
#
# Inner script for the `Bash(gh pr create --base*)` PostToolUse hook.
# The prefix-gating is handled upstream by
# `scripts/hooks/gated-runner.sh 'gh pr create --base'`, so this script
# only runs right after a `/orchestrate` ready-PR create — the sole
# `--base`-first create shape. Unattended `gh pr create --draft` flows
# (queue-consumer, consistency-audit) lead with `--draft`, do NOT match
# the `--base` gate, and never trigger this reminder — so the nudge only
# fires where a human is present to act on it.
#
# Emits a `hookSpecificOutput.additionalContext` reminder at the
# PR-creation moment — when the operator is present and the change is
# fresh — covering the three things that were previously nudged too late
# at ExitWorktree (which fires only at post-merge worktree teardown):
#   1. Restate the on-device QA steps for this change (or `実機QA不要`
#      + reason) to match the PR body's `## Device QA` section.
#   2. Surface any observations / concerns / suggestions noticed during
#      the session.
#   3. Note any memory files worth creating or updating.
#
# Reads no stdin (static reminder). The tool-input data is available via
# the env vars gated-runner.sh exports ($CLAUDE_HOOK_INPUT,
# $CLAUDE_TOOL_INPUT_COMMAND) for future scripts; this one does not use
# them.
#
# hookEventName MUST be "PostToolUse" — this fires after the tool runs.
#
# Reference: issue #1026.

set -euo pipefail

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: "PR created. Before moving on: (1) Device QA — restate the on-device QA steps this change needs (or state 実機QA不要 with the reason), matching the ## Device QA section in the PR body. (2) Observations — share any concerns, surprises, or suggestions you noticed during this session. (3) Memory — note any memory files worth creating or updating from this session."
  }
}'

exit 0
