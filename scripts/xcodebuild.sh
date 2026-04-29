#!/bin/bash
# Run xcodebuild test / build with Pastura's standard env + flags pre-applied.
#
# Usage (canonical form — cwd-independent, matches the Bash allowlist):
#   "$(git rev-parse --show-toplevel)/scripts/xcodebuild.sh" test
#   "$(git rev-parse --show-toplevel)/scripts/xcodebuild.sh" test -only-testing PasturaTests/Foo
#   "$(git rev-parse --show-toplevel)/scripts/xcodebuild.sh" test -skip-testing:PasturaUITests
#   "$(git rev-parse --show-toplevel)/scripts/xcodebuild.sh" build
#
# Shorter convenience alias for interactive shells:
#   xcb="$(git rev-parse --show-toplevel)/scripts/xcodebuild.sh"
#   "$xcb" test -only-testing PasturaTests/Foo
#
# Subcommand maps directly to xcodebuild's; remaining args forward
# verbatim via "$@". xcodebuild honors the last value for repeated
# single-value flags, so caller passthrough wins on duplicates (e.g.
# override the destination: `... test -destination 'platform=iOS Simulator,name=...'`).
#
# Mode-specific behavior:
#
# - `test` uses the UDID-pinned simulator destination from sim-dest.sh
#   and adds `-parallel-testing-enabled NO`. The parallel-OFF flag
#   mirrors the CI workaround for the within-process simulator-clone
#   crash cascade (200+ tests reporting failed at 0.000s on a single
#   clone PID — local Apple Silicon reproduces at ~50% on the full
#   suite). CI applies the same flag inline. Harmless for narrow TDD
#   runs since `@Suite(.serialized)` already orders within-suite tests.
#   Root-cause investigation stays in #189; this wrapper is the
#   symptom-level workaround.
#
# - `build` uses `generic/platform=iOS Simulator` (no UDID) and exports
#   `PASTURA_SKIP_SIM_WAIT=1` BEFORE sourcing sim-dest.sh so the
#   concurrent-session simulator gate is bypassed. Build artifacts are
#   architecturally identical across simulator UDIDs, so booking a
#   specific UDID wastes time and reintroduces gate contention. This
#   matches the pre-commit hook's destination choice. `$DERIVED_DATA`
#   is still populated by sim-dest.sh so build output lands in the
#   worktree-local Pastura/DerivedData/ alongside test runs.
#
# Streams output directly to the terminal — no tee, no log file. Exit
# code is xcodebuild's exit code unmodified (xcodebuild is the last
# statement under `set -e`). For context-window-sized output in agent
# sessions, pipe externally:
#
#   "$xcb" test ...  2>&1 | grep -E 'error:|TEST|passed|failed' | tail -30
#   "$xcb" build ... 2>&1 | grep -E 'error:|warning:|BUILD'    | head -30

set -euo pipefail

# Resolve repo root once so every subsequent path is absolute. Lets the
# wrapper work correctly from any cwd inside the worktree (e.g., a
# nested Pastura/PasturaTests/ subdirectory) — relative paths like
# `Pastura/Pastura.xcodeproj` would silently break under cwd shifts.
REPO_ROOT=$(git rev-parse --show-toplevel)

if [[ $# -eq 0 ]]; then
  echo 'Usage: "$(git rev-parse --show-toplevel)/scripts/xcodebuild.sh" <test|build> [args...]' >&2
  exit 2
fi

cmd=$1
shift

case "$cmd" in
  test)
    extra_flags=(-parallel-testing-enabled NO)
    ;;
  build)
    extra_flags=()
    # build doesn't book a simulator — bypass the sim-dest.sh gate so
    # concurrent test runs from other worktrees don't block us.
    export PASTURA_SKIP_SIM_WAIT=1
    ;;
  *)
    echo "Unknown subcommand: $cmd (expected 'test' or 'build')" >&2
    exit 2
    ;;
esac

# shellcheck source=scripts/sim-dest.sh
source "$REPO_ROOT/scripts/sim-dest.sh"

if [[ "$cmd" == "build" ]]; then
  destination="generic/platform=iOS Simulator"
else
  destination="$DEST"
fi

set -x
# `${extra_flags[@]+"${extra_flags[@]}"}` survives `set -u` when the
# array is empty (macOS bash 3.2 quirk: bare `"${arr[@]}"` expansion
# trips `nounset` for zero-length arrays).
xcodebuild "$cmd" \
  -scheme Pastura \
  -project "$REPO_ROOT/Pastura/Pastura.xcodeproj" \
  -destination "$destination" \
  -derivedDataPath "$DERIVED_DATA" \
  ${extra_flags[@]+"${extra_flags[@]}"} \
  "$@"
