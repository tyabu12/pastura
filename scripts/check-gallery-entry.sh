#!/usr/bin/env bash
# scripts/check-gallery-entry.sh — Validate gallery YAML entries against
# docs/gallery/gallery.json without writing.
#
# Usage:
#   bash scripts/check-gallery-entry.sh --all
#       Validates every entry in docs/gallery/gallery.json + id
#       uniqueness across gallery + bundled presets.
#   bash scripts/check-gallery-entry.sh docs/gallery/<id>.yaml
#       Validates a single YAML against its gallery.json entry plus the
#       cross-source uniqueness check. Use this from
#       add-gallery-entry.sh as a pre/post-write gate.
#
# Validations enforced here:
#   - YAML SHA-256 byte-match with gallery.json yaml_sha256
#   - YAML file size <= 256 KiB (matches URLSessionGalleryService.yamlSizeLimit)
#   - id uniqueness across gallery.json + Pastura/Pastura/Resources/Presets/*.yaml
#   - YAML filename stem == id field inside the YAML
#   - docs/gallery/highlights/<id>.json validity (ADR-029 Decision 2) —
#     delegated to scripts/gallery_highlight_validate.py, which re-derives the
#     schema/cap/source_field allowlist, the sha three-way (highlight pin ==
#     gallery.json == raw YAML bytes), the highlight_url ⟺ highlight_sha256 ⟺
#     file pairing (including the inverse orphan), the spoiler position rules
#     and the ContentBlocklist re-audit. This is the enforcement point: a
#     hand-edited highlight never runs the extractor.
#
# Validations covered elsewhere (kept here as a maintainer signpost so
# the next contributor does not duplicate them in bash):
#   - GalleryCategory enum membership          → GalleryCategory.allCases
#   - recommended_model in ModelRegistry       → GallerySeedYAMLTests
#                                                .recommendedModelMatchesRegistry
#   - title byte-equal to YAML name            → GallerySeedYAMLTests
#                                                .galleryTitleMatchesYAMLName
#   - YAML parse + ScenarioValidator pass      → GallerySeedYAMLTests
#                                                .allSeedYAMLsParseAndValidate
#   - yaml_sha256 byte-match (this script duplicates it; the Swift test
#     is the durable defense against --no-verify and GitHub-UI merges)
#                                              → GallerySeedYAMLTests
#                                                .galleryYAMLHashMatchesIndex
#
# Exit code: 0 on success, 1 on any violation. Failures aggregate so a
# single --all run reports every drift.

set -euo pipefail

# --- Dependency check ------------------------------------------------------

# Fail loudly with install hints, not an opaque "command not found"
# mid-pipe. shasum + awk + jq are present on macOS by default and on
# ubuntu-latest GHA runners; PyYAML must be installed explicitly on CI.
for dep in jq python3 shasum awk basename wc; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "ERROR: missing dependency: $dep" >&2
    exit 1
  fi
done
if ! python3 -c "import yaml" 2>/dev/null; then
  echo "ERROR: PyYAML not available — install via 'python3 -m pip install pyyaml'" >&2
  exit 1
fi

ROOT="$(git rev-parse --show-toplevel)"
GALLERY_DIR="$ROOT/docs/gallery"
GALLERY_JSON="$GALLERY_DIR/gallery.json"
PRESETS_DIR="$ROOT/Pastura/Pastura/Resources/Presets"
HIGHLIGHTS_DIR="$GALLERY_DIR/highlights"
HIGHLIGHT_VALIDATOR="$ROOT/scripts/gallery_highlight_validate.py"
BLOCKLIST_JSON="$ROOT/Pastura/Pastura/Resources/ContentBlocklist.json"
MAX_BYTES=$((256 * 1024))

FAILURES=0

fail() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

# --- Field readers ---------------------------------------------------------

# Parse YAML id via PyYAML — robust against folded scalars / comments /
# quote variations that grep-based extraction would mishandle.
yaml_id() {
  python3 -c "import sys, yaml; print(yaml.safe_load(open(sys.argv[1]))['id'])" "$1"
}

# Parse YAML top-level language via PyYAML (same robustness as yaml_id).
# Prints the empty string when the key is absent/null so the caller can
# distinguish "missing" from "present but out of range".
yaml_language() {
  python3 -c "import sys, yaml; print(yaml.safe_load(open(sys.argv[1])).get('language') or '')" "$1"
}

# Lowercase hex SHA-256 — matches URLSessionGalleryService's runtime
# format and gallery.json.yaml_sha256. shasum is BSD perl on macOS and
# perl-based on ubuntu — output format is identical (`<hex>  <file>`).
yaml_sha256() {
  shasum -a 256 "$1" | awk '{print $1}'
}

file_size() {
  wc -c < "$1" | awk '{print $1}'
}

# Concatenated id stream from gallery.json + every bundled preset YAML.
# Uniqueness is checked at runtime by `sort | uniq -d`.
all_known_ids() {
  jq -r '.scenarios[].id' "$GALLERY_JSON"
  for f in "$PRESETS_DIR"/*.yaml; do
    [ -f "$f" ] || continue
    yaml_id "$f"
  done
}

# --- Per-entry validation --------------------------------------------------

check_entry() {
  local yaml_path="$1"
  local expected_id="$2"
  local expected_sha="$3"
  local expected_lang="$4"

  local actual_id
  actual_id="$(yaml_id "$yaml_path")"
  local file_stem
  file_stem="$(basename "$yaml_path" .yaml)"

  if [ "$actual_id" != "$expected_id" ]; then
    fail "id mismatch — gallery.json id=$expected_id but YAML id=$actual_id ($yaml_path)"
  fi
  if [ "$file_stem" != "$actual_id" ]; then
    fail "filename stem != id — file stem=$file_stem but YAML id=$actual_id ($yaml_path). Rename one or the other so they match."
  fi
  local actual_sha
  actual_sha="$(yaml_sha256 "$yaml_path")"
  if [ "$actual_sha" != "$expected_sha" ]; then
    fail "yaml_sha256 mismatch for id=$expected_id — gallery.json=$expected_sha but actual=$actual_sha ($yaml_path)"
  fi
  local size
  size="$(file_size "$yaml_path")"
  if [ "$size" -gt "$MAX_BYTES" ]; then
    fail "size ${size} bytes exceeds 256 KiB cap (id=$expected_id, $yaml_path)"
  fi
  # Language: the index copy must be present, one of ja/en (ADR-010 D1), and
  # equal to the YAML body's language. This is a data-level gate — it fires at
  # pre-commit / the gallery-drift CI job, outside the iOS test suite, and so
  # also covers the README "Manual fallback" hand-edit path that
  # add-gallery-entry.sh's auto-derivation never touches. Mirrors the Swift
  # GallerySeedYAMLTests.galleryLanguageMatchesYAML pin (#848).
  local actual_lang
  actual_lang="$(yaml_language "$yaml_path")"
  case "$actual_lang" in
    ja|en) ;;
    *) fail "YAML 'language' must be present and one of ja/en — got '$actual_lang' (id=$expected_id, $yaml_path)" ;;
  esac
  if [ "$expected_lang" != "$actual_lang" ]; then
    fail "language mismatch for id=$expected_id — gallery.json='${expected_lang:-<missing>}' but YAML='$actual_lang' ($yaml_path)"
  fi
}

# --- Highlight validation (ADR-029) ----------------------------------------

# Delegates to the python validator. Runs in BOTH modes (the gallery-drift CI
# job uses --all) and is a no-op when the repo carries neither a highlights/
# directory nor any highlight_* index field — that keeps the check free for
# every gallery edit that predates the feature.
check_highlights() {
  local paired
  paired="$(jq -r '[.scenarios[] | select(has("highlight_url") or has("highlight_sha256"))] | length' "$GALLERY_JSON")"
  if [ ! -d "$HIGHLIGHTS_DIR" ] && [ "$paired" = "0" ]; then
    return 0
  fi
  if [ ! -f "$HIGHLIGHT_VALIDATOR" ]; then
    fail "highlight: validator missing — expected $HIGHLIGHT_VALIDATOR"
    return 0
  fi
  local out rc
  set +e
  out="$(python3 "$HIGHLIGHT_VALIDATOR" \
    --gallery-json "$GALLERY_JSON" \
    --gallery-dir "$GALLERY_DIR" \
    --blocklist "$BLOCKLIST_JSON" 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    # here-doc, not a pipe: `echo "$out" | while …` would run the loop in a
    # subshell and lose `fail`'s FAILURES increments. (Not `<<<` either —
    # here-strings are on ci-workflows.md Rule 1's bash-3.2 avoid list.)
    while IFS= read -r line; do
      [ -n "$line" ] && fail "$line"
    done <<EOF
$out
EOF
  fi
}

check_id_uniqueness() {
  local dups
  dups="$(all_known_ids | sort | uniq -d)"
  if [ -n "$dups" ]; then
    while IFS= read -r dup; do
      fail "duplicate id across gallery.json + bundled presets: $dup"
    done <<< "$dups"
  fi
}

# --- Mode dispatch ---------------------------------------------------------

MODE="${1:-}"
if [ -z "$MODE" ]; then
  echo "Usage: $0 --all" >&2
  echo "       $0 docs/gallery/<id>.yaml" >&2
  exit 1
fi

if [ "$MODE" = "--all" ]; then
  check_id_uniqueness
  while IFS=$'\t' read -r entry_id entry_url entry_sha entry_lang; do
    yaml_path="$GALLERY_DIR/$(basename "$entry_url")"
    if [ ! -f "$yaml_path" ]; then
      fail "yaml file missing for id=$entry_id — expected $yaml_path"
      continue
    fi
    check_entry "$yaml_path" "$entry_id" "$entry_sha" "$entry_lang"
  done < <(jq -r '.scenarios[] | [.id, .yaml_url, .yaml_sha256, (.language // "")] | @tsv' "$GALLERY_JSON")
  check_highlights
else
  yaml_path="$MODE"
  if [ ! -f "$yaml_path" ]; then
    echo "ERROR: file not found: $yaml_path" >&2
    exit 1
  fi
  yaml_basename="$(basename "$yaml_path")"
  entry_json="$(jq -r --arg base "$yaml_basename" \
    '.scenarios[] | select((.yaml_url | split("/") | last) == $base)' \
    "$GALLERY_JSON")"
  if [ -z "$entry_json" ]; then
    fail "no gallery.json entry references yaml_url=$yaml_basename — add the entry first or fix the filename"
  else
    expected_id="$(echo "$entry_json" | jq -r '.id')"
    expected_sha="$(echo "$entry_json" | jq -r '.yaml_sha256')"
    expected_lang="$(echo "$entry_json" | jq -r '.language // ""')"
    check_entry "$yaml_path" "$expected_id" "$expected_sha" "$expected_lang"
  fi
  check_id_uniqueness
  check_highlights
fi

if [ "$FAILURES" -gt 0 ]; then
  echo "" >&2
  echo "$FAILURES failure(s) detected." >&2
  exit 1
fi
echo "OK: gallery validation passed."
