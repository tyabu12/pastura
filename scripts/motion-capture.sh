#!/usr/bin/env bash
# motion-capture.sh — Record app animations into static review artifacts.
#
# Records the simulator display with `xcrun simctl io <UDID> recordVideo`
# while a forced launch animation plays, then expands the recording with
# ffmpeg into a horizontally-tiled filmstrip plus the individual frames,
# under docs/design/motion/<variant>/. The artifacts give a human or agent
# a *time axis* on motion that a single screenshot can't convey.
#
# Launch-animation variants (the app-launch sequence — see
# Pastura/Pastura/Views/Splash/ and LaunchAnimationConfig):
#   cold          — "Pastoral Drift" full cold-launch splash
#   warm          — abbreviated "Breath" warm-launch splash
#   reduce-motion — cold splash with the Reduce Motion fallback
#   all (default) — the three launch variants in sequence
#
# Other variants (explicit-only — NOT part of `all`, different in nature):
#   demo          — the DL-time demo replay screen, for verifying the
#                   chat-stream TYPING animation speed frame-by-frame
#                   (the filmstrip gives a time axis; count the characters
#                   revealed per frame at MOTION_FPS to read off chars/sec).
#
# How the launch animation is forced: under `--ui-test` the splash is
# normally suppressed (PasturaApp.swift). The DEBUG-only `--capture-launch`
# / `--capture-launch-warm` args (added alongside this script) override that
# so the splash plays over the `--ui-test` Home fixtures, and the exit
# transition reveals Home. Reduce Motion is driven by the simulator
# accessibility setting (ColdSplashView reads `@Environment(\.
# accessibilityReduceMotion)`; that key is read-only in Swift 6, so it can't
# be injected from code).
#
# How the demo replay is forced: the DEBUG-only `--capture-demo` arg
# (PasturaApp.swift) seeds the active model into `.downloading` and routes to
# `.needsModelDownload`, so `ModelDownloadHostView` renders the bundled demo
# replay — WITHOUT a real download. It does NOT use `--ui-test` (that would
# short-circuit to `.ready` and never reach the demo host).
#
# Local-run only by design — generated artifacts are gitignored (only the
# README is tracked), and this is NOT a CI gate (same posture as
# scripts/ui-tour.sh). Do NOT run concurrently with scripts/ui-tour.sh or
# `xcodebuild test` against the same simulator: this script mutates the
# simulator's Reduce Motion setting and holds a video recorder, and the
# sim-dest.sh gate only sees `xcodebuild test`, not `simctl io`.
#
# Usage: scripts/motion-capture.sh [cold|warm|reduce-motion|all|demo]
# Env:   MOTION_FPS (default 12)   — frame extraction rate (bump it, e.g.
#        MOTION_FPS=24, for finer chars/sec resolution on the `demo` variant)
#        MOTION_THUMB_W (default 160) — per-frame width (px) in the filmstrip
# Requires: ffmpeg (brew install ffmpeg)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_ROOT="$REPO_ROOT/docs/design/motion"
FPS="${MOTION_FPS:-12}"
THUMB_W="${MOTION_THUMB_W:-160}"
ACCESSIBILITY_DOMAIN="com.apple.Accessibility"
REDUCE_MOTION_KEY="ReduceMotionEnabled"
# Minimum plausible recording size — a too-short / clipped capture finalizes
# far smaller than this, so it lets an empty filmstrip fail loudly instead.
MIN_MOV_BYTES=10240

if ! command -v ffmpeg > /dev/null 2>&1; then
  echo "ERROR: ffmpeg is required (brew install ffmpeg)" >&2
  exit 1
fi

VARIANT="${1:-all}"
case "$VARIANT" in
  cold | warm | reduce-motion | all | demo) ;;
  *)
    echo "ERROR: unknown variant '$VARIANT' (expected: cold | warm | reduce-motion | all | demo)" >&2
    exit 1
    ;;
esac

# Resolve a simulator destination + DerivedData path and respect the
# concurrent-`xcodebuild test` gate (see .claude/rules/xcodebuild-cli.md).
# shellcheck source=/dev/null
source "$REPO_ROOT/scripts/sim-dest.sh"
# sim-dest.sh restores the *pre-source* shell options on exit, which clears
# our `set -e`; re-assert it so the rest of the script still fails fast.
set -euo pipefail
UDID="${DEST##*id=}"

# State the cleanup trap restores. REC_PID is cleared after each variant's
# recorder stops cleanly, so the trap only acts on an interrupted run.
REC_PID=""
PRIOR_RM=""

set_reduce_motion() {
  # $1: 1 to enable, 0 to disable.
  local flag="NO"
  [ "$1" = "1" ] && flag="YES"
  xcrun simctl spawn "$UDID" defaults write \
    "$ACCESSIBILITY_DOMAIN" "$REDUCE_MOTION_KEY" -bool "$flag" > /dev/null 2>&1 || true
  # Post the Darwin notification so a fresh launch reads the new value.
  xcrun simctl spawn "$UDID" notifyutil \
    -p com.apple.Accessibility.ReduceMotionStatusDidChange > /dev/null 2>&1 || true
}

restore_reduce_motion() {
  [ -z "${UDID:-}" ] && return 0
  if [ -z "$PRIOR_RM" ]; then
    # Key was absent before the run — remove it rather than forcing a value.
    xcrun simctl spawn "$UDID" defaults delete \
      "$ACCESSIBILITY_DOMAIN" "$REDUCE_MOTION_KEY" > /dev/null 2>&1 || true
    xcrun simctl spawn "$UDID" notifyutil \
      -p com.apple.Accessibility.ReduceMotionStatusDidChange > /dev/null 2>&1 || true
  else
    set_reduce_motion "$PRIOR_RM"
  fi
}

cleanup() {
  # Stop a still-running recorder (interrupted mid-capture). SIGINT is the
  # only signal that makes recordVideo flush the moov atom — SIGTERM/KILL
  # corrupt the file.
  if [ -n "$REC_PID" ]; then
    kill -INT "$REC_PID" 2> /dev/null || true
    wait "$REC_PID" 2> /dev/null || true
  fi
  restore_reduce_motion
}
trap cleanup EXIT INT TERM

# Build once (all variants share the same binary). Skip the xcstrings
# auto-sync — this script changes no source, so the catalog must not move.
export PASTURA_SKIP_XCSTRINGS_SYNC=1
echo "Building Pastura (Debug, simulator)..."
"$REPO_ROOT/scripts/xcodebuild.sh" build > /dev/null

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Pastura.app"
if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: built app not found at $APP_PATH" >&2
  exit 1
fi
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist")"

echo "Booting simulator $UDID..."
xcrun simctl boot "$UDID" > /dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" > /dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP_PATH"

# Capture the pre-run Reduce Motion value so the trap restores exactly that
# (another tool or the operator may legitimately have it on). `defaults read`
# prints 0/1, or errors when the key is absent (→ empty PRIOR_RM).
PRIOR_RM="$(xcrun simctl spawn "$UDID" defaults read \
  "$ACCESSIBILITY_DOMAIN" "$REDUCE_MOTION_KEY" 2> /dev/null | tr -d '[:space:]' || true)"

# Warm up dyld / disk caches. The first launch after install can take
# several seconds to foreground, which would clip the splash to the tail of
# the recording window; a throwaway launch (no splash needed) pays that cost
# once so each recorded launch foregrounds promptly. Caches stay warm for
# the rest of this boot session, so one warm-up covers all variants.
echo "Warming up launch caches..."
xcrun simctl launch "$UDID" "$BUNDLE_ID" --ui-test > /dev/null 2>&1 || true
sleep 4
xcrun simctl terminate "$UDID" "$BUNDLE_ID" > /dev/null 2>&1 || true

# The `--ui-test` warm-up above boots into the in-memory MockLLM path, which
# does NOT warm the `--capture-demo` init (AppDependencies.production() + demo
# resource load). Pay that distinct cold cost once so the demo capture_window
# below isn't spent waiting on first-launch init instead of the typing it
# means to record.
if [ "$VARIANT" = "demo" ]; then
  echo "Warming up demo-replay init path..."
  xcrun simctl launch "$UDID" "$BUNDLE_ID" --capture-demo > /dev/null 2>&1 || true
  sleep 4
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" > /dev/null 2>&1 || true
fi

# capture_one <variant>: record a single launch animation and expand it.
capture_one() {
  local variant="$1"
  local launch_args reduce_motion capture_window
  case "$variant" in
    cold)
      launch_args="--ui-test --capture-launch"
      reduce_motion=0
      # coldDuration 1.2s + up to 1.0s init extension + ~0.34s exit, plus
      # headroom to also catch Home settling underneath.
      capture_window=3.5
      ;;
    reduce-motion)
      launch_args="--ui-test --capture-launch"
      reduce_motion=1
      # Parent hold still uses coldDuration (only the inner fade shortens),
      # so the window matches cold.
      capture_window=3.5
      ;;
    warm)
      launch_args="--ui-test --capture-launch-warm"
      reduce_motion=0
      # warmDuration 0.7s (~0.5s hold + ~0.2s exit); extra to show Home.
      capture_window=2.0
      ;;
    demo)
      launch_args="--capture-demo"
      reduce_motion=0
      # Sized for a COLD demo-host boot (the --ui-test cache warm-up does not
      # warm the --capture-demo production-init path) PLUS a generous stretch
      # of the chat-stream typing animation — the actual thing being measured.
      # The replay loops through several demos, so over-shooting just captures
      # more typing; under-shooting clips it. Re-run with a larger value (or
      # a higher MOTION_FPS) if the first agent bubble doesn't finish on screen.
      capture_window=18.0
      ;;
  esac

  local variant_dir="$OUT_ROOT/$variant"
  local frame_dir="$variant_dir/frames"
  local mov="$variant_dir/recording.mov"
  # Full refresh so stale frames from a prior run never linger.
  rm -rf "$variant_dir"
  mkdir -p "$frame_dir"

  echo "[$variant] preparing (Reduce Motion: $([ "$reduce_motion" = 1 ] && echo on || echo off))"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" > /dev/null 2>&1 || true
  set_reduce_motion "$reduce_motion"

  echo "[$variant] starting recorder..."
  # recordVideo buffers and only writes the file at finalize (on SIGINT),
  # so file growth can't signal readiness — instead poll its stderr for the
  # "Recording started" line before launching, so the splash's opening
  # frames (the point of the artifact) aren't clipped.
  local rec_log="$variant_dir/.recorder.log"
  xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$mov" \
    > "$rec_log" 2>&1 &
  REC_PID=$!
  local waited=0
  while ! grep -q "Recording started" "$rec_log" 2> /dev/null; do
    # Bail immediately if the recorder process already died (bad codec,
    # device not booted, disk full) instead of spinning the full timeout.
    kill -0 "$REC_PID" 2> /dev/null || break
    [ "$waited" -ge 50 ] && break
    sleep 0.1
    waited=$((waited + 1))
  done
  if ! grep -q "Recording started" "$rec_log" 2> /dev/null; then
    echo "ERROR: [$variant] recorder never reported 'Recording started':" >&2
    sed 's/^/  /' "$rec_log" >&2 2> /dev/null || true
    return 1
  fi
  sleep 0.3  # small safety margin so frame 0 is the static LaunchScreen

  echo "[$variant] launching app (${capture_window}s window)..."
  # shellcheck disable=SC2086  # launch_args is an intentional word list
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" $launch_args > /dev/null
  sleep "$capture_window"

  echo "[$variant] finalizing recording..."
  kill -INT "$REC_PID" 2> /dev/null || true
  wait "$REC_PID" 2> /dev/null || true
  REC_PID=""

  local bytes
  bytes="$(stat -f%z "$mov" 2> /dev/null || echo 0)"
  if [ "$bytes" -lt "$MIN_MOV_BYTES" ]; then
    echo "ERROR: [$variant] recording is only ${bytes}B (<${MIN_MOV_BYTES}B) — capture failed" >&2
    return 1
  fi

  echo "[$variant] extracting frames @ ${FPS}fps..."
  # Explicit guard (not bare set -e): when capture_one is called via `||` in
  # the `all` loop, set -e is suppressed inside it, so each fallible step
  # must check itself.
  ffmpeg -hide_banner -loglevel error -y -i "$mov" \
    -vf "fps=$FPS" "$frame_dir/frame_%03d.png" \
    || { echo "ERROR: [$variant] ffmpeg frame extraction failed" >&2; return 1; }

  local frame_count
  frame_count="$(find "$frame_dir" -name 'frame_*.png' | wc -l | tr -d ' ')"
  if [ "$frame_count" -eq 0 ]; then
    echo "ERROR: [$variant] ffmpeg produced no frames" >&2
    return 1
  fi

  echo "[$variant] building filmstrip ($frame_count frames)..."
  # Tile the extracted PNGs (not a second pass over the .mov) so the column
  # count provably matches the input count — a re-extract could differ by a
  # frame and leave the tile filter waiting forever.
  ffmpeg -hide_banner -loglevel error -y \
    -framerate "$FPS" -pattern_type glob -i "$frame_dir/frame_*.png" \
    -vf "scale=${THUMB_W}:-1,tile=${frame_count}x1" -frames:v 1 \
    "$variant_dir/filmstrip.png" \
    || { echo "ERROR: [$variant] ffmpeg filmstrip build failed" >&2; return 1; }

  rm -f "$rec_log"
  echo "[$variant] done → docs/design/motion/$variant/ (filmstrip.png + $frame_count frames)"
}

# Continue past a transient per-variant failure so one flake doesn't deny
# the other artifacts. capture_one self-guards each fallible step, so the
# `||` (which suppresses set -e inside the call) is safe. A plain string
# accumulator avoids the bash 3.2 empty-array-under-`set -u` pitfall.
FAILED=""
if [ "$VARIANT" = "all" ]; then
  for v in cold warm reduce-motion; do
    capture_one "$v" || FAILED="$FAILED $v"
  done
else
  capture_one "$VARIANT" || FAILED="$FAILED $VARIANT"
fi

if [ -n "$FAILED" ]; then
  echo "Motion capture finished with failures:$FAILED" >&2
  exit 1
fi

echo "Motion capture complete. Artifacts under docs/design/motion/ (gitignored)."
