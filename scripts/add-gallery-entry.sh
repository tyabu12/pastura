#!/usr/bin/env bash
# scripts/add-gallery-entry.sh — Add or update an entry in
# docs/gallery/gallery.json safely. Eliminates the three error-prone
# hand-edits that PR #300 + PR #318 + PR #323 left behind:
#
#   1. shasum -a 256 → copy/paste 64-hex                   (now automated)
#   2. updated_at bump                                     (now automated)
#   3. byte-equal gallery.json[].title == YAML name:       (now automated)
#
# Usage:
#   bash scripts/add-gallery-entry.sh <yaml-path> [flags]                    (add mode)
#   bash scripts/add-gallery-entry.sh --update <id> [<yaml-path>] [flags]    (update mode)
#
# Modes:
#   add (default)               Register a new gallery entry. REJECTS if
#                                id is already in gallery.json.
#   --update <id>               Refresh an existing entry's yaml_sha256
#                                (and optionally title / description /
#                                etc.). REJECTS if id is NOT in
#                                gallery.json. <yaml-path> defaults to
#                                docs/gallery/<id>.yaml when omitted;
#                                fields not overridden by a flag are
#                                preserved from the existing entry.
#
# Required positional:
#   <yaml-path>                 path to docs/gallery/<id>.yaml — file
#                                must already be committed/staged.
#                                Required in add mode; in update mode,
#                                defaults to docs/gallery/<id>.yaml.
#
# Optional flags (each suppresses the corresponding interactive prompt):
#   --update <id>               update mode — refresh the entry whose
#                                id matches (see Modes above)
#   --category <slug>           one of GalleryCategory.allCases raw
#                                values (social_psychology, game_theory,
#                                ethics, roleplay, creative, experimental)
#   --recommended-model <id>    e.g. gemma-4-e2b-q4-k-m
#   --estimated-inferences <n>  positive integer
#   --added-at <YYYY-MM-DD>     add mode: defaults to today (UTC).
#                                update mode: preserved from existing
#                                entry; pass to override.
#   --description <text>        overrides the gallery card description.
#                                add mode default: YAML's description.
#                                update mode default: existing entry's
#                                description (preserved). To re-sync
#                                from YAML, pass the YAML value
#                                explicitly — see docs/gallery/README.md
#                                "Updating an existing scenario".
#   --author <handle>           add mode: defaults to gh api user → git
#                                config user.name. update mode:
#                                preserved from existing entry.
#   --non-interactive           fail if any required field is missing
#                                (no prompts, no confirmation). In
#                                update mode, all fields default to
#                                existing-entry values, so this works
#                                without overrides.
#
# Failure modes — chosen behavior:
#
#   (a) Re-run with same id in add mode: REJECT (pre-check on
#       .scenarios[].id). To refresh an existing entry, use
#       `--update <id>`. Symmetrically, `--update <id>` with an id that
#       does NOT exist also REJECTS — drop the flag to add a new entry.
#   (b) YAML id != filename stem: REJECT. The Swift gallery resolver
#       round-trips on yaml_url.lastPathComponent → file. Rename one
#       or the other and re-run.
#   (c) updated_at monotonicity: bumps to max(now, existing). When
#       local clock is behind existing (NTP rollback / CI runner skew),
#       a stderr WARNING fires and updated_at does NOT advance — keeps
#       monotonic ordering. Verify `date -u` if you see this.
#   (d) Atomic write: jq writes to gallery.json.tmp; the original is
#       moved aside, the new file installed, then check-gallery-entry.sh
#       runs as a post-validate gate (--all in add mode, single-file
#       in update mode — see in-script comment for why). Any failure
#       restores the backup, leaving the working tree byte-identical.
#   (e) Trailing newline: jq emits a trailing newline by default,
#       matching the existing gallery.json. Re-run does not double-newline.
#   (f) BOM-prefixed YAML: PyYAML accepts BOM and SHA-256 is byte-level
#       so the hash matches downloaded content. No special handling.
#   (g) update-mode no-op: when the candidate entry is byte-identical
#       to the existing one (no flag overrides AND unchanged YAML),
#       exits 0 BEFORE bumping `updated_at` and BEFORE the atomic
#       write. Re-running `--update` with no real change is therefore
#       free.
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
UPDATE_ID=""           # set by --update <id>; empty → add mode
CATEGORY=""
RECOMMENDED_MODEL=""
ESTIMATED_INFERENCES=""
ADDED_AT=""
DESCRIPTION_OVERRIDE=""
AUTHOR=""
NON_INTERACTIVE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --update)
      [ $# -ge 2 ] || { echo "ERROR: --update requires an id argument" >&2; exit 1; }
      UPDATE_ID="$2"
      [ -n "$UPDATE_ID" ] || { echo "ERROR: --update id cannot be empty" >&2; exit 1; }
      # Guard against `--update --category foo` where the next token is
      # another flag — would otherwise be silently stored as the id and
      # produce a confusing yaml-not-found / stem-mismatch error far
      # downstream.
      case "$UPDATE_ID" in
        -*) echo "ERROR: --update id '$UPDATE_ID' looks like a flag (did you forget the id?)" >&2; exit 1 ;;
      esac
      shift 2 ;;
    --category) CATEGORY="$2"; shift 2 ;;
    --recommended-model) RECOMMENDED_MODEL="$2"; shift 2 ;;
    --estimated-inferences) ESTIMATED_INFERENCES="$2"; shift 2 ;;
    --added-at) ADDED_AT="$2"; shift 2 ;;
    --description) DESCRIPTION_OVERRIDE="$2"; shift 2 ;;
    --author) AUTHOR="$2"; shift 2 ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    -h|--help) awk '/^# Usage/{p=1} /^set -/{exit} p' "$0" | sed -E 's/^# ?//'; exit 0 ;;
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

if [ -n "$UPDATE_ID" ]; then
  MODE="update"
else
  MODE="add"
fi

if [ -z "$YAML_PATH" ]; then
  if [ "$MODE" = "update" ]; then
    YAML_PATH="$GALLERY_DIR/$UPDATE_ID.yaml"
  else
    echo "Usage: $0 <yaml-path> [flags]                    (add mode)" >&2
    echo "       $0 --update <id> [<yaml-path>] [flags]    (update mode)" >&2
    echo "       $0 --help" >&2
    exit 1
  fi
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

if [ "$MODE" = "update" ] && [ "$UPDATE_ID" != "$YAML_ID" ]; then
  echo "ERROR: --update id '$UPDATE_ID' does not match YAML id '$YAML_ID'." >&2
  echo "       Pass the YAML for the id you want to update, or fix the --update value." >&2
  exit 1
fi

if [ "$YAML_SIZE" -gt "$MAX_BYTES" ]; then
  echo "ERROR: YAML size ${YAML_SIZE} bytes exceeds 256 KiB cap (URLSessionGalleryService.yamlSizeLimit)" >&2
  exit 1
fi

# --- Pre-check: mode-branched id existence --------------------------------

EXISTING_ENTRY="$(jq -c --arg id "$YAML_ID" '.scenarios[] | select(.id == $id)' "$GALLERY_JSON")"

if [ "$MODE" = "add" ]; then
  if [ -n "$EXISTING_ENTRY" ]; then
    echo "ERROR: id '$YAML_ID' already exists in gallery.json." >&2
    echo "       This script's add mode is for new entries only." >&2
    echo "       To refresh an existing entry, use:" >&2
    echo "         bash $0 --update $YAML_ID [flags]" >&2
    exit 1
  fi
else
  if [ -z "$EXISTING_ENTRY" ]; then
    echo "ERROR: id '$YAML_ID' is not in gallery.json — nothing to update." >&2
    echo "       Available ids:" >&2
    jq -r '.scenarios[].id' "$GALLERY_JSON" | sed 's/^/         - /' >&2
    echo "       To add a new entry, drop the --update flag:" >&2
    echo "         bash $0 $YAML_PATH [flags]" >&2
    exit 1
  fi
fi

# --- Preload existing entry values (update mode) --------------------------
#
# In update mode, fields default to the existing entry's values so a
# bare `--update <id>` (just refreshing the SHA) does not require the
# curator to re-supply category / recommended_model / etc. Each
# assignment is guarded by `[ -z "$VAR" ]` — flag overrides win because
# the loop above already populated $VAR from --category / etc. before
# we reach this block. (`prompt_required` becomes a no-op once preload
# runs, which is also how update mode supports `--non-interactive`
# without forcing every field to be re-supplied.)
if [ "$MODE" = "update" ]; then
  [ -z "$CATEGORY" ] && CATEGORY="$(echo "$EXISTING_ENTRY" | jq -r '.category')"
  [ -z "$RECOMMENDED_MODEL" ] && RECOMMENDED_MODEL="$(echo "$EXISTING_ENTRY" | jq -r '.recommended_model')"
  [ -z "$ESTIMATED_INFERENCES" ] && ESTIMATED_INFERENCES="$(echo "$EXISTING_ENTRY" | jq -r '.estimated_inferences')"
  [ -z "$ADDED_AT" ] && ADDED_AT="$(echo "$EXISTING_ENTRY" | jq -r '.added_at')"
  [ -z "$AUTHOR" ] && AUTHOR="$(echo "$EXISTING_ENTRY" | jq -r '.author')"
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

# Add-mode-only default: today UTC. In update mode, ADDED_AT is already
# preloaded from the existing entry above, so this branch is a no-op.
if [ -z "$ADDED_AT" ] && [ "$MODE" = "add" ]; then
  ADDED_AT="$(date -u +%Y-%m-%d)"
fi
if [ -z "$ADDED_AT" ]; then
  echo "ERROR: added_at is empty (in update mode this means the existing entry was malformed)" >&2
  exit 1
fi

# DESCRIPTION resolution differs by mode:
#   add    → flag override > YAML's description > error
#   update → flag override > existing entry's description > error
# Update mode preloads-from-existing rather than YAML so a curator who
# previously customised the gallery card with `--description "shorter
# summary"` does not have it silently reverted to the YAML's longer
# version on a re-run. To re-sync from YAML, pass the YAML value
# explicitly — see docs/gallery/README.md.
if [ -n "$DESCRIPTION_OVERRIDE" ]; then
  DESCRIPTION="$DESCRIPTION_OVERRIDE"
elif [ "$MODE" = "update" ]; then
  DESCRIPTION="$(echo "$EXISTING_ENTRY" | jq -r '.description')"
else
  DESCRIPTION="$YAML_DESC"
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

# --- Build candidate entry -------------------------------------------------

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

# --- update-mode no-op short-circuit --------------------------------------
#
# If the candidate is byte-identical to the existing entry (no flag
# overrides AND unchanged YAML body), exit 0 BEFORE bumping
# `updated_at` and BEFORE the atomic write. Otherwise a no-op `--update`
# would still produce a top-level `updated_at`-only diff. jq's `==` on
# objects is order-independent, so canonical-key order does not matter.
if [ "$MODE" = "update" ]; then
  if jq -e -n --argjson a "$NEW_ENTRY" --argjson b "$EXISTING_ENTRY" '$a == $b' >/dev/null; then
    echo "No change needed — candidate entry is byte-identical to existing (id=$YAML_ID)." >&2
    exit 0
  fi
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

# --- Diff display (update mode) -------------------------------------------
#
# Single-line fields use `field: OLD → NEW`.
# Multi-line description uses two-line `(old):` / `(new):` form so the
# arrow does not get buried inside string newlines.
# `title` and `yaml_sha256` are prefixed `(from YAML)` so curators can
# tell YAML-driven changes (curator edited the YAML body) from
# flag-driven changes (curator passed --category etc.).
print_entry_diff() {
  local old="$1"
  local new="$2"
  local field old_val new_val source_label
  for field in title category description author recommended_model estimated_inferences added_at yaml_sha256; do
    old_val="$(echo "$old" | jq -r --arg f "$field" '.[$f] | tostring')"
    new_val="$(echo "$new" | jq -r --arg f "$field" '.[$f] | tostring')"
    if [ "$old_val" = "$new_val" ]; then
      continue
    fi
    source_label=""
    case "$field" in
      title|yaml_sha256) source_label=" (from YAML)" ;;
    esac
    if [ "$field" = "description" ] && { [[ "$old_val" == *$'\n'* ]] || [[ "$new_val" == *$'\n'* ]]; }; then
      printf "  %s%s (old):\n" "$field" "$source_label"
      printf '%s\n' "$old_val" | sed 's/^/    /'
      printf "  %s%s (new):\n" "$field" "$source_label"
      printf '%s\n' "$new_val" | sed 's/^/    /'
    else
      printf "  %s%s: %s → %s\n" "$field" "$source_label" "$old_val" "$new_val"
    fi
  done
}

# --- Confirm --------------------------------------------------------------

if [ "$NON_INTERACTIVE" != "1" ]; then
  echo "" >&2
  if [ "$MODE" = "update" ]; then
    echo "About to update entry id=$YAML_ID in $GALLERY_JSON:" >&2
    print_entry_diff "$EXISTING_ENTRY" "$NEW_ENTRY" >&2
  else
    echo "About to add to $GALLERY_JSON:" >&2
    echo "$NEW_ENTRY" | jq . >&2
  fi
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
if [ "$MODE" = "add" ]; then
  jq --argjson new "$NEW_ENTRY" --arg updated_at "$UPDATED_AT" \
    '.updated_at = $updated_at | .scenarios += [$new]' \
    "$GALLERY_JSON" > "$TMP"
else
  # `map` preserves array position — the entry stays where it was.
  jq --argjson new "$NEW_ENTRY" --arg updated_at "$UPDATED_AT" --arg id "$YAML_ID" \
    '.updated_at = $updated_at | .scenarios |= map(if .id == $id then $new else . end)' \
    "$GALLERY_JSON" > "$TMP"
fi

BACKUP="$GALLERY_JSON.bak.$$"
mv "$GALLERY_JSON" "$BACKUP"
mv "$TMP" "$GALLERY_JSON"

# Post-validate gate. Update mode uses single-file mode — sufficient
# because `check_id_uniqueness` still runs globally inside the check
# script, and `--update` cannot introduce drift on other entries (it
# rewrites only one entry by id-match). Add mode uses --all to also
# catch unrelated stale YAMLs in the gallery dir at script-run time.
if [ "$MODE" = "update" ]; then
  POST_VALIDATE_ARGS=("$YAML_PATH")
else
  POST_VALIDATE_ARGS=("--all")
fi

if ! bash "$CHECK_SCRIPT" "${POST_VALIDATE_ARGS[@]}"; then
  echo "" >&2
  echo "ERROR: post-write validation failed; restoring previous gallery.json" >&2
  mv "$BACKUP" "$GALLERY_JSON"
  exit 1
fi

rm "$BACKUP"
echo ""
if [ "$MODE" = "update" ]; then
  echo "Updated entry id=$YAML_ID in docs/gallery/gallery.json (updated_at=$UPDATED_AT)"
else
  echo "Added entry id=$YAML_ID to docs/gallery/gallery.json (updated_at=$UPDATED_AT)"
fi
echo "Next: review the diff, run a Debug build with PASTURA_GALLERY_BASE_URL"
echo "      pointing at your branch, and confirm the scenario installs cleanly."
