#!/usr/bin/env bash
#
# scripts/kmp/assemble-xcframework.sh — Assemble `PasturaShared.xcframework`
# for iOS-side consumption (Issue #220 W3 PR-A).
#
# Invokes Gradle's `:shared:models:assemblePasturaSharedXCFramework` task
# (defined by `XCFramework("PasturaShared")` in `shared/models/build.gradle.kts`)
# and atomically places the release-variant output at the gitignored path
# `Pastura/Frameworks/PasturaShared.xcframework` where `Pastura.xcodeproj`'s
# Framework Search Paths expect it.
#
# Usage:
#   scripts/kmp/assemble-xcframework.sh             # full assemble (~1-2s when UP-TO-DATE)
#   scripts/kmp/assemble-xcframework.sh --if-missing # same as full assemble; relies on
#                                                    # Gradle's UP-TO-DATE check for fast path
#
# Exit codes:
#   0 — success (built or already up-to-date)
#   1 — missing tool (JDK 17 / gradlew)
#   2 — Gradle assemble failed
#   3 — copy / atomic-rename failed
#
# Design notes:
#   - `--if-missing` does NOT short-circuit on filesystem mtime check. An
#     earlier draft (W3 PR-A 3rd critic) used `git diff --cached --quiet
#     shared/` plus an `Info.plist` mtime check, but both leaked silent-stale
#     scenarios (post-`git pull` stale-Info.plist, new `.kt` file invisible
#     to two-file mtime check). Gradle's own UP-TO-DATE check is the
#     authoritative fast path and costs only ~1-2s on no-op invocations.
#   - Aggregator task outputs both Debug and Release variants. We promote
#     the Release variant to `Pastura/Frameworks/` because:
#       (a) Pastura.app's Release config consumes the released framework
#           (Debug builds also link release variant for spike simplicity)
#       (b) `Debug` adds .dSYM bundles but doubles size (~2x) — not worth
#           the disk cost for the iOS-side spike scope.
#   - Atomic rename via `mv` (POSIX) — partial xcframework on Ctrl-C is
#     avoided because mv on the same filesystem is atomic.

set -euo pipefail

# Run from repo root regardless of invocation directory.
cd "$(git rev-parse --show-toplevel)"

REPO_ROOT="$(pwd)"
GRADLE_OUTPUT="${REPO_ROOT}/shared/models/build/XCFrameworks/release/PasturaShared.xcframework"
TARGET_DIR="${REPO_ROOT}/Pastura/Frameworks"
TARGET="${TARGET_DIR}/PasturaShared.xcframework"

# Branch-switch guard (Issue #220 W3 PR-A code-reviewer Warning #1):
# the KMP module is gated to `feature/kmp-spike-models` and its child
# branches. If a contributor runs `setup.sh` while on a spike branch
# (activating the pre-commit hook with KMP step 0), then switches to
# `main` or a non-spike branch, `shared/models/` is absent from that
# ref and gradle would fail with "task not found". Silent no-op
# instead — consistent with `scripts/xcodebuild.sh` handling missing
# xcstrings sync via sentinel + exit 0.
if [ ! -f "${REPO_ROOT}/shared/models/build.gradle.kts" ]; then
  exit 0
fi

# Parse args. Only --if-missing is meaningful at the moment (kept for
# pre-commit / setup.sh callsites that pass it explicitly), but the
# behaviour is currently identical to no-flag invocation.
IF_MISSING=0
for arg in "$@"; do
  case "$arg" in
    --if-missing) IF_MISSING=1 ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "✗ unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

# JDK probe. Gradle 9.x requires JDK 17+ for the daemon; the `jvmTarget`
# in `shared/models/build.gradle.kts` is pinned to 17 (bytecode-only),
# so the runtime JVM may be any LTS at-or-above 17. CI uses
# `actions/setup-java` `java-version: 17` for parity, but local dev on
# 17 / 21 / future LTS is supported.
if ! command -v java >/dev/null 2>&1; then
  echo "✗ java not found. Install Temurin 17: brew install --cask temurin@17" >&2
  exit 1
fi

# `java -version` writes to stderr. Extract major version from
# `openjdk version "17.0.x" ...` or `openjdk version "21" ...` formats.
JAVA_VERSION="$(java -version 2>&1 | head -1 | sed -E 's/.*version "([0-9]+)(\.[0-9]+)?.*/\1/')"
if ! [[ "${JAVA_VERSION:-}" =~ ^[0-9]+$ ]] || [ "${JAVA_VERSION}" -lt 17 ]; then
  echo "✗ JDK 17 or newer required, found JDK ${JAVA_VERSION:-unknown}." >&2
  echo "  Install: brew install --cask temurin@17" >&2
  echo "  Or set JAVA_HOME: export JAVA_HOME=\$(/usr/libexec/java_home -v 17)" >&2
  exit 1
fi

if [ ! -x "${REPO_ROOT}/gradlew" ]; then
  echo "✗ gradlew not found or not executable at ${REPO_ROOT}/gradlew" >&2
  exit 1
fi

# Always invoke Gradle — its UP-TO-DATE check is the fast path
# (~1-2s on no-op, full build only when sources changed).
if ! "${REPO_ROOT}/gradlew" :shared:models:assemblePasturaSharedXCFramework --quiet; then
  echo "✗ Gradle assemble failed. Re-run without --quiet for diagnostics:" >&2
  echo "    ${REPO_ROOT}/gradlew :shared:models:assemblePasturaSharedXCFramework --stacktrace" >&2
  exit 2
fi

if [ ! -d "${GRADLE_OUTPUT}" ]; then
  echo "✗ Gradle reported success but output missing: ${GRADLE_OUTPUT}" >&2
  exit 3
fi

# Atomic rename: stage to a sibling temp dir, then `mv` over the target.
# Removes a stale prior copy first to avoid `mv: cannot move ... into itself` semantics.
mkdir -p "${TARGET_DIR}"
TEMP_TARGET="${TARGET_DIR}/.PasturaShared.xcframework.tmp.$$"
trap 'rm -rf "${TEMP_TARGET}"' EXIT

# Copy the gradle output to a sibling temp path then atomically swap.
# Pure-`mv` from gradle's build dir would tie our target to Gradle's
# rebuild-then-delete cycle; copy-then-swap keeps the deployed framework
# independent.
cp -R "${GRADLE_OUTPUT}" "${TEMP_TARGET}" || { echo "✗ copy failed" >&2; exit 3; }
rm -rf "${TARGET}"
mv "${TEMP_TARGET}" "${TARGET}" || { echo "✗ atomic rename failed" >&2; exit 3; }
trap - EXIT

if [ "${IF_MISSING}" -eq 1 ]; then
  # In --if-missing mode, suppress success chatter; the typical caller
  # is pre-commit / setup.sh where silent success is preferable.
  exit 0
fi

SIZE="$(du -sh "${TARGET}" 2>/dev/null | cut -f1)"
echo "✓ PasturaShared.xcframework ready at ${TARGET} (${SIZE})"
