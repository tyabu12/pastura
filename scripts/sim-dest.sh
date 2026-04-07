#!/bin/bash
# Resolve a usable iOS Simulator destination for xcodebuild.
# Sources into the caller's shell and exports DEST.
#
# Usage:
#   source scripts/sim-dest.sh
#   xcodebuild test ... -destination "$DEST"
#
# Update this list when new Xcode versions add newer default simulators.
# Save caller's shell options so sourcing doesn't permanently alter them.
_simdest_old_opts=$(set +o)
set -euo pipefail

SIMULATOR_NAMES=(
  "iPhone 16 Pro"
  "iPhone 16"
  "iPhone 15 Pro"
  "iPhone 15"
)

for name in "${SIMULATOR_NAMES[@]}"; do
  if xcrun simctl list devices available | grep -qF "$name"; then
    export DEST="platform=iOS Simulator,name=$name"
    echo "Selected simulator: $name"
    eval "$_simdest_old_opts"
    # return when sourced, exit when executed directly
    return 0 2>/dev/null || exit 0
  fi
done

echo "Error: No available iOS Simulator found. Tried: ${SIMULATOR_NAMES[*]}" >&2
eval "$_simdest_old_opts"
# return when sourced, exit when executed directly
return 1 2>/dev/null || exit 1
