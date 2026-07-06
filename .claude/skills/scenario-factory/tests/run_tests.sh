#!/bin/bash
# Self-test for the scenario-factory helper scripts. No Swift toolchain or
# model needed — exercises classification (--classify), transcript
# formatting, and digest appending against fixtures, including the #253
# crash shape (truncated JSONL, no run_end).
#
# usage: bash .claude/skills/scenario-factory/tests/run_tests.sh
set -eu
cd "$(dirname "$0")"
SCRIPTS=../scripts
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
check_status() { # <label> <jsonl> <exit_code> <expected_status>
  local got
  got=$(bash "$SCRIPTS/run_scenario.sh" --classify "$2" "$3" | jq -r '.status')
  [ "$got" = "$4" ] || fail "$1: expected status=$4, got $got"
}

# --- run_scenario.sh --classify -------------------------------------------
check_status "ok run" fixtures/run_ok.jsonl 0 ok
# #253 SIGABRT: shell sees 134, last line truncated, no run_end
check_status "SIGABRT crash" fixtures/run_crash_truncated.jsonl 134 failed
# harness-internal failure: run_end present with status=error, exit 1
check_status "retries exhausted" fixtures/run_error.jsonl 1 failed
# clean exit but missing run_end (writer died) must still be failed
check_status "exit 0 without run_end" fixtures/run_crash_truncated.jsonl 0 failed
# config error: exit 2, no JSONL ever written
check_status "config error" "$TMP/never_written.jsonl" 2 config_error
# oversized estimate in run_start → config_error regardless of exit code
check_status "oversize estimate" fixtures/run_oversize.jsonl 143 config_error
check_status "oversize estimate (clean exit)" fixtures/run_oversize.jsonl 0 config_error

ERR=$(bash "$SCRIPTS/run_scenario.sh" --classify fixtures/run_crash_truncated.jsonl 134 | jq -r '.error')
echo "$ERR" | grep -q "#253" || fail "crash error should reference #253, got: $ERR"

# --- format_transcript.py ---------------------------------------------------
T=$(python3 "$SCRIPTS/format_transcript.py" fixtures/run_ok.jsonl)
echo "$T" | grep -q "テスト大喜利" || fail "transcript: scenario name missing"
echo "$T" | grep -q "お前が議事録だろ" || fail "transcript: statement missing"
echo "$T" | grep -q "status=ok" || fail "transcript: run_end status missing"
echo "$T" | grep -q "inference_started" && fail "transcript: noise events not skipped"

T=$(python3 "$SCRIPTS/format_transcript.py" fixtures/run_crash_truncated.jsonl)
echo "$T" | grep -q "run_end missing" || fail "transcript: crash shape not reported"
echo "$T" | grep -q "1 unparseable line" || fail "transcript: truncated line not counted"

# --- append_digest.py -------------------------------------------------------
cp fixtures/digest_seed.md "$TMP/digest.md"
python3 "$SCRIPTS/append_digest.py" \
  --results fixtures/results_sample.json --digest "$TMP/digest.md" >/dev/null
grep -q "^## 2026-06-13$" "$TMP/digest.md" || fail "digest: section heading missing"
grep -q "factory_20260613_test_ok" "$TMP/digest.md" || fail "digest: ok row missing"
grep -q '設定は一貫、ボケの幅 \\| は狭め' "$TMP/digest.md" || fail "digest: pipe not escaped in comment"
grep -q 'elimination / creative' "$TMP/digest.md" || fail "digest: axis column not rendered"
# scenario without an axis renders the em-dash (backward-compat via cell())
grep -q 'クラッシュ再現 | 大喜利 | – |' "$TMP/digest.md" || fail "digest: missing axis not em-dashed"
# 5th rubric axis: header column present, null development renders em-dash
# alongside sibling rubric scores rendered as integers
grep -q '(e) development' "$TMP/digest.md" || fail "digest: development header column missing"
grep -q '| 1 | 2 | 3 | 4 | – |' "$TMP/digest.md" || fail "digest: null development not em-dashed"
grep -q "factory-digest:promotion" "$TMP/digest.md" || fail "digest: promotion marker lost"
tail -1 "$TMP/digest.md" | grep -q "^Promotion:" || fail "digest: promotion line no longer last"

# date idempotency: re-append replaces, never duplicates
python3 "$SCRIPTS/append_digest.py" \
  --results fixtures/results_sample.json --digest "$TMP/digest.md" >/dev/null 2>"$TMP/warn"
COUNT=$(grep -c "^## 2026-06-13$" "$TMP/digest.md")
[ "$COUNT" -eq 1 ] || fail "digest: re-append duplicated the section ($COUNT)"
grep -q "warning: replaced" "$TMP/warn" || fail "digest: replace warning missing"

# corrupted digest (no markers) must hard-error, not blind-append
echo "# broken" > "$TMP/broken.md"
if python3 "$SCRIPTS/append_digest.py" \
  --results fixtures/results_sample.json --digest "$TMP/broken.md" 2>/dev/null; then
  fail "digest: missing markers should be a hard error"
fi

# absent digest → bootstrap a scaffold (both markers + Promotion: line), append
python3 "$SCRIPTS/append_digest.py" \
  --results fixtures/results_sample.json --digest "$TMP/bootstrap.md" >/dev/null \
  || fail "digest: absent file should bootstrap, not error"
grep -q "factory-digest:sections" "$TMP/bootstrap.md" || fail "bootstrap: sections marker missing"
grep -q "factory-digest:promotion" "$TMP/bootstrap.md" || fail "bootstrap: promotion marker missing"
grep -q "^## 2026-06-13$" "$TMP/bootstrap.md" || fail "bootstrap: section not appended"
tail -1 "$TMP/bootstrap.md" | grep -q "^Promotion:" || fail "bootstrap: promotion line not last"

# --- append_digest.py: sidecar index ----------------------------------------
# The index (digest-index.jsonl) is a machine-readable dedup cache written
# alongside the digest; digest.md stays the source of truth.
IDX_DIR="$TMP/idx"; mkdir -p "$IDX_DIR"
cp fixtures/digest_seed.md "$IDX_DIR/digest.md"
python3 "$SCRIPTS/append_digest.py" \
  --results fixtures/results_sample.json --digest "$IDX_DIR/digest.md" >/dev/null
IDX="$IDX_DIR/digest-index.jsonl"
[ -f "$IDX" ] || fail "index: sidecar not created next to digest"
# one line per scenario (results_sample has 3)
[ "$(grep -c . "$IDX")" -eq 3 ] || fail "index: expected 3 lines, got $(grep -c . "$IDX")"
# comment is deliberately excluded (it is the bulk of digest size)
if jq -es 'map(has("comment")) | any' "$IDX" >/dev/null; then
  fail "index: comment key must be excluded"
fi
# same-date re-run replaces, never duplicates
python3 "$SCRIPTS/append_digest.py" \
  --results fixtures/results_sample.json --digest "$IDX_DIR/digest.md" >/dev/null 2>&1
[ "$(grep -c . "$IDX")" -eq 3 ] || fail "index: same-date re-run duplicated lines"

# incremental multi-date accumulation: appending a SECOND date's results must
# keep the first date's index lines (not just replace-by-date).
MD="$TMP/multidate"; mkdir -p "$MD"
cp fixtures/digest_seed.md "$MD/digest.md"
python3 "$SCRIPTS/append_digest.py" \
  --results fixtures/results_sample.json --digest "$MD/digest.md" >/dev/null
jq '.date = "2026-06-14"
    | .scenarios = [.scenarios[0]]
    | .scenarios[0].id = "factory_20260614_test_ok"
    | .scenarios[0].scores = {"coherence": 5, "interaction": 4}' \
  fixtures/results_sample.json > "$MD/results_day2.json"
python3 "$SCRIPTS/append_digest.py" \
  --results "$MD/results_day2.json" --digest "$MD/digest.md" >/dev/null
MDIDX="$MD/digest-index.jsonl"
[ "$(jq -es 'map(select(.date=="2026-06-13")) | length' "$MDIDX")" -eq 3 ] \
  || fail "index: day-1 lines lost after day-2 append"
[ "$(jq -es 'map(select(.date=="2026-06-14")) | length' "$MDIDX")" -eq 1 ] \
  || fail "index: day-2 line missing"
# partial scores dict (missing rubric keys) normalized with null-filled
# keys — matches what --rebuild-index would materialize for the same row
jq -es 'map(select(.date=="2026-06-14"))[0].scores
    == {"coherence":5,"interaction":4,"breakdown_free":null,"humor":null,"development":null}' \
  "$MDIDX" >/dev/null || fail "index: partial scores dict not normalized with null rubric keys"

# corrupt existing index line (malformed JSON) must fail-open like the
# unwritable-index case above: append still succeeds, warning names
# --rebuild-index. Pins the ValueError branch of write_index_incremental's
# `except (OSError, ValueError)`.
CI="$TMP/corrupt_idx"; mkdir -p "$CI"
cp fixtures/digest_seed.md "$CI/digest.md"
echo '{not json' > "$CI/digest-index.jsonl"
python3 "$SCRIPTS/append_digest.py" \
  --results fixtures/results_sample.json --digest "$CI/digest.md" >/dev/null 2>"$CI/warn" \
  || fail "index: corrupt existing index line must not fail the append"
grep -q "^## 2026-06-13$" "$CI/digest.md" || fail "index: digest not updated on corrupt index line"
grep -q -- "--rebuild-index" "$CI/warn" || fail "index: corrupt-line warning must name --rebuild-index"

# round-trip: --rebuild-index off the produced digest == the incremental index
cp "$IDX" "$IDX_DIR/index-incremental.jsonl"
python3 "$SCRIPTS/append_digest.py" \
  --digest "$IDX_DIR/digest.md" --rebuild-index >/dev/null || fail "index: rebuild failed"
python3 - "$IDX_DIR/index-incremental.jsonl" "$IDX" <<'PY' || fail "index: round-trip mismatch"
import json, sys
def norm(path):
    with open(path, encoding="utf-8") as f:
        objs = [json.loads(l) for l in f if l.strip()]
    return sorted(json.dumps(o, sort_keys=True, ensure_ascii=False) for o in objs)
sys.exit(0 if norm(sys.argv[1]) == norm(sys.argv[2]) else 1)
PY

# 3-shape rebuild: pre-axis / 4-axis / 5-axis sections, incl. an escaped pipe
SH="$TMP/shapes"; mkdir -p "$SH"
cp fixtures/digest_shapes.md "$SH/digest.md"
python3 "$SCRIPTS/append_digest.py" \
  --digest "$SH/digest.md" --rebuild-index >/dev/null || fail "shapes: rebuild failed"
SHIDX="$SH/digest-index.jsonl"
[ "$(grep -c . "$SHIDX")" -eq 4 ] || fail "shapes: expected 4 scenario lines, got $(grep -c . "$SHIDX")"
# escaped \| round-trips into the JSON value unescaped
grep -q 'テスト | 大喜利' "$SHIDX" || fail "shapes: escaped pipe not unescaped in index"
# pre-axis-column row carries a null axis
jq -es 'map(select(.id=="shape_c_ok"))[0].axis == null' "$SHIDX" >/dev/null \
  || fail "shapes: pre-axis-column row axis not null"

# unrecognized table shape → rebuild hard-fails (non-zero) and writes nothing
BG="$TMP/bogus"; mkdir -p "$BG"
cat > "$BG/digest.md" <<'EOF'
# Digest
<!-- factory-digest:sections -->

## 2026-06-13

| id | name | theme | axis | status | (a) coherence | (z) bogus | comment |
|---|---|---|---|---|---|---|---|
| x | n | t | – | ok | 4 | 9 | c |

<!-- factory-digest:promotion -->
Promotion: x
EOF
if python3 "$SCRIPTS/append_digest.py" \
  --digest "$BG/digest.md" --rebuild-index 2>/dev/null; then
  fail "bogus: unrecognized rubric column should hard-fail"
fi
[ ! -f "$BG/digest-index.jsonl" ] || fail "bogus: index written despite hard-fail"

# rebuild-index on a digest with both markers but ZERO `## <date>` sections
# (e.g. the bootstrap scaffold before any append) must exit 0 and write an
# EMPTY index file — not error, not skip the write.
ZS="$TMP/zero_sections"; mkdir -p "$ZS"
cp fixtures/digest_seed.md "$ZS/digest.md"
python3 "$SCRIPTS/append_digest.py" \
  --digest "$ZS/digest.md" --rebuild-index >/dev/null || fail "zero-section rebuild failed"
[ -f "$ZS/digest-index.jsonl" ] || fail "zero-section rebuild: index file not created"
[ ! -s "$ZS/digest-index.jsonl" ] || fail "zero-section rebuild: index file not empty"

# non-fatal index failure: a directory at the index path blocks the write;
# the append still succeeds (digest is the source of truth)
UW="$TMP/unwr"; mkdir -p "$UW"
cp fixtures/digest_seed.md "$UW/digest.md"
mkdir "$UW/digest-index.jsonl"   # a directory can't be overwritten by a file
python3 "$SCRIPTS/append_digest.py" \
  --results fixtures/results_sample.json --digest "$UW/digest.md" >/dev/null 2>"$UW/warn" \
  || fail "index: unwritable index must not fail the append"
grep -q "^## 2026-06-13$" "$UW/digest.md" || fail "index: digest not updated when index write fails"
grep -q -- "--rebuild-index" "$UW/warn" || fail "index: failure warning must name --rebuild-index"

# --- gallery_census.py ------------------------------------------------------
C=$(python3 "$SCRIPTS/gallery_census.py" fixtures/gallery_census_sample.json)
echo "$C" | grep -q "Suggested targets" || fail "census: suggested-targets section missing"
# a known-RARE axis (branching, 1/4) must appear in the suggested mechanic line
echo "$C" | grep "mechanic axes:" | grep -q "branching" || fail "census: rare axis not suggested"
# a known-CROWDED axis (peer_vote, 3/4) must be flagged crowded
echo "$C" | grep "peer_vote" | grep -q "crowded" || fail "census: crowded axis not flagged"
# nullable/absent phases excluded from the axis denominator, reported
echo "$C" | grep -q "1 skipped: no phases" || fail "census: null-phases row not skipped"
# zero-entry valid category surfaced as rare (game_theory has no gallery entry)
echo "$C" | grep "game_theory" | grep -q "rare" || fail "census: zero-count category not rare"
# empty gallery must not crash the overnight cycle (exit 0, notice printed)
echo '{"version":1,"scenarios":[]}' > "$TMP/empty.json"
python3 "$SCRIPTS/gallery_census.py" "$TMP/empty.json" | grep -q "empty gallery" \
  || fail "census: empty gallery not handled cleanly"
# fallback: when no axis trips rare/crowded (all 2/4), still suggest 3 rarest
F=$(python3 "$SCRIPTS/gallery_census.py" fixtures/gallery_census_balanced.json)
echo "$F" | grep -q "avoid piling onto crowded" && fail "census: balanced should have no crowded axis"
echo "$F" | grep "mechanic axes:" | grep -q "peer_vote" || fail "census: fallback rarest-3 targets missing"
# unrecognized category drift surfaces on stderr (not silently absorbed)
echo '{"version":1,"scenarios":[{"id":"x","category":"made_up_cat","phases":["vote"]}]}' > "$TMP/drift.json"
python3 "$SCRIPTS/gallery_census.py" "$TMP/drift.json" 2>"$TMP/drift.err" >/dev/null
grep -q "unrecognized categories" "$TMP/drift.err" || fail "census: category drift not warned"

# --- gallery_census.py: new structural axes (whisper / reflect) --------------
# whisper 2/4 (whisper_reflect + whisper_only), reflect 2/4 (whisper_reflect +
# reflect_only) — proves the two Engine-phase axes count presence correctly.
NP=$(python3 "$SCRIPTS/gallery_census.py" fixtures/gallery_census_newphases.json)
echo "$NP" | grep "pair_whisper" | grep -q "2/4" || fail "census: pair_whisper axis count wrong"
echo "$NP" | grep "reflection" | grep -q "2/4" || fail "census: reflection axis count wrong"

# --- gallery_census.py: PhaseType drift tripwire ----------------------------
# (b) a fixture enum carrying a fake `future_phase` case (plus dot-prefixed
# switch patterns the parser must ignore) surfaces the NEW-mechanic warning.
D=$(python3 "$SCRIPTS/gallery_census.py" fixtures/gallery_census_sample.json \
  --phase-types fixtures/phase_types_drifted.swift)
echo "$D" | grep -q "NEW ENGINE MECHANICS" || fail "census: drift warning not printed"
echo "$D" | grep "NEW ENGINE MECHANICS" | grep -q "future_phase" \
  || fail "census: drifted phase not surfaced in warning"
# (c) a fixture mirroring the real 12 cases → no warning (all axis/scaffolding-covered)
CUR=$(python3 "$SCRIPTS/gallery_census.py" fixtures/gallery_census_sample.json \
  --phase-types fixtures/phase_types_current.swift)
echo "$CUR" | grep -q "NEW ENGINE MECHANICS" && fail "census: false drift on current phase types"
# (d) unreadable phase-types file → fail-open: exit 0, stderr notice, targets intact
if ! python3 "$SCRIPTS/gallery_census.py" fixtures/gallery_census_sample.json \
  --phase-types /nonexistent/phase_types.swift 2>"$TMP/fo.err" >"$TMP/fo.out"; then
  fail "census: missing phase-types file should fail-open (exit 0)"
fi
grep -q "skipping PhaseType drift check" "$TMP/fo.err" || fail "census: fail-open notice missing"
grep -q "Suggested targets" "$TMP/fo.out" || fail "census: fail-open lost suggested targets"

# (e) repo-root reality check — the REAL PhaseType.swift must exist at its
# documented path, so a future Models/ SPM extraction fails CI here instead of
# silently disabling the tripwire (fail-open would swallow the moved path).
REPO_ROOT=$(git rev-parse --show-toplevel)
[ -f "$REPO_ROOT/Pastura/Pastura/Models/PhaseType.swift" ] \
  || fail "census: real PhaseType.swift not found (Models/ SPM move? see --phase-types comment)"
REAL=$(python3 "$SCRIPTS/gallery_census.py" fixtures/gallery_census_sample.json \
  --phase-types "$REPO_ROOT/Pastura/Pastura/Models/PhaseType.swift")
echo "$REAL" | grep -q "NEW ENGINE MECHANICS" \
  && fail "census: unexpected drift against real PhaseType.swift (new phase needs a census axis)"

echo "ALL TESTS PASSED"
