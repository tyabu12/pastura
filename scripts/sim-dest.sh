#!/bin/bash
# Resolve a usable iOS Simulator destination for xcodebuild.
# Sources into the caller's shell and exports DEST.
#
# Usage:
#   source scripts/sim-dest.sh
#   xcodebuild test ... -destination "$DEST"
#
# Uses UDID-based destination to avoid OS version mismatch when
# xcodebuild defaults to OS:latest (e.g., iPhone 16 has only iOS 26.3
# but latest is 26.4).
#
# Update this list when new Xcode versions add newer default simulators.
# Save caller's shell options so sourcing doesn't permanently alter them.
_simdest_old_opts=$(set +o)
set -euo pipefail

SIMULATOR_NAMES=(
  "iPhone 17 Pro"
  "iPhone 17"
  "iPhone Air"
  "iPhone 17e"
  "iPhone 16"
  "iPhone 16e"
  "iPhone 15 Pro"
  "iPhone 15"
)

# Resolve the first matching simulator's UDID, name, and runtime via JSON.
# python3 is available on all macOS systems with Xcode.
_simdest_result=$(python3 -c "
import json, subprocess, sys, re

priority = sys.argv[1:]
raw = subprocess.check_output(
    ['xcrun', 'simctl', 'list', 'devices', 'available', '--json'],
    text=True,
)
data = json.loads(raw)

for name in priority:
    for runtime_id, devices in data.get('devices', {}).items():
        for device in devices:
            if device['name'] == name:
                # Extract human-readable OS version from runtime identifier
                # e.g. com.apple.CoreSimulator.SimRuntime.iOS-26-4 -> iOS 26.4
                m = re.search(r'iOS-(\d+)-(\d+)', runtime_id)
                os_ver = f'iOS {m.group(1)}.{m.group(2)}' if m else runtime_id
                print(f\"{device['udid']}|{name}|{os_ver}\")
                sys.exit(0)

sys.exit(1)
" "${SIMULATOR_NAMES[@]}" 2>/dev/null) || true

if [ -z "$_simdest_result" ]; then
  echo "Error: No available iOS Simulator found. Tried: ${SIMULATOR_NAMES[*]}" >&2
  eval "$_simdest_old_opts"
  return 1 2>/dev/null || exit 1
fi

_simdest_udid=$(echo "$_simdest_result" | cut -d'|' -f1)
_simdest_name=$(echo "$_simdest_result" | cut -d'|' -f2)
_simdest_os=$(echo "$_simdest_result" | cut -d'|' -f3)

export DEST="platform=iOS Simulator,id=$_simdest_udid"
echo "Selected simulator: $_simdest_name ($_simdest_os) [id=$_simdest_udid]"

eval "$_simdest_old_opts"
# return when sourced, exit when executed directly
return 0 2>/dev/null || exit 0
