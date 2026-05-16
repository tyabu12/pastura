#!/usr/bin/env bash
#
# scripts/setup.sh — Pastura post-clone bootstrap.
#
# Activates the repo-tracked git hooks under `scripts/git-hooks/` by
# pointing `core.hooksPath` at that directory. Idempotent — safe to
# rerun any time (e.g., after `git clone --no-config` or after manually
# editing `.git/config`).
#
# Why this exists:
#   - `.git/hooks/` is per-clone and not tracked in the repo, so we
#     can't ship hooks there. Instead we keep them under
#     `scripts/git-hooks/` and point git at that directory via
#     `core.hooksPath`.
#   - Pre-Step E PR2 / #406 the same gates lived as Claude Code
#     PreToolUse Bash hooks in `.claude/settings.json`. They were
#     migrated here because Claude Code's `if`-field parser fails-open
#     on complex Bash, so the hooks surfaced their errors on every
#     complex tool invocation, not just `git commit`. See memory
#     `reference_claudecode_hook_matcher.md` and PR #410 for the
#     full history.
#
# Run this once per fresh clone:
#   ./scripts/setup.sh

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

git config core.hooksPath scripts/git-hooks
echo "✓ git hooks activated (core.hooksPath = scripts/git-hooks)"
echo "  Pre-commit gates: swiftlint, xcodebuild build, blocklist, gallery"
echo "  Bypass (discouraged): \`git commit --no-verify\` — CLAUDE.md prohibits."
