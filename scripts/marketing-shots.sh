#!/usr/bin/env bash
# marketing-shots.sh — Capture the Zenn-article "inference screenshots" (ja, 6.9").
#
# Runs PasturaUITests/MarketingShotTests pinned to the 6.9" iPhone
# (iPhone 17 Pro Max) in ja, then extracts the per-fixture PNG attachments and
# routes them into docs/marketing/screenshots/ (gitignored). The shots render
# the two curated transcripts from docs/marketing/launch-transcripts.md through
# the real ResultDetailView timeline (seeded verbatim by StubResultSeeder).
#
# ja / light only, and light is now a CHOICE this script enforces rather than a
# property of the app: #1284 removed Info.plist's UIUserInterfaceStyle, so the
# app follows the device and all 69 ADR-028 pairs resolve. A dark marketing set
# is deferred (#1274 discussion) — until someone decides to add one, this
# captures light. Local-run only by design — MarketingShotTests is CI-skipped
# (6.9"-pinned, UI-test flake class).
# Output PNGs are gitignored; this is the single regeneration path.
#
# Usage: scripts/marketing-shots.sh
# Requires: jq (brew install jq); an available "iPhone 17 Pro Max" simulator.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$REPO_ROOT/docs/marketing/screenshots"
RESULT_BUNDLE="$REPO_ROOT/Pastura/DerivedData/marketing-shots.xcresult"

# 6.9" device (1320x2868). Pin it via PASTURA_SIM_NAME (sim-dest.sh honors it)
# rather than appending a second `-destination` — xcodebuild runs tests on EVERY
# -destination given, so an append would also run on the wrapper's default 6.3"
# iPhone 17 Pro. sim-dest.sh's default list has no 6.9" device.
export PASTURA_SIM_NAME="iPhone 17 Pro Max"

if ! command -v jq > /dev/null 2>&1; then
  echo "ERROR: jq is required (brew install jq)" >&2
  exit 1
fi

# The capture changes no source; skip the wrapper's xcstrings auto-sync so a
# run never leaves an unexpected Localizable.xcstrings diff.
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
  -only-testing PasturaUITests/MarketingShotTests \
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
mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/*.png

# The exporter names files "<name>_<index>_<UUID>.png"; split("_")[0] recovers
# the XCTAttachment name, which is "{fixture}-NN-desc" (no underscores, by
# construction in MarketingShotTests). Route into docs/marketing/screenshots/.
count=0
while IFS=$'\t' read -r exported base; do
  case "$base" in
    wordwolf-[0-9][0-9]-* | prisoners-[0-9][0-9]-*) ;;
    *)
      echo "ERROR: capture name '$base' must be {wordwolf|prisoners}-NN-desc (kebab, no underscores)" >&2
      exit 1
      ;;
  esac
  dest="$OUT_DIR/$base.png"
  if [ -e "$dest" ]; then
    echo "ERROR: duplicate screenshot '$dest' — capture names must be unique" >&2
    exit 1
  fi
  cp "$EXPORT_DIR/$exported" "$dest"
  echo "  $base.png"
  count=$((count + 1))
done < <(
  jq -r '
    .[].attachments[]
    | select(.suggestedHumanReadableName | test("^(wordwolf|prisoners)-[0-9]{2}-"))
    | "\(.exportedFileName)\t\(.suggestedHumanReadableName | split("_")[0])"
  ' "$MANIFEST"
)

if [ "$count" -eq 0 ]; then
  echo "ERROR: no marketing attachments ({wordwolf,prisoners}-NN-*) found in $RESULT_BUNDLE" >&2
  exit 1
fi

echo "Exported $count screenshot(s) to $OUT_DIR"
