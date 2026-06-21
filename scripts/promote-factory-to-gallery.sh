#!/usr/bin/env bash
# scripts/promote-factory-to-gallery.sh — bridge a scenario-factory (or any
# field-tested) scenario YAML into the shared-scenario gallery. Automates
# docs/gallery/README.md § "Promoting from the scenario factory" steps 1–3
# then delegates the mechanical registration (SHA / updated_at / title-sync
# / validation) to add-gallery-entry.sh.
#
# Usage:
#   bash scripts/promote-factory-to-gallery.sh <factory-id> [flags]   (factory mode)
#   bash scripts/promote-factory-to-gallery.sh --scenario <yaml> --id <gallery-id> [flags]
#                                                                      (path-spec mode)
#
# Modes:
#   factory mode    Positional <factory-id> of the form
#                    `factory_<YYYYMMDD>_<slug>` (the id stamped by the
#                    /scenario-factory cycle). The date and slug are
#                    parsed out and used to locate:
#                      scenario: data/factory/scenarios/<YYYY-MM-DD>/<factory-id>.yaml
#                      run log:  data/factory/runs/<YYYY-MM-DD>/<factory-id>.jsonl
#                    The default gallery id is `<slug>_v1`.
#
#   path-spec mode  `--scenario <yaml>` points at any scenario YAML (e.g.
#                    an improved v2 produced by a future improvement
#                    routine). `--id <gallery-id>` is REQUIRED — the
#                    target gallery id / filename stem cannot be derived.
#                    `--run-log <jsonl>` is optional; when omitted you
#                    MUST pass `--estimated-inferences <n>` (no log to
#                    read it from).
#
# What it does (per the README bridge):
#   1. Copies the source YAML → docs/gallery/<gallery-id>.yaml and
#      rewrites the top-level `id:` to <gallery-id> (anchored ^id: edit,
#      so the stem==id invariant add-gallery-entry.sh enforces holds).
#   2. Extracts estimated_inferences from the run log's `run_start` line.
#   3. Defaults category=creative and recommended_model to the factory's
#      pinned model (both overridable).
#   4. Calls add-gallery-entry.sh to register the entry.
#
# CURATION STAYS MANUAL: this script promotes the id you name. It never
# inspects judge scores or auto-picks a gallery-worthy scenario — that
# judgement is yours (see the README's curation guidance).
#
# Optional flags:
#   --scenario <yaml>           path-spec mode source YAML (see Modes)
#   --run-log <jsonl>           explicit run log (factory mode: derived;
#                                path-spec mode: optional)
#   --id <gallery-id>           target gallery id / filename stem
#                                (factory mode default: <slug>_v1;
#                                path-spec mode: REQUIRED)
#   --category <slug>           gallery category (default: creative)
#   --recommended-model <id>    default: gemma-4-e2b-q4-k-m
#   --estimated-inferences <n>  override the run-log value; REQUIRED in
#                                path-spec mode when --run-log is absent
#   --description <text>        gallery card description. When omitted the
#                                copied YAML's description is used — but
#                                factory descriptions carry curation
#                                meta-notes, so this prints a WARNING and
#                                is an ERROR under --non-interactive.
#   --added-at <YYYY-MM-DD>     passthrough to add-gallery-entry.sh
#   --author <handle>           passthrough to add-gallery-entry.sh
#   --force                     allow overwriting an existing
#                                docs/gallery/<gallery-id>.yaml (default:
#                                refuse, to protect curator edits)
#   --dry-run                   print derived values + the would-be
#                                add-gallery-entry.sh command, then exit
#                                WITHOUT copying or delegating (the add
#                                script has no dry-run of its own)
#   --non-interactive, -y       pass --non-interactive to the add script
#                                (suppresses its confirm prompt); also
#                                forces --description (see above)
#   -h, --help                  print this header

set -euo pipefail

# --- Dependency check ------------------------------------------------------

for dep in jq awk shasum basename date; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "ERROR: missing dependency: $dep" >&2
    exit 1
  fi
done

ROOT="$(git rev-parse --show-toplevel)"
GALLERY_DIR="$ROOT/docs/gallery"
ADD_SCRIPT="$ROOT/scripts/add-gallery-entry.sh"

# Shell-safe single-quote a value for the dry-run command preview. Unlike
# printf %q this preserves UTF-8 (Japanese descriptions) readably while
# staying copy-paste-safe: bare for [A-Za-z0-9_./=-], else single-quoted
# with embedded quotes escaped as '\''.
shell_quote() {
  case "$1" in
    *[!A-Za-z0-9_./=-]*|'')
      printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")" ;;
    *) printf '%s' "$1" ;;
  esac
}

# --- Argument parsing ------------------------------------------------------

FACTORY_ID=""
SCENARIO_PATH=""
RUN_LOG=""
GALLERY_ID=""
CATEGORY="creative"
RECOMMENDED_MODEL="gemma-4-e2b-q4-k-m"
ESTIMATED_INFERENCES=""
DESCRIPTION=""
DESCRIPTION_SET=0
ADDED_AT=""
AUTHOR=""
FORCE=0
DRY_RUN=0
NON_INTERACTIVE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --scenario) SCENARIO_PATH="$2"; shift 2 ;;
    --run-log) RUN_LOG="$2"; shift 2 ;;
    --id) GALLERY_ID="$2"; shift 2 ;;
    --category) CATEGORY="$2"; shift 2 ;;
    --recommended-model) RECOMMENDED_MODEL="$2"; shift 2 ;;
    --estimated-inferences) ESTIMATED_INFERENCES="$2"; shift 2 ;;
    --description) DESCRIPTION="$2"; DESCRIPTION_SET=1; shift 2 ;;
    --added-at) ADDED_AT="$2"; shift 2 ;;
    --author) AUTHOR="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --non-interactive|-y) NON_INTERACTIVE=1; shift ;;
    -h|--help) awk '/^# Usage/{p=1} /^set -/{exit} p' "$0" | sed -E 's/^# ?//'; exit 0 ;;
    -*) echo "Unknown flag: $1" >&2; exit 1 ;;
    *)
      if [ -z "$FACTORY_ID" ]; then
        FACTORY_ID="$1"
      else
        echo "ERROR: unexpected positional argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

# --- Mode resolution -------------------------------------------------------

if [ -n "$FACTORY_ID" ] && [ -n "$SCENARIO_PATH" ]; then
  echo "ERROR: pass EITHER a <factory-id> positional OR --scenario, not both." >&2
  exit 1
fi

if [ -n "$FACTORY_ID" ]; then
  MODE="factory"
elif [ -n "$SCENARIO_PATH" ]; then
  MODE="path"
else
  echo "ERROR: provide a <factory-id> positional or --scenario <yaml>." >&2
  echo "       See: bash $0 --help" >&2
  exit 1
fi

# --- Factory-mode derivation ----------------------------------------------

if [ "$MODE" = "factory" ]; then
  # Expect factory_<8 digits>_<slug>. Validate up front so a path or a
  # malformed id produces a clear error rather than a confusing
  # file-not-found far downstream.
  case "$FACTORY_ID" in
    factory_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_*) ;;
    *)
      echo "ERROR: '$FACTORY_ID' is not a factory id of the form factory_<YYYYMMDD>_<slug>." >&2
      echo "       For an arbitrary YAML, use: --scenario <yaml> --id <gallery-id>" >&2
      exit 1 ;;
  esac
  # Fixed-offset parse (not a delimiter split — slugs contain underscores).
  REST="${FACTORY_ID#factory_}"     # 20260618_uso_kigen
  DATESTAMP="${REST:0:8}"           # 20260618
  SLUG="${REST:9}"                  # uso_kigen  (skip the underscore at index 8)
  if [ -z "$SLUG" ]; then
    echo "ERROR: factory id '$FACTORY_ID' has an empty slug." >&2
    exit 1
  fi
  DATE="${DATESTAMP:0:4}-${DATESTAMP:4:2}-${DATESTAMP:6:2}"   # 2026-06-18
  SCENARIO_PATH="$ROOT/data/factory/scenarios/$DATE/$FACTORY_ID.yaml"
  if [ -z "$RUN_LOG" ]; then
    RUN_LOG="$ROOT/data/factory/runs/$DATE/$FACTORY_ID.jsonl"
  fi
  if [ -z "$GALLERY_ID" ]; then
    GALLERY_ID="${SLUG}_v1"
  fi
fi

# --- Path-mode requirements -----------------------------------------------

if [ "$MODE" = "path" ] && [ -z "$GALLERY_ID" ]; then
  echo "ERROR: --id <gallery-id> is required in path-spec mode (cannot be derived)." >&2
  exit 1
fi

# --- Common validation -----------------------------------------------------

# gallery-id must be a safe filename stem AND a valid scenario id. The add
# script enforces stem==id; we keep the id conservative here so neither the
# copy destination nor the rewrite produce anything surprising.
case "$GALLERY_ID" in
  [a-z0-9]*) ;;
  *) echo "ERROR: gallery id '$GALLERY_ID' must start with a lowercase letter or digit." >&2; exit 1 ;;
esac
case "$GALLERY_ID" in
  *[!a-z0-9_]*) echo "ERROR: gallery id '$GALLERY_ID' may contain only [a-z0-9_]." >&2; exit 1 ;;
esac

if [ ! -f "$SCENARIO_PATH" ]; then
  echo "ERROR: scenario YAML not found: $SCENARIO_PATH" >&2
  exit 1
fi

if [ ! -f "$ADD_SCRIPT" ]; then
  echo "ERROR: add-gallery-entry.sh not found at $ADD_SCRIPT" >&2
  exit 1
fi

DEST="$GALLERY_DIR/$GALLERY_ID.yaml"
if [ -e "$DEST" ] && [ "$FORCE" != "1" ]; then
  echo "ERROR: $DEST already exists." >&2
  echo "       Refusing to overwrite a curated gallery YAML. Re-run with --force" >&2
  echo "       to overwrite, or pass a different --id (e.g. a _v2 promotion)." >&2
  exit 1
fi

# --- estimated_inferences resolution --------------------------------------
#
# Precedence: explicit --estimated-inferences > run log's run_start line.
# `jq -s` slurps the whole JSONL into an array so we pick the first
# run_start without a `head -1` SIGPIPE (which would trip `set -o pipefail`).
if [ -z "$ESTIMATED_INFERENCES" ]; then
  if [ -n "$RUN_LOG" ] && [ -f "$RUN_LOG" ]; then
    ESTIMATED_INFERENCES="$(jq -rs '([.[] | select(.type=="run_start")][0] // {}) | .estimated_inferences // empty' "$RUN_LOG")"
    if [ -z "$ESTIMATED_INFERENCES" ]; then
      echo "ERROR: no run_start.estimated_inferences found in $RUN_LOG." >&2
      echo "       Pass --estimated-inferences <n> explicitly." >&2
      exit 1
    fi
  else
    if [ "$MODE" = "path" ]; then
      echo "ERROR: path-spec mode without --run-log requires --estimated-inferences <n>." >&2
    else
      echo "ERROR: run log not found: $RUN_LOG" >&2
      echo "       Pass --run-log <jsonl> or --estimated-inferences <n>." >&2
    fi
    exit 1
  fi
fi

case "$ESTIMATED_INFERENCES" in
  ''|*[!0-9]*)
    echo "ERROR: estimated_inferences must be a positive integer (got: '$ESTIMATED_INFERENCES')." >&2
    exit 1 ;;
esac
# Advisory only — the gallery README suggests rough parity with a real run;
# unusually large values are worth a glance but not a hard failure.
if [ "$ESTIMATED_INFERENCES" -gt 50 ]; then
  echo "ADVISORY: estimated_inferences=$ESTIMATED_INFERENCES is high (>50);" >&2
  echo "          confirm it matches a real run (see docs/gallery/README.md)." >&2
fi

# --- description resolution ------------------------------------------------
#
# When --description is omitted the add script falls back to the copied
# YAML's description. Factory descriptions carry curation meta-notes, so
# under --non-interactive (e.g. a scheduled Routine) that fallback would
# silently ship meta-notes to users — make it a hard error there; warn
# otherwise.
if [ "$DESCRIPTION_SET" != "1" ]; then
  if [ "$NON_INTERACTIVE" = "1" ]; then
    echo "ERROR: --non-interactive requires an explicit --description." >&2
    echo "       The source YAML's description may contain curation meta-notes" >&2
    echo "       unsuitable for a user-facing gallery card." >&2
    exit 1
  fi
  echo "WARNING: no --description given — the gallery card will use the source" >&2
  echo "         YAML's description verbatim, which may contain curation" >&2
  echo "         meta-notes. Review and edit the gallery card if needed." >&2
fi

# --- Original id (for messaging) ------------------------------------------

ORIG_ID="$(awk '/^id:[[:space:]]/{sub(/^id:[[:space:]]*/, ""); print; exit}' "$SCENARIO_PATH")"
if [ -z "$ORIG_ID" ]; then
  echo "ERROR: source YAML has no top-level 'id:' line: $SCENARIO_PATH" >&2
  exit 1
fi

# --- Build the add-gallery-entry.sh argument vector -----------------------

ADD_ARGS=("$DEST"
  --category "$CATEGORY"
  --recommended-model "$RECOMMENDED_MODEL"
  --estimated-inferences "$ESTIMATED_INFERENCES")
[ "$DESCRIPTION_SET" = "1" ] && ADD_ARGS+=(--description "$DESCRIPTION")
[ -n "$ADDED_AT" ] && ADD_ARGS+=(--added-at "$ADDED_AT")
[ -n "$AUTHOR" ] && ADD_ARGS+=(--author "$AUTHOR")
[ "$NON_INTERACTIVE" = "1" ] && ADD_ARGS+=(--non-interactive)

# --- Dry run: report and stop BEFORE any write or delegation --------------

if [ "$DRY_RUN" = "1" ]; then
  echo "[dry-run] would promote:"
  echo "  mode:                  $MODE"
  echo "  source YAML:           $SCENARIO_PATH"
  echo "  source id:             $ORIG_ID"
  [ -n "$RUN_LOG" ] && echo "  run log:               $RUN_LOG"
  echo "  destination:           $DEST"
  echo "  gallery id (= stem):   $GALLERY_ID"
  echo "  category:              $CATEGORY"
  echo "  recommended_model:     $RECOMMENDED_MODEL"
  echo "  estimated_inferences:  $ESTIMATED_INFERENCES"
  if [ "$DESCRIPTION_SET" = "1" ]; then
    echo "  description:           (override) $DESCRIPTION"
  else
    echo "  description:           (from source YAML — review!)"
  fi
  echo ""
  echo "[dry-run] would then run:"
  printf '  bash %s' "$(shell_quote "$ADD_SCRIPT")"
  for a in "${ADD_ARGS[@]}"; do printf ' %s' "$(shell_quote "$a")"; done
  printf '\n'
  echo ""
  echo "[dry-run] no files written."
  exit 0
fi

# --- Copy + anchored id rewrite -------------------------------------------
#
# Copy first, then rewrite ONLY the first top-level `^id:` line. An
# unanchored substitution would corrupt any other `factory_<date>_<slug>`
# occurrence (persona ids, prose); a PyYAML round-trip would reorder keys
# and drop comments. The single GALLERY_ID is used for BOTH the filename
# stem (DEST) and the rewritten id, so add-gallery-entry.sh's stem==id
# guard cannot fail.
cp "$SCENARIO_PATH" "$DEST"

awk -v newid="$GALLERY_ID" '
  !done && /^id:[[:space:]]/ { print "id: " newid; done = 1; next }
  { print }
  END { if (!done) exit 3 }
' "$DEST" > "$DEST.tmp" || {
  rm -f "$DEST.tmp" "$DEST"
  echo "ERROR: source YAML has no top-level 'id:' line to rewrite." >&2
  exit 1
}
mv "$DEST.tmp" "$DEST"

echo "Wrote $DEST (id: $ORIG_ID → $GALLERY_ID)"

# --- Delegate registration -------------------------------------------------

if bash "$ADD_SCRIPT" "${ADD_ARGS[@]}"; then
  echo ""
  echo "Promoted $GALLERY_ID to the gallery."
  echo "Next: review the diff, run a Debug build with PASTURA_GALLERY_BASE_URL"
  echo "      pointing at your branch, and confirm the scenario installs cleanly."
else
  STATUS=$?
  # If we created a fresh file (not a --force overwrite of a pre-existing
  # one), remove the orphan so a failed add (e.g. duplicate id in
  # gallery.json) does not leave an untracked stray YAML behind.
  if [ "$FORCE" != "1" ]; then
    rm -f "$DEST"
    echo "Removed $DEST (add-gallery-entry.sh failed; no partial promotion left behind)." >&2
  else
    echo "WARNING: add-gallery-entry.sh failed and $DEST was overwritten (--force)." >&2
    echo "         Restore it from git if needed." >&2
  fi
  exit "$STATUS"
fi
