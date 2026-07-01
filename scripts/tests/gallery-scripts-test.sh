#!/usr/bin/env bash
#
# scripts/tests/gallery-scripts-test.sh — regression tests for the gallery
# tooling: scripts/add-gallery-entry.sh, scripts/check-gallery-entry.sh,
# and scripts/promote-factory-to-gallery.sh (#542).
#
# Black-box tests. Each case scaffolds an ISOLATED throwaway git repo
# under a tempdir (copies the three scripts into <tmp>/scripts/, writes a
# minimal docs/gallery/gallery.json, `git init`), then runs the scripts
# from inside it. Because every script resolves its root via
# `git rev-parse --show-toplevel`, the temp repo becomes their root — so
# the real docs/gallery/ is never touched and cases are parallel-safe.
# No production code change and no new dependency (jq + python3/PyYAML,
# already required by the scripts under test).
#
# check-gallery-entry.sh's Presets uniqueness scan tolerates a missing
# Pastura/Pastura/Resources/Presets/ dir (the glob yields no match), so
# the scaffold omits it — gallery-only id uniqueness is still exercised.
#
# CI-wired: the `scripts/tests/*-test.sh` naming convention makes this a
# gate under .github/workflows/ci.yml ("Run scripts/tests/*-test.sh",
# the `shell-tests` job). That job runs on ubuntu (bash 5+); the scripts
# under test ship to macOS (bash 3.2), so run this manually under
# /bin/bash before merge for 3.2 coverage:
#
#   /bin/bash scripts/tests/gallery-scripts-test.sh

set -euo pipefail

for dep in jq python3 git shasum; do
  command -v "$dep" >/dev/null 2>&1 || { echo "ERROR: missing dependency: $dep" >&2; exit 1; }
done
python3 -c "import yaml" 2>/dev/null || { echo "ERROR: PyYAML not available — 'python3 -m pip install pyyaml'" >&2; exit 1; }

SRC_SCRIPTS="$(git rev-parse --show-toplevel)/scripts"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0
OUT=""
RC=0

# --- Assertion + scaffold helpers -----------------------------------------

bad() { echo "FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

# Run "$@" with cwd set to repo $1, capturing combined output + exit code
# into OUT / RC. Toggles errexit so a non-zero exit is observed, not fatal.
runc() {
  local d="$1"; shift
  set +e
  OUT="$(cd "$d" && "$@" 2>&1)"
  RC=$?
  set -e
}

expect_ok()   { if [ "$RC" -eq 0 ]; then PASS=$((PASS + 1)); else bad "$1 (rc=$RC): $OUT"; fi; }
expect_fail() { if [ "$RC" -ne 0 ]; then PASS=$((PASS + 1)); else bad "$1 (expected non-zero rc): $OUT"; fi; }
expect_out()  { case "$OUT" in *"$1"*) PASS=$((PASS + 1));; *) bad "$2 (missing '$1'): $OUT";; esac; }
expect_file()   { if [ -f "$1" ]; then PASS=$((PASS + 1)); else bad "$2 (no file: $1)"; fi; }
expect_nofile() { if [ ! -e "$1" ]; then PASS=$((PASS + 1)); else bad "$2 (unexpected file: $1)"; fi; }

new_repo() {
  local d
  d="$(mktemp -d "$TMPROOT/repo.XXXXXX")"
  mkdir -p "$d/scripts" "$d/docs/gallery"
  cp "$SRC_SCRIPTS/add-gallery-entry.sh" \
     "$SRC_SCRIPTS/check-gallery-entry.sh" \
     "$SRC_SCRIPTS/promote-factory-to-gallery.sh" "$d/scripts/"
  printf '{\n  "updated_at": "2026-01-01T00:00:00Z",\n  "scenarios": []\n}\n' \
    > "$d/docs/gallery/gallery.json"
  git -C "$d" init -q
  git -C "$d" config user.email "t@example.com"
  git -C "$d" config user.name "tester"
  printf '%s' "$d"
}

mk_factory() {  # repo date datestamp slug estimated_inferences
  local d="$1" date="$2" ds="$3" slug="$4" ei="$5"
  mkdir -p "$d/data/factory/scenarios/$date" "$d/data/factory/runs/$date"
  cat > "$d/data/factory/scenarios/$date/factory_${ds}_${slug}.yaml" <<YAML
id: factory_${ds}_${slug}
language: ja
name: Test ${slug}
agents: 4
rounds: 2
description: factory description with a curation meta-note
personas:
  - name: persona1
    description: body references factory_${ds}_${slug} verbatim
phases:
  - type: speak_all
  - type: vote
YAML
  printf '{"type":"run_start","estimated_inferences":%s}\n{"type":"turn"}\n{"type":"run_end"}\n' \
    "$ei" > "$d/data/factory/runs/$date/factory_${ds}_${slug}.jsonl"
}

mk_gallery_yaml() {  # repo id agents rounds [description]
  local d="$1" id="$2" agents="$3" rounds="$4" desc="${5:-card description}"
  cat > "$d/docs/gallery/$id.yaml" <<YAML
id: $id
language: ja
name: Name of $id
agents: $agents
rounds: $rounds
description: $desc
personas:
  - name: a
    description: aa
phases:
  - type: speak_all
  - type: vote
YAML
}

# ============================ promote-factory ============================

# P1 — dry-run derives id/estimated_inferences and writes nothing.
R="$(new_repo)"; mk_factory "$R" 2026-01-01 20260101 demo 42
runc "$R" bash scripts/promote-factory-to-gallery.sh factory_20260101_demo --dry-run --description card
expect_ok "P1 dry-run exits 0"
expect_out "demo_v1" "P1 derives gallery id demo_v1"
expect_out "estimated_inferences:  42" "P1 extracts estimated_inferences from run log"
expect_nofile "$R/docs/gallery/demo_v1.yaml" "P1 dry-run writes no YAML"
runc "$R" jq -r '.scenarios | length' docs/gallery/gallery.json
expect_out "0" "P1 dry-run added no gallery.json entry"

# P2 — real factory promote: id rewrite (anchored) + gallery.json entry.
R="$(new_repo)"; mk_factory "$R" 2026-01-01 20260101 demo 42
runc "$R" bash scripts/promote-factory-to-gallery.sh factory_20260101_demo \
  --non-interactive --description "clean card copy" --author tester
expect_ok "P2 promote exits 0"
expect_file "$R/docs/gallery/demo_v1.yaml" "P2 writes the gallery YAML"
runc "$R" awk 'NR==1' docs/gallery/demo_v1.yaml
expect_out "id: demo_v1" "P2 top-level id rewritten to demo_v1"
runc "$R" grep -c "factory_20260101_demo" docs/gallery/demo_v1.yaml
expect_out "1" "P2 body factory_<id> substring preserved (not clobbered)"
runc "$R" jq -r '.scenarios[0] | "\(.id) \(.estimated_inferences) \(.agent_count) \(.rounds) \(.title)"' \
  docs/gallery/gallery.json
expect_out "demo_v1 42 4 2 Test demo" "P2 entry has derived id/ei + YAML-sourced agent_count/rounds/title"

# P9 — re-promote without --force refuses to overwrite the curated YAML.
# Reuses P2's repo (already has demo_v1.yaml); no new_repo between them.
runc "$R" bash scripts/promote-factory-to-gallery.sh factory_20260101_demo \
  --non-interactive --description x --author tester
expect_fail "P9 re-promote without --force fails"
expect_out "already exists" "P9 overwrite guard message"

# P10 — path-spec mode (arbitrary source + explicit id + estimated).
R="$(new_repo)"; mk_factory "$R" 2026-02-02 20260202 src 7
runc "$R" bash scripts/promote-factory-to-gallery.sh \
  --scenario data/factory/scenarios/2026-02-02/factory_20260202_src.yaml \
  --id improved_v2 --estimated-inferences 7 --description "v2 card" \
  --non-interactive --author tester
expect_ok "P10 path-spec promote exits 0"
expect_file "$R/docs/gallery/improved_v2.yaml" "P10 writes improved_v2.yaml"
runc "$R" jq -r '.scenarios[0].id' docs/gallery/gallery.json
expect_out "improved_v2" "P10 registers improved_v2"

# Error paths (each on a fresh repo; some need only arg parsing).
R="$(new_repo)"
runc "$R" bash scripts/promote-factory-to-gallery.sh not_a_factory_id
expect_fail "P-err bad factory id fails"; expect_out "not a factory id" "P-err bad-id message"

runc "$R" bash scripts/promote-factory-to-gallery.sh factory_20260101_demo --scenario x.yaml
expect_fail "P-err both modes fails"; expect_out "not both" "P-err both-modes message"

runc "$R" bash scripts/promote-factory-to-gallery.sh --scenario docs/gallery/gallery.json
expect_fail "P-err path mode without --id fails"; expect_out "required in path-spec" "P-err missing --id message"

mk_factory "$R" 2026-03-03 20260303 noec 5
runc "$R" bash scripts/promote-factory-to-gallery.sh \
  --scenario data/factory/scenarios/2026-03-03/factory_20260303_noec.yaml --id noec_v1
expect_fail "P-err path mode no run-log + no estimated fails"
expect_out "requires --estimated-inferences" "P-err missing estimated message"

mk_factory "$R" 2026-04-04 20260404 nod 9
runc "$R" bash scripts/promote-factory-to-gallery.sh factory_20260404_nod -y
expect_fail "P-err -y without --description fails"
expect_out "requires an explicit --description" "P-err non-interactive description message"

# ============================ add-gallery-entry ==========================

# A1 — add a new entry; agent_count/rounds derived from the YAML.
R="$(new_repo)"; mk_gallery_yaml "$R" foo_v1 5 3
runc "$R" bash scripts/add-gallery-entry.sh docs/gallery/foo_v1.yaml \
  --category creative --recommended-model gemma-4-e2b-q4-k-m \
  --estimated-inferences 8 --description card --author tester --non-interactive
expect_ok "A1 add exits 0"
runc "$R" jq -r '.scenarios[0] | "\(.id) \(.agent_count) \(.rounds)"' docs/gallery/gallery.json
expect_out "foo_v1 5 3" "A1 entry agent_count/rounds from YAML scalars"
runc "$R" jq -r '.scenarios[0].language' docs/gallery/gallery.json
expect_out "ja" "A1 entry language derived from YAML language: scalar"

# A2 — duplicate id rejected in add mode (reuses A1's repo state).
runc "$R" bash scripts/add-gallery-entry.sh docs/gallery/foo_v1.yaml \
  --category creative --recommended-model gemma-4-e2b-q4-k-m \
  --estimated-inferences 8 --description card --author tester --non-interactive
expect_fail "A2 duplicate id fails"; expect_out "already exists" "A2 dup-id message"

# A4 — update mode refreshes the sha after a YAML body edit.
SHA_BEFORE="$(jq -r '.scenarios[0].yaml_sha256' "$R/docs/gallery/gallery.json")"
mk_gallery_yaml "$R" foo_v1 5 3 "edited description body"
runc "$R" bash scripts/add-gallery-entry.sh --update foo_v1 --non-interactive
expect_ok "A4 update exits 0"; expect_out "Updated entry" "A4 update message"
SHA_AFTER="$(jq -r '.scenarios[0].yaml_sha256' "$R/docs/gallery/gallery.json")"
if [ "$SHA_BEFORE" != "$SHA_AFTER" ]; then PASS=$((PASS + 1)); else bad "A4 sha did not refresh"; fi

# A5 — update with no change short-circuits (no-op).
runc "$R" bash scripts/add-gallery-entry.sh --update foo_v1 --non-interactive
expect_ok "A5 no-op update exits 0"; expect_out "No change needed" "A5 no-op message"

# A3 — filename stem != YAML id rejected.
R="$(new_repo)"; mk_gallery_yaml "$R" wrongstem 4 2
# Rewrite the internal id so stem (wrongstem) != id (otherid).
sed 's/^id: wrongstem/id: otherid/' "$R/docs/gallery/wrongstem.yaml" > "$R/docs/gallery/wrongstem.yaml.t"
mv "$R/docs/gallery/wrongstem.yaml.t" "$R/docs/gallery/wrongstem.yaml"
runc "$R" bash scripts/add-gallery-entry.sh docs/gallery/wrongstem.yaml \
  --category creative --recommended-model gemma-4-e2b-q4-k-m \
  --estimated-inferences 8 --description card --author tester --non-interactive
expect_fail "A3 stem!=id fails"; expect_out "does not match YAML id" "A3 stem-mismatch message"

# A6 — non-interactive with a missing required field fails fast.
R="$(new_repo)"; mk_gallery_yaml "$R" bar_v1 4 2
runc "$R" bash scripts/add-gallery-entry.sh docs/gallery/bar_v1.yaml \
  --recommended-model gemma-4-e2b-q4-k-m --estimated-inferences 8 \
  --description card --author tester --non-interactive
expect_fail "A6 non-interactive missing category fails"
expect_out "category is missing" "A6 missing-field message"

# A7 — YAML missing `language:` rejected with a curated error (not a raw
# Python KeyError). Strip the line portably (mirrors A3's sed-then-mv idiom).
R="$(new_repo)"; mk_gallery_yaml "$R" nolang_v1 4 2
grep -v '^language:' "$R/docs/gallery/nolang_v1.yaml" > "$R/docs/gallery/nolang_v1.yaml.t"
mv "$R/docs/gallery/nolang_v1.yaml.t" "$R/docs/gallery/nolang_v1.yaml"
runc "$R" bash scripts/add-gallery-entry.sh docs/gallery/nolang_v1.yaml \
  --category creative --recommended-model gemma-4-e2b-q4-k-m \
  --estimated-inferences 8 --description card --author tester --non-interactive
expect_fail "A7 missing language fails"
expect_out "must be present and one of ja/en" "A7 missing-language message"

# ================================ summary ================================

echo ""
echo "gallery-scripts-test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
echo "OK"
