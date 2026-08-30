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
echo "  Pre-commit gates: swiftlint, xcodebuild build, blocklist, gallery, p8, navigation-map"
echo "  Bypass (discouraged): \`git commit --no-verify\` — CLAUDE.md prohibits."

# KMP umbrella first-build (ADR-023 Stage 5, S5-1 — #1635; PR-B2 links
# `PasturaSharedEngine.xcframework` into the app build). `--if-missing` still
# runs Gradle — its up-to-date check is the short-circuit, see the script's
# header. A cold `~/.konan` first run also downloads the Kotlin/Native
# toolchain: several minutes, roughly a gigabyte.
#
# Exit 1 (missing JDK 17+ / gradlew) WARNS and continues, the opposite of
# the pre-commit hook: this script's job is activating the hooks above, and
# an iOS-only contributor must not be blocked over a toolchain they do not
# have yet. Any other non-zero code is a real failure and aborts.
# `|| rc=$?` captures the code under `set -e` without aborting.
rc=0
./scripts/kmp/assemble-xcframework.sh --if-missing || rc=$?
case "$rc" in
  0)
    echo "✓ PasturaSharedEngine.xcframework ready"
    ;;
  1)
    echo "⚠️  KMP prerequisite missing (see the error above) — KMP build skipped." >&2
    echo "   Usually JDK 17+. Required to stage PasturaSharedEngine.xcframework; the" >&2
    echo "   pre-commit hook and scripts/xcodebuild.sh will need it once" >&2
    echo "   PR-B2 links the framework into the Pastura.app build:" >&2
    echo "     brew install --cask temurin@17" >&2
    echo "   (Git hooks above were activated successfully.)" >&2
    ;;
  *)
    echo "✗ KMP wrapper failed (exit $rc). Fix before continuing." >&2
    exit "$rc"
    ;;
esac
