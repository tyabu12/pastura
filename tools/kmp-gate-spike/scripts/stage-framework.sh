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
# The Gradle invocation, JDK probe and atomic staging now live in
# `scripts/kmp/assemble-xcframework.sh`, the single implementation shared with
# the app tree (ADR-023 §6 (b) — one umbrella, so one assembler). This file is a
# thin wrapper that only supplies this package's `--dest`.
#
# Idempotent: re-running re-assembles (Gradle is incremental) and replaces the
# staged copy.
#
# Usage:
#   tools/kmp-gate-spike/scripts/stage-framework.sh [debug|release]   # default: debug
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PACKAGE_ROOT/../.." && pwd)"

# Default debug: `kmp-nightly.yml` calls this with no argument, and ADR-023 §11
# measured its numbers at debug.
exec "$REPO_ROOT/scripts/kmp/assemble-xcframework.sh" \
  --config "${1:-debug}" \
  --dest "$PACKAGE_ROOT/Frameworks"
