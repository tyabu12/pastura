#!/usr/bin/env bash
# ui-tour.sh — Regenerate the design-review screenshot set.
#
# Runs the ScreenshotTourTests UI tour (review-only capture — no
# assertions against stored references; see the ADR-009 note) on the
# UDID-pinned simulator via scripts/xcodebuild.sh, then extracts the
# tour's PNG attachments from the xcresult bundle into
# docs/design/screenshots/. The PNGs are gitignored; this script is
# the single regeneration path (see docs/design/screenshots/README.md).
#
# Local-run only by design — the tour class is skipped on CI
# (-skip-testing in ci.yml) because it gates nothing and UI-test jobs
# on GHA runners carry known infrastructure flakes.
#
# Usage: scripts/ui-tour.sh [--light | --dark]
#   --light (default) → docs/design/screenshots/
#   --dark            → docs/design/screenshots/dark/
# The simulator's prior appearance is restored on exit either way.
# Requires: jq (brew install jq)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_BUNDLE="$REPO_ROOT/Pastura/DerivedData/ui-tour.xcresult"

# Appearance to capture. Opt-in rather than a both-appearances default: each
# pass is a full xcodebuild test run, so making dark automatic would double
# every routine regeneration for a set that reaches none of the dark risk
# classes (see docs/design/screenshots/README.md § Dark set).
APPEARANCE="light"
while [ $# -gt 0 ]; do
  case "$1" in
    --dark) APPEARANCE="dark" ;;
    --light) APPEARANCE="light" ;;
    *) echo "ERROR: unknown argument '$1' (expected --dark or --light)" >&2; exit 1 ;;
  esac
  shift
done

# The dark set lives in its own directory rather than carrying a filename
# suffix: the light set's NN-name.png filenames are referenced by name from
# this repo's docs and from .claude/skills/ui-refine, so they stay put. The
# per-run wipe and the duplicate-basename guard below are both non-recursive,
# so each set refreshes independently without touching the other.
OUT_DIR="$REPO_ROOT/docs/design/screenshots"
if [ "$APPEARANCE" = "dark" ]; then
  OUT_DIR="$OUT_DIR/dark"
fi

if ! command -v jq > /dev/null 2>&1; then
  echo "ERROR: jq is required (brew install jq)" >&2
  exit 1
fi

# The tour changes no source; skip the wrapper's xcstrings auto-sync so
# regenerating screenshots never leaves an unexpected Localizable.xcstrings
# diff in the working tree (the git pre-commit hook sets the same skip for
# the same reason).
export PASTURA_SKIP_XCSTRINGS_SYNC=1

# Appearance pin. #1284 removed Info.plist's UIUserInterfaceStyle, so the tour
# renders in whatever appearance the SIMULATOR is set to — and that setting
# persists across runs, so one session that flipped a device to dark would keep
# producing dark review screenshots. That persistence is also why this script
# RESTORES the prior appearance on exit (see cleanup below): `--dark` would
# otherwise leave the device dark for the next unrelated run, and
# scripts/motion-capture.sh is deliberately device-following — it would silently
# start recording dark filmstrips nobody asked for. `simctl ui` needs a booted device
# (CoreSimulator error 405 on Shutdown); xcodebuild boots the same one moments
# later anyway. Sourced WITH the concurrent-session gate: appearance is
# device-global, so writing it while another session holds the simulator would
# flip that run's appearance mid-suite. Sourcing drops errexit, hence both the
# explicit `||` and the re-assert (.claude/rules/xcodebuild-cli.md).
# shellcheck source=/dev/null
source "$REPO_ROOT/scripts/sim-dest.sh" \
  || { echo "ERROR: simulator resolution failed" >&2; exit 1; }
set -euo pipefail
SIM_UDID="${DEST##*,id=}"
SIM_UDID="${SIM_UDID%%,*}"
xcrun simctl bootstatus "$SIM_UDID" -b > /dev/null 2>&1 || true

# Save the prior appearance so the trap can put it back. `simctl ui <dev>
# appearance` with no value prints the current style, but it can also print
# `unsupported` / `unknown`. Anything that is not light/dark is left EMPTY and
# the restore is skipped: defaulting to `light` would make a failed read on a
# genuinely-dark device *flip* it, which is the one outcome this trap exists to
# prevent. Not restoring leaves the tour's own pin in place, which is no worse
# than the sibling capture scripts already are.
PRIOR_APPEARANCE="$(xcrun simctl ui "$SIM_UDID" appearance 2> /dev/null || true)"
case "$PRIOR_APPEARANCE" in
  light | dark) ;;
  *) PRIOR_APPEARANCE="" ;;
esac

# ONE cleanup handler: bash replaces a trap rather than chaining, so a second
# `trap … EXIT` further down would silently drop this restore (or leak the
# mktemp dir, depending on order). Same save/restore shape as
# scripts/motion-capture.sh's Reduce Motion handling. EXPORT_DIR does not exist
# yet — the guard is what lets the trap be armed here, immediately after the
# pin, so an early failure still restores the appearance.
cleanup() {
  if [ -n "$PRIOR_APPEARANCE" ]; then
    xcrun simctl ui "$SIM_UDID" appearance "$PRIOR_APPEARANCE" > /dev/null 2>&1 || true
  fi
  [ -n "${EXPORT_DIR:-}" ] && rm -rf "$EXPORT_DIR"
  return 0
}
trap cleanup EXIT INT TERM

xcrun simctl ui "$SIM_UDID" appearance "$APPEARANCE" > /dev/null

# xcodebuild refuses to write into a pre-existing result bundle; pre-clean
# so re-runs are idempotent.
rm -rf "$RESULT_BUNDLE"

"$REPO_ROOT/scripts/xcodebuild.sh" test \
  -only-testing PasturaUITests/ScreenshotTourTests \
  -resultBundlePath "$RESULT_BUNDLE"

EXPORT_DIR="$(mktemp -d)"

xcrun xcresulttool export attachments \
  --path "$RESULT_BUNDLE" --output-path "$EXPORT_DIR"

MANIFEST="$EXPORT_DIR/manifest.json"
if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: attachment manifest not found at $MANIFEST" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
# Full refresh: drop stale PNGs from screens that no longer exist in the
# tour. Only generated files live here (both directories are gitignored; the
# light one also tracks its README.md).
rm -f "$OUT_DIR"/*.png

# The exporter assigns opaque on-disk filenames; the XCTAttachment name we
# set in capture(name:) surfaces as suggestedHumanReadableName in the form
# "<name>_<index>_<UUID>.png". split("_")[0] recovers <name>, which is why
# capture names must be NN-kebab-case with no underscores (enforced by the
# NN- prefix filter convention in ScreenshotTourTests). The filter also
# keeps auto-generated failure screenshots and diagnostics out.
count=0
while IFS=$'\t' read -r exported base; do
  # Fail fast if a capture name breaks the NN-kebab-case/no-underscore
  # convention — silently truncating at the first "_" would otherwise
  # produce a wrong filename.
  case "$base" in
    [0-9][0-9]-*) ;;
    *)
      echo "ERROR: capture name '$base' violates NN-kebab-case convention" >&2
      exit 1
      ;;
  esac
  # An underscore-containing capture name truncates to a plausible-looking
  # base, so also catch the resulting collision (OUT_DIR was wiped above —
  # any pre-existing target this run is a duplicate).
  if [ -e "$OUT_DIR/$base.png" ]; then
    echo "ERROR: duplicate screenshot name '$base.png' — capture names must be unique and underscore-free" >&2
    exit 1
  fi
  cp "$EXPORT_DIR/$exported" "$OUT_DIR/$base.png"
  echo "  $base.png"
  count=$((count + 1))
done < <(
  jq -r '
    .[].attachments[]
    | select(.suggestedHumanReadableName | test("^[0-9]{2}-"))
    | "\(.exportedFileName)\t\(.suggestedHumanReadableName | split("_")[0])"
  ' "$MANIFEST"
)

if [ "$count" -eq 0 ]; then
  echo "ERROR: no tour attachments (NN-*) found in $RESULT_BUNDLE" >&2
  exit 1
fi

echo "Exported $count screenshot(s) to $OUT_DIR"
