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
# Usage: scripts/ui-tour.sh
# Requires: jq (brew install jq)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$REPO_ROOT/docs/design/screenshots"
RESULT_BUNDLE="$REPO_ROOT/Pastura/DerivedData/ui-tour.xcresult"

if ! command -v jq > /dev/null 2>&1; then
  echo "ERROR: jq is required (brew install jq)" >&2
  exit 1
fi

# The tour changes no source; skip the wrapper's xcstrings auto-sync so
# regenerating screenshots never leaves an unexpected Localizable.xcstrings
# diff in the working tree (the git pre-commit hook sets the same skip for
# the same reason).
export PASTURA_SKIP_XCSTRINGS_SYNC=1

# xcodebuild refuses to write into a pre-existing result bundle; pre-clean
# so re-runs are idempotent.
rm -rf "$RESULT_BUNDLE"

"$REPO_ROOT/scripts/xcodebuild.sh" test \
  -only-testing PasturaUITests/ScreenshotTourTests \
  -resultBundlePath "$RESULT_BUNDLE"

EXPORT_DIR="$(mktemp -d)"
trap 'rm -rf "$EXPORT_DIR"' EXIT

xcrun xcresulttool export attachments \
  --path "$RESULT_BUNDLE" --output-path "$EXPORT_DIR"

MANIFEST="$EXPORT_DIR/manifest.json"
if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: attachment manifest not found at $MANIFEST" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
# Full refresh: drop stale PNGs from screens that no longer exist in the
# tour. Only generated files live here (the directory is gitignored except
# for README.md).
rm -f "$OUT_DIR"/*.png

# The exporter assigns opaque on-disk filenames; the XCTAttachment name we
# set in capture(name:) surfaces as suggestedHumanReadableName in the form
# "<name>_<index>_<UUID>.png". split("_")[0] recovers <name>, which is why
# capture names must be NN-kebab-case with no underscores (enforced by the
# NN- prefix filter convention in ScreenshotTourTests). The filter also
# keeps auto-generated failure screenshots and diagnostics out.
count=0
while IFS=$'\t' read -r exported base; do
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
