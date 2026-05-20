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
echo "  Pre-commit gates: KMP xcframework (--if-missing), swiftlint,"
echo "                    xcodebuild build, blocklist, gallery"
echo "  Bypass (discouraged): \`git commit --no-verify\` — CLAUDE.md prohibits."

# KMP XCFramework first-build (Issue #220 — spike scope; gates the
# Pastura.app build because pbxproj references `PasturaShared.xcframework`
# from `Pastura/Frameworks/`). The wrapper's `--if-missing` is gradle-UP-TO-DATE-backed.
#
# Exit code branching:
#   - 0: success / already up-to-date — continue silently.
#   - 1: missing tool (JDK 17+ / gradlew) — warn but DO NOT block
#        bootstrap. iOS-only contributors should be able to run
#        `./scripts/setup.sh` without installing JDK 17 (they just
#        can't build Pastura.app until they do, which is fine — the
#        hooks themselves are activated above and that's the main
#        purpose of setup.sh).
#   - 2 / 3 / other: real failure — propagate the error, abort bootstrap.
#
# `|| rc=$?` captures the exit code under `set -e` without aborting the
# script. The `case` statement then branches on the captured rc.
rc=0
./scripts/kmp/assemble-xcframework.sh --if-missing || rc=$?
case "$rc" in
  0)
    echo "✓ PasturaShared.xcframework ready"
    ;;
  1)
    echo "⚠️  JDK 17+ not found — KMP build skipped." >&2
    echo "   Install Temurin 17 to enable Pastura.app builds:" >&2
    echo "     brew install --cask temurin@17" >&2
    echo "   (Git hooks above were activated successfully.)" >&2
    ;;
  *)
    echo "✗ KMP wrapper failed (exit $rc). Fix before continuing." >&2
    exit "$rc"
    ;;
esac
