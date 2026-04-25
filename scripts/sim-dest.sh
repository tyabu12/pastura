#!/bin/bash
# Resolve a usable iOS Simulator destination for xcodebuild and export a
# workspace-relative DerivedData path. Sources into the caller's shell and
# exports DEST and DERIVED_DATA.
#
# Usage:
#   source scripts/sim-dest.sh
#   xcodebuild test ... -destination "$DEST" -derivedDataPath "$DERIVED_DATA"
#
# Why DERIVED_DATA: Xcode.app honors Workspace-relative DerivedData via
# xcshareddata/WorkspaceSettings.xcsettings, but `xcodebuild` CLI ignores
# that file entirely. Passing -derivedDataPath keeps CLI test runs aligned
# with the GUI layout (Pastura/DerivedData/) so `git worktree remove`
# auto-cleans all build artifacts.
#
# NOTE: pass -derivedDataPath with a SPACE separator, not `=`. The `=` form
# is silently ignored by xcodebuild (known since Xcode 15.4).
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
_simdest_errfile=$(mktemp)
_simdest_result=$(python3 -c "
import json, subprocess, sys, re

priority = sys.argv[1:]
raw = subprocess.check_output(
    ['xcrun', 'simctl', 'list', 'devices', 'available', '--json'],
    text=True,
)
data = json.loads(raw)

# Sort runtimes in reverse so newest OS is preferred for each device name
for name in priority:
    for runtime_id in sorted(data.get('devices', {}).keys(), reverse=True):
        for device in data['devices'][runtime_id]:
            if device['name'] == name:
                m = re.search(r'iOS-(\d+)-(\d+)', runtime_id)
                os_ver = f'iOS {m.group(1)}.{m.group(2)}' if m else runtime_id
                print(f\"{device['udid']}|{name}|{os_ver}\")
                sys.exit(0)

sys.exit(1)
" "${SIMULATOR_NAMES[@]}" 2>"$_simdest_errfile") || true

if [ -z "$_simdest_result" ]; then
  echo "Error: No available iOS Simulator found. Tried: ${SIMULATOR_NAMES[*]}" >&2
  [ -s "$_simdest_errfile" ] && echo "Details:" >&2 && cat "$_simdest_errfile" >&2
  rm -f "$_simdest_errfile"
  eval "$_simdest_old_opts"
  return 1 2>/dev/null || exit 1
fi
rm -f "$_simdest_errfile"

_simdest_udid=$(echo "$_simdest_result" | cut -d'|' -f1)
_simdest_name=$(echo "$_simdest_result" | cut -d'|' -f2)
_simdest_os=$(echo "$_simdest_result" | cut -d'|' -f3)

export DEST="platform=iOS Simulator,id=$_simdest_udid"

# Matches the Xcode.app GUI's Workspace-relative DerivedData layout
# (Pastura/DerivedData/), so the CLI and GUI share one build cache per
# worktree. Removing a worktree therefore cleans both.
# Guard: if sourced from outside a git worktree, fail loud and restore
# the caller's shell options before returning (otherwise set -e would
# abort the script with pipefail still active in the caller's shell).
_simdest_repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "Error: scripts/sim-dest.sh must be sourced from inside the git worktree." >&2
  eval "$_simdest_old_opts"
  return 1 2>/dev/null || exit 1
}
export DERIVED_DATA="$_simdest_repo_root/Pastura/DerivedData"
echo "Selected simulator: $_simdest_name ($_simdest_os) [id=$_simdest_udid]"
echo "DerivedData path: $DERIVED_DATA"

# Wait for any other in-flight `xcodebuild test` against an iOS Simulator
# to finish before returning. Concurrent test runs against the same
# simulator UDID corrupt clone/boot/teardown state: when one sim clone
# crashes mid-suite, the run reports 200+ 0.000s "failed" cascades that
# look like a real regression but disappear on re-run.
# Override with PASTURA_SKIP_SIM_WAIT=1 when intentional parallelism is
# wanted (e.g. distinct simulators per worktree).
_simdest_wait_for_simulator() {
  if [ "${PASTURA_SKIP_SIM_WAIT:-}" = "1" ]; then
    return 0
  fi
  # Match only UDID-pinned destinations (`...,id=<UDID>`). This is the form
  # sim-dest.sh produces and the only one that actually clones/boots/tears
  # down a simulator. Excludes `generic/platform=iOS Simulator` (used by
  # the pre-commit `xcodebuild build` hook) and any other non-booting form.
  local pattern='xcodebuild.*-destination.*platform=iOS Simulator,id='
  local poll_interval=5
  local timeout_s=900
  local elapsed=0
  local notified=0
  local busy_pids jitter
  while :; do
    # Exclude $$ and $PPID to avoid self-trigger: when sim-dest.sh is
    # sourced from `sh -c "source ... && xcodebuild test ..."`, the
    # wrapping shell's own argv contains the pattern, so pgrep -f matches
    # it. $$ inside the function resolves to that wrapping shell's PID
    # (not pgrep's subshell). $PPID covers a one-deeper nesting (e.g.
    # `bash -c "sh -c '... && xcodebuild ...'"`), where the grandparent
    # also carries the pattern in its argv.
    busy_pids=$(pgrep -f "$pattern" 2>/dev/null | grep -vE "^($$|$PPID)\$" || true)
    if [ -n "$busy_pids" ]; then
      if [ "$notified" -eq 0 ]; then
        echo "Another xcodebuild test detected (pids: $(echo "$busy_pids" | tr '\n' ' ')); waiting up to ${timeout_s}s. Set PASTURA_SKIP_SIM_WAIT=1 to bypass." >&2
        notified=1
      fi
      sleep "$poll_interval"
      elapsed=$((elapsed + poll_interval))
      if [ "$elapsed" -ge "$timeout_s" ]; then
        echo "Error: timed out after ${timeout_s}s waiting for in-flight xcodebuild test." >&2
        echo "  Likely cause: a stale xcodebuild/testmanagerd/XCTRunner from a prior timeout-killed run." >&2
        echo "  Inspect:  pgrep -af 'xcodebuild.*-destination.*platform=iOS Simulator,id='" >&2
        echo "  Recover:  pkill -f 'xcodebuild test'   (only after confirming the PID is yours and stale)" >&2
        echo "  Bypass:   PASTURA_SKIP_SIM_WAIT=1 source scripts/sim-dest.sh" >&2
        return 1
      fi
      continue
    fi
    # Random jitter (1.0–5.0s, 1 decimal) before claiming the simulator,
    # then re-check. Reduces thundering-herd when multiple waiters detect
    # the same "clear" moment after a competing run finishes.
    jitter=$(python3 -c "import random; print(f'{random.uniform(1.0, 5.0):.1f}')" 2>/dev/null) || jitter="2.5"
    sleep "$jitter"
    busy_pids=$(pgrep -f "$pattern" 2>/dev/null | grep -vE "^($$|$PPID)\$" || true)
    if [ -z "$busy_pids" ]; then
      return 0
    fi
    if [ "$notified" -eq 1 ]; then
      echo "Another session entered during jitter window; resuming wait..." >&2
    fi
  done
}

if ! _simdest_wait_for_simulator; then
  unset _simdest_result _simdest_udid _simdest_name _simdest_os _simdest_errfile _simdest_repo_root
  unset -f _simdest_wait_for_simulator
  eval "$_simdest_old_opts"
  return 1 2>/dev/null || exit 1
fi

unset _simdest_result _simdest_udid _simdest_name _simdest_os _simdest_errfile _simdest_repo_root
unset -f _simdest_wait_for_simulator
eval "$_simdest_old_opts"
# return when sourced, exit when executed directly
return 0 2>/dev/null || exit 0
