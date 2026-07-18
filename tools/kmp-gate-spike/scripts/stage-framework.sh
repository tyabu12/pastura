#!/usr/bin/env bash
#
# Assembles the `PasturaSharedEngine` XCFramework from the KMP `shared/engine`
# module and stages it inside this package so SwiftPM's local-path
# `.binaryTarget` can resolve it.
#
# Why stage instead of pointing `.binaryTarget` at the Gradle output directly:
# SwiftPM resolves a target's path relative to the package root and rejects one
# that escapes it, so `../../shared/engine/build/...` is not addressable from a
# package rooted at `tools/kmp-gate-spike/`. (The same constraint is why the
# `SuspendController` copy in Sources/ is a copy — see README § "The
# SuspendController copy".)
#
# Idempotent: re-running re-assembles (Gradle is incremental) and replaces the
# staged copy.
#
# Usage:
#   tools/kmp-gate-spike/scripts/stage-framework.sh [debug|release]   # default: debug
set -euo pipefail

CONFIG="${1:-debug}"
case "$CONFIG" in
  debug) GRADLE_TASK=":shared:engine:assemblePasturaSharedEngineDebugXCFramework" ;;
  release) GRADLE_TASK=":shared:engine:assemblePasturaSharedEngineReleaseXCFramework" ;;
  *)
    echo "error: unknown configuration '$CONFIG' (expected 'debug' or 'release')" >&2
    exit 2
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PACKAGE_ROOT/../.." && pwd)"

SOURCE="$REPO_ROOT/shared/engine/build/XCFrameworks/$CONFIG/PasturaSharedEngine.xcframework"
DEST_DIR="$PACKAGE_ROOT/Frameworks"
DEST="$DEST_DIR/PasturaSharedEngine.xcframework"

echo "==> Assembling $GRADLE_TASK"
(cd "$REPO_ROOT" && ./gradlew "$GRADLE_TASK" --no-daemon)

if [ ! -d "$SOURCE" ]; then
  echo "error: Gradle reported success but '$SOURCE' is missing." >&2
  echo "       The XCFramework output path may have moved — check" >&2
  echo "       shared/engine/build.gradle.kts and update this script." >&2
  exit 1
fi

echo "==> Staging into $DEST"
mkdir -p "$DEST_DIR"
rm -rf "$DEST"
cp -R "$SOURCE" "$DEST"

echo "==> Done. 'swift build --package-path tools/kmp-gate-spike' can now resolve the binary target."
