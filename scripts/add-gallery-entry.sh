#!/usr/bin/env bash
# scripts/add-gallery-entry.sh — Add a new entry to docs/gallery/gallery.json
# safely. Eliminates the three error-prone hand-edits that PR #300 +
# PR #318 left behind:
#
#   1. shasum -a 256 → copy/paste 64-hex                   (now automated)
#   2. updated_at bump                                     (now automated)
#   3. byte-equal gallery.json[].title == YAML name:       (now automated)
#
# Usage:
#   bash scripts/add-gallery-entry.sh <yaml-path> [flags]
#
# Required positional:
#   <yaml-path>                 path to docs/gallery/<id>.yaml — file
#                                must already be committed/staged
#
# Optional flags (each suppresses the corresponding interactive prompt):
#   --category <slug>           one of GalleryCategory.allCases raw
#                                values (social_psychology, game_theory,
#                                ethics, roleplay, creative, experimental)
#   --recommended-model <id>    e.g. gemma-4-e2b-q4-k-m
#   --estimated-inferences <n>  positive integer
#   --added-at <YYYY-MM-DD>     defaults to today (UTC)
#   --description <text>        overrides YAML description for the
#                                gallery card (e.g. shorter summary)
#   --author <handle>           defaults to gh api user → git config user.name
#   --non-interactive           fail if any required field is missing
#                                (no prompts, no confirmation)
#
# Failure modes — chosen behavior:
#
#   (a) Re-run with same id: REJECT (pre-check on .scenarios[].id).
#       This script is for new entries; edit gallery.json directly to
#       update an existing entry.
#   (b) YAML id != filename stem: REJECT. The Swift gallery resolver
#       round-trips on yaml_url.lastPathComponent → file. Rename one
#       or the other and re-run.
#   (c) updated_at monotonicity: bumps to max(now, existing). When
#       local clock is behind existing (NTP rollback / CI runner skew),
#       a stderr WARNING fires and updated_at does NOT advance — keeps
#       monotonic ordering. Verify `date -u` if you see this.
#   (d) Atomic write: jq writes to gallery.json.tmp; the original is
#       moved aside, the new file installed, then check-gallery-entry.sh
#       --all runs as a post-validate gate. Any failure restores the
#       backup, leaving the working tree byte-identical to entry.
#   (e) Trailing newline: jq emits a trailing newline by default,
#       matching the existing gallery.json. Re-run does not double-newline.
#   (f) BOM-prefixed YAML: PyYAML accepts BOM and SHA-256 is byte-level
#       so the hash matches downloaded content. No special handling.
#
# Choice lists at prompts are read from the Swift sources at runtime
# (Pastura/Pastura/Models/GalleryScenario.swift,
# Pastura/Pastura/App/ModelRegistry.swift) so this script does not
# duplicate the enum / registry. The Swift suite
# (GallerySeedYAMLTests) is the enforcement mechanism — these prompts
# are UX only and accept any string.

set -euo pipefail

# --- Dependency check ------------------------------------------------------

for dep in jq python3 shasum awk basename date wc; do
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
CHECK_SCRIPT="$ROOT/scripts/check-gallery-entry.sh"
MAX_BYTES=$((256 * 1024))

# --- Argument parsing ------------------------------------------------------

YAML_PATH=""
CATEGORY=""
RECOMMENDED_MODEL=""
ESTIMATED_INFERENCES=""
ADDED_AT=""
DESCRIPTION_OVERRIDE=""
AUTHOR=""
NON_INTERACTIVE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --category) CATEGORY="$2"; shift 2 ;;
    --recommended-model) RECOMMENDED_MODEL="$2"; shift 2 ;;
    --estimated-inferences) ESTIMATED_INFERENCES="$2"; shift 2 ;;
    --added-at) ADDED_AT="$2"; shift 2 ;;
    --description) DESCRIPTION_OVERRIDE="$2"; shift 2 ;;
    --author) AUTHOR="$2"; shift 2 ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    -h|--help) awk '/^# Usage/{p=1} /^set -/{exit} p' "$0" | sed 's/^# \?//'; exit 0 ;;
    -*) echo "Unknown flag: $1" >&2; exit 1 ;;
    *)
      if [ -z "$YAML_PATH" ]; then
        YAML_PATH="$1"
      else
        echo "Unexpected positional argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "$YAML_PATH" ]; then
  echo "Usage: $0 <yaml-path> [--category ...] [--recommended-model ...] ..." >&2
  echo "       $0 --help" >&2
  exit 1
fi

if [ ! -f "$YAML_PATH" ]; then
  echo "ERROR: file not found: $YAML_PATH" >&2
  exit 1
fi

# Canonicalize to absolute (no symlink resolution needed — basename
# and jq lookups only care about identity, not realpath). Avoids the
# `$(cd "$(dirname …)" && pwd)` form that Claude Code's permission
# heuristic flags (anthropics/claude-code#31373).
case "$YAML_PATH" in
  /*) ;;
  *) YAML_PATH="$PWD/$YAML_PATH" ;;
esac
YAML_BASENAME="$(basename "$YAML_PATH")"
YAML_STEM="$(basename "$YAML_PATH" .yaml)"

# --- Derive from YAML ------------------------------------------------------

YAML_ID="$(python3 -c "import sys, yaml; print(yaml.safe_load(open(sys.argv[1]))['id'])" "$YAML_PATH")"
YAML_NAME="$(python3 -c "import sys, yaml; print(yaml.safe_load(open(sys.argv[1]))['name'])" "$YAML_PATH")"
YAML_DESC="$(python3 -c "import sys, yaml; d = yaml.safe_load(open(sys.argv[1])).get('description', ''); print((d or '').strip())" "$YAML_PATH")"
YAML_SHA="$(shasum -a 256 "$YAML_PATH" | awk '{print $1}')"
YAML_SIZE="$(wc -c < "$YAML_PATH" | awk '{print $1}')"

if [ "$YAML_ID" != "$YAML_STEM" ]; then
  echo "ERROR: filename stem '$YAML_STEM' does not match YAML id '$YAML_ID'." >&2
  echo "       Rename one or the other so the gallery resolver's round-trip works." >&2
  exit 1
fi

if [ "$YAML_SIZE" -gt "$MAX_BYTES" ]; then
  echo "ERROR: YAML size ${YAML_SIZE} bytes exceeds 256 KiB cap (URLSessionGalleryService.yamlSizeLimit)" >&2
  exit 1
fi

# --- Pre-check: refuse if id already in gallery.json -----------------------

EXISTING="$(jq -r --arg id "$YAML_ID" '.scenarios[] | select(.id == $id) | .id' "$GALLERY_JSON")"
if [ -n "$EXISTING" ]; then
  echo "ERROR: id '$YAML_ID' already exists in gallery.json." >&2
  echo "       This script is for adding new entries. Edit gallery.json directly to update." >&2
  exit 1
fi

# --- Prompt for non-derivable fields ---------------------------------------

list_categories() {
  grep -E '^[[:space:]]*case [a-zA-Z]+[[:space:]]*=[[:space:]]*"[a-z_]+"' \
    "$ROOT/Pastura/Pastura/Models/GalleryScenario.swift" \
    | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/'
}

list_models() {
  grep -E 'id:[[:space:]]*"[^"]+"' \
    "$ROOT/Pastura/Pastura/App/ModelRegistry.swift" \
    | sed -E 's/.*id:[[:space:]]*"([^"]+)".*/\1/' \
    | sort -u
}

prompt_required() {
  local label="$1"; shift
  local var_name="$1"
  local current="${!var_name}"
  if [ -n "$current" ]; then
    return
  fi
  if [ "$NON_INTERACTIVE" = "1" ]; then
    echo "ERROR: --non-interactive but $label is missing" >&2
    exit 1
  fi
  printf "%s: " "$label" >&2
  local value
  read -r value < /dev/tty
  if [ -z "$value" ]; then
    echo "ERROR: $label cannot be empty" >&2
    exit 1
  fi
  printf -v "$var_name" '%s' "$value"
}

if [ -z "$CATEGORY" ] && [ "$NON_INTERACTIVE" != "1" ]; then
  echo "Categories (from GalleryScenario.swift):" >&2
  list_categories | sed 's/^/  - /' >&2
fi
prompt_required "category" CATEGORY

if [ -z "$RECOMMENDED_MODEL" ] && [ "$NON_INTERACTIVE" != "1" ]; then
  echo "Recommended models (from ModelRegistry.swift):" >&2
  list_models | sed 's/^/  - /' >&2
fi
prompt_required "recommended_model" RECOMMENDED_MODEL

prompt_required "estimated_inferences" ESTIMATED_INFERENCES
case "$ESTIMATED_INFERENCES" in
  ''|*[!0-9]*)
    echo "ERROR: estimated_inferences must be a positive integer" >&2
    exit 1
    ;;
esac

if [ -z "$ADDED_AT" ]; then
  ADDED_AT="$(date -u +%Y-%m-%d)"
fi

if [ -z "$DESCRIPTION_OVERRIDE" ]; then
  DESCRIPTION="$YAML_DESC"
else
  DESCRIPTION="$DESCRIPTION_OVERRIDE"
fi
if [ -z "$DESCRIPTION" ]; then
  echo "ERROR: description is empty (YAML lacks description: and no --description override given)" >&2
  exit 1
fi

if [ -z "$AUTHOR" ]; then
  AUTHOR="$(gh api user --jq .login 2>/dev/null || git config user.name 2>/dev/null || echo "")"
  if [ -z "$AUTHOR" ] && [ "$NON_INTERACTIVE" != "1" ]; then
    prompt_required "author" AUTHOR
  fi
fi
if [ -z "$AUTHOR" ]; then
  echo "ERROR: author is empty (gh+git fallback failed and --non-interactive blocked the prompt)" >&2
  exit 1
fi

# --- updated_at monotonicity ----------------------------------------------

NOW_UTC="$(date -u +%Y-%m-%dT00:00:00Z)"
EXISTING_UPDATED_AT="$(jq -r '.updated_at' "$GALLERY_JSON")"
# Lexicographic comparison works for fixed-format ISO-8601 strings.
if [ "$EXISTING_UPDATED_AT" \> "$NOW_UTC" ]; then
  echo "WARNING: existing updated_at ($EXISTING_UPDATED_AT) is later than today ($NOW_UTC)." >&2
  echo "         Local clock skew? Verify 'date -u' and re-run if needed." >&2
  echo "         updated_at will NOT advance — keeping monotonic ordering." >&2
  UPDATED_AT="$EXISTING_UPDATED_AT"
else
  UPDATED_AT="$NOW_UTC"
fi

# --- Build new entry & confirm --------------------------------------------

NEW_ENTRY=$(jq -n \
  --arg id "$YAML_ID" \
  --arg title "$YAML_NAME" \
  --arg category "$CATEGORY" \
  --arg description "$DESCRIPTION" \
  --arg author "$AUTHOR" \
  --arg recommended_model "$RECOMMENDED_MODEL" \
  --argjson estimated_inferences "$ESTIMATED_INFERENCES" \
  --arg yaml_url "$YAML_BASENAME" \
  --arg yaml_sha256 "$YAML_SHA" \
  --arg added_at "$ADDED_AT" \
  '{
    id: $id,
    title: $title,
    category: $category,
    description: $description,
    author: $author,
    recommended_model: $recommended_model,
    estimated_inferences: $estimated_inferences,
    yaml_url: $yaml_url,
    yaml_sha256: $yaml_sha256,
    added_at: $added_at
  }')

if [ "$NON_INTERACTIVE" != "1" ]; then
  echo "" >&2
  echo "About to add to $GALLERY_JSON:" >&2
  echo "$NEW_ENTRY" | jq . >&2
  echo "" >&2
  echo "  updated_at: $UPDATED_AT" >&2
  printf "Proceed? [y/N]: " >&2
  read -r confirm < /dev/tty
  if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Aborted." >&2
    exit 0
  fi
fi

# --- Atomic write + post-validate -----------------------------------------

TMP="$GALLERY_JSON.tmp"
jq --argjson new "$NEW_ENTRY" --arg updated_at "$UPDATED_AT" \
  '.updated_at = $updated_at | .scenarios += [$new]' \
  "$GALLERY_JSON" > "$TMP"

BACKUP="$GALLERY_JSON.bak.$$"
mv "$GALLERY_JSON" "$BACKUP"
mv "$TMP" "$GALLERY_JSON"

if ! bash "$CHECK_SCRIPT" --all; then
  echo "" >&2
  echo "ERROR: post-write validation failed; restoring previous gallery.json" >&2
  mv "$BACKUP" "$GALLERY_JSON"
  exit 1
fi

rm "$BACKUP"
echo ""
echo "Added entry id=$YAML_ID to docs/gallery/gallery.json (updated_at=$UPDATED_AT)"
echo "Next: review the diff, run a Debug build with PASTURA_GALLERY_BASE_URL"
echo "      pointing at your branch, and confirm the scenario installs cleanly."
