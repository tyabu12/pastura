#!/bin/bash
# Run the full Pastura test suite locally with parallel testing disabled.
#
# Usage:
#   scripts/test-full.sh                                # full unit suite
#   scripts/test-full.sh -only-testing PasturaTests/Foo # narrow scope
#   scripts/test-full.sh -skip-testing:PasturaUITests   # skip UI tests
#
# Why -parallel-testing-enabled NO:
# Mirrors the CI workaround for the within-process simulator-clone crash
# cascade (200+ tests reporting failed at 0.000s on a single clone PID).
# CI applied this in .github/workflows/ci.yml; local Apple Silicon runs
# also reproduce at ~50% frequency (PR #246 session). Root-cause work
# stays in #189 — this wrapper only mirrors the symptom-level workaround.
#
# Args after the wrapper's fixed flags are forwarded verbatim via "$@".
# xcodebuild honors the last value for repeated single-value flags, so
# user passthrough (e.g. -parallel-testing-enabled YES to test the bug)
# wins on duplicates. No flag parsing happens here.
#
# This wrapper streams xcodebuild output directly to the terminal — no
# tee, no log file. The exit code is xcodebuild's exit code unmodified.

set -euo pipefail

# shellcheck source=scripts/sim-dest.sh
source "$(git rev-parse --show-toplevel)/scripts/sim-dest.sh"

set -x
xcodebuild test \
  -scheme Pastura \
  -project Pastura/Pastura.xcodeproj \
  -destination "$DEST" \
  -derivedDataPath "$DERIVED_DATA" \
  -parallel-testing-enabled NO \
  "$@"
