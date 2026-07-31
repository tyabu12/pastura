#!/usr/bin/env bash
# store-shots.sh — Capture the App Store screenshot set (en + ja, 6.9").
#
# Runs PasturaUITests/StoreScreenshotTests pinned to the 6.9" iPhone
# (iPhone 17 Pro Max → 1320x2868, the only App-Store-required iPhone size;
# ASC auto-scales it to smaller devices), extracts the per-locale PNG
# attachments, routes them into docs/store/screenshots/{en,ja}/, and verifies
# each is exactly 1320x2868 with no alpha channel (ASC rejects both a size
# mismatch and an alpha channel).
#
# Local-run only by design — StoreScreenshotTests is CI-skipped (6.9"-pinned,
# UI-test flake class). Output PNGs are gitignored (docs/store/screenshots/);
# this is the single regeneration path. See docs/store/screenshot-plan.md.
#
# A tab-switch failure here is NOT the structural-`Tab` identifier drop —
# `tapTab`'s label fallback already absorbs that (.claude/rules/uitest-traps.md).
# It means the localized label literal drifted (StoreCaptureTabLabelTests guards
# it) or the tab bar never appeared. Do not just re-run.
#
# Usage: scripts/store-shots.sh
# Requires: jq (brew install jq); an available "iPhone 17 Pro Max" simulator.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_ROOT="$REPO_ROOT/docs/store/screenshots"
RESULT_BUNDLE="$REPO_ROOT/Pastura/DerivedData/store-shots.xcresult"
# 6.9" device: the only App-Store-required iPhone size (1320x2868). Pin it via
# PASTURA_SIM_NAME (sim-dest.sh honors it) rather than appending a second
# `-destination` — xcodebuild runs tests on EVERY -destination given, so an
# append would also run on the wrapper's default 6.3" iPhone 17 Pro and produce
# wrong-size shots. sim-dest.sh's default list has no 6.9" device.
export PASTURA_SIM_NAME="iPhone 17 Pro Max"
EXPECT_W=1320
EXPECT_H=2868

if ! command -v jq > /dev/null 2>&1; then
  echo "ERROR: jq is required (brew install jq)" >&2
  exit 1
fi

# The tour changes no source; skip the wrapper's xcstrings auto-sync so a
# capture run never leaves an unexpected Localizable.xcstrings diff.
export PASTURA_SKIP_XCSTRINGS_SYNC=1

# Appearance pin. With the app no longer forcing light, the capture renders in
# whatever appearance the SIMULATOR is set to — and that setting persists across
# runs, so one session that flipped a device to dark would silently keep
# producing dark shots. Pin it here instead of trusting operator state.
# `simctl ui` needs a booted device (CoreSimulator error 405 on Shutdown), hence
# the explicit boot; xcodebuild boots the same device moments later anyway.
# Sourced WITHOUT PASTURA_SKIP_SIM_WAIT: appearance is device-global state, so
# writing it must happen inside the concurrent-session gate — skipping the wait
# would flip the appearance of another session's in-flight `xcodebuild test` on
# the same simulator. `scripts/motion-capture.sh` sources with the gate for the
# same reason. Sourcing restores the caller's shell options on exit, which drops
# errexit — hence both the explicit `||` on the source itself (errexit is
# provably off at the instant it returns) and the re-assert below
# (.claude/rules/xcodebuild-cli.md § "Sourcing it in a script clears your
# `set -e`"; measured by reading $-, not `set -o` inside a command substitution,
# which reports "off" regardless).
# shellcheck source=/dev/null
source "$REPO_ROOT/scripts/sim-dest.sh" \
  || { echo "ERROR: simulator resolution failed (PASTURA_SIM_NAME=$PASTURA_SIM_NAME)" >&2; exit 1; }
set -euo pipefail
SIM_UDID="${DEST##*,id=}"
SIM_UDID="${SIM_UDID%%,*}"
xcrun simctl bootstatus "$SIM_UDID" -b > /dev/null 2>&1 || true

# Restore the operator's appearance on exit. Without this the light pin below
# persists — appearance is device-global — and scripts/motion-capture.sh, which
# is deliberately device-following, would then record light filmstrips for an
# operator who had deliberately set dark. `simctl ui <dev> appearance` with no
# value prints the current style but can also print `unsupported` / `unknown`;
# anything else is left empty and the restore skipped, because defaulting to a
# value would flip a device rather than leave it as found. Same shape and same
# single-trap constraint as scripts/ui-tour.sh — see its cleanup() for why the
# two handlers must be one (bash replaces a trap, it does not chain).
PRIOR_APPEARANCE="$(xcrun simctl ui "$SIM_UDID" appearance 2> /dev/null || true)"
case "$PRIOR_APPEARANCE" in
  light | dark) ;;
  *) PRIOR_APPEARANCE="" ;;
esac

cleanup() {
  if [ -n "$PRIOR_APPEARANCE" ]; then
    xcrun simctl ui "$SIM_UDID" appearance "$PRIOR_APPEARANCE" > /dev/null 2>&1 || true
  fi
  [ -n "${EXPORT_DIR:-}" ] && rm -rf "$EXPORT_DIR"
  return 0
}
trap cleanup EXIT INT TERM

xcrun simctl ui "$SIM_UDID" appearance light > /dev/null

# xcodebuild refuses to write into a pre-existing result bundle.
rm -rf "$RESULT_BUNDLE"

"$REPO_ROOT/scripts/xcodebuild.sh" test \
  -only-testing PasturaUITests/StoreScreenshotTests \
  -resultBundlePath "$RESULT_BUNDLE"

EXPORT_DIR="$(mktemp -d)"

xcrun xcresulttool export attachments \
  --path "$RESULT_BUNDLE" --output-path "$EXPORT_DIR"

MANIFEST="$EXPORT_DIR/manifest.json"
if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: attachment manifest not found at $MANIFEST" >&2
  exit 1
fi

# Full refresh: drop stale PNGs from any prior run (only generated files live
# here — the directory is gitignored).
for loc in en ja; do
  mkdir -p "$OUT_ROOT/$loc"
  rm -f "$OUT_ROOT/$loc"/*.png
done

# ASC rejects alpha PNGs. Simulator screenshots are opaque in practice, so
# this rarely fires; when it does, flatten in place onto white.
strip_alpha() {
  local f="$1"
  if [ "$(sips -g hasAlpha "$f" | awk '/hasAlpha/{print $2}')" != "yes" ]; then
    return
  fi
  if command -v magick > /dev/null 2>&1; then
    magick "$f" -background white -alpha remove -alpha off "$f"
  elif command -v convert > /dev/null 2>&1; then
    convert "$f" -background white -alpha remove -alpha off "$f"
  else
    # Built-in fallback: round-trip through alpha-less BMP. Opaque content is
    # preserved losslessly; only the unused alpha channel is dropped.
    local tmp="${f%.png}.flatten.bmp"
    sips -s format bmp "$f" --out "$tmp" > /dev/null
    sips -s format png "$tmp" --out "$f" > /dev/null
    rm -f "$tmp"
  fi
}

verify_png() {
  local f="$1" w h a
  w="$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')"
  h="$(sips -g pixelHeight "$f" | awk '/pixelHeight/{print $2}')"
  a="$(sips -g hasAlpha "$f" | awk '/hasAlpha/{print $2}')"
  if [ "$w" != "$EXPECT_W" ] || [ "$h" != "$EXPECT_H" ]; then
    echo "ERROR: $f is ${w}x${h}, expected ${EXPECT_W}x${EXPECT_H}" >&2
    exit 1
  fi
  if [ "$a" = "yes" ]; then
    echo "ERROR: $f still has an alpha channel (ASC rejects alpha PNGs). Flatten it with:" >&2
    echo "  magick '$f' -background white -alpha remove -alpha off '$f'" >&2
    exit 1
  fi
}

# The exporter names files "<name>_<index>_<UUID>.png"; split("_")[0] recovers
# the XCTAttachment name, which for store shots is "{locale}-NN-screen" (no
# underscores, by construction in StoreScreenshotTests). Route by the locale
# prefix into docs/store/screenshots/{en,ja}/NN-screen.png.
count=0
while IFS=$'\t' read -r exported base; do
  case "$base" in
    en-[0-9][0-9]-* | ja-[0-9][0-9]-*) ;;
    *)
      echo "ERROR: capture name '$base' must be {en|ja}-NN-screen (kebab, no underscores)" >&2
      exit 1
      ;;
  esac
  loc="${base%%-*}"       # en | ja
  rest="${base#*-}"       # NN-screen
  dest="$OUT_ROOT/$loc/$rest.png"
  if [ -e "$dest" ]; then
    echo "ERROR: duplicate screenshot '$dest' — capture names must be unique" >&2
    exit 1
  fi
  cp "$EXPORT_DIR/$exported" "$dest"
  strip_alpha "$dest"
  verify_png "$dest"
  echo "  $loc/$rest.png"
  count=$((count + 1))
done < <(
  jq -r '
    .[].attachments[]
    | select(.suggestedHumanReadableName | test("^(en|ja)-[0-9]{2}-"))
    | "\(.exportedFileName)\t\(.suggestedHumanReadableName | split("_")[0])"
  ' "$MANIFEST"
)

if [ "$count" -eq 0 ]; then
  echo "ERROR: no store attachments ({en,ja}-NN-*) found in $RESULT_BUNDLE" >&2
  exit 1
fi

echo "Exported $count screenshot(s) to $OUT_ROOT/{en,ja} (verified ${EXPECT_W}x${EXPECT_H}, no alpha)"
