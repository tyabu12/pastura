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

# Bounded poll helpers for the flock cases below. Synchronization is by
# sentinel file / process liveness, never by a sleep margin: a cold python
# start on a loaded CI runner outruns any fixed margin, and a margin that is
# too short would fire the "did not write" assertion on a CORRECT
# implementation. Every poll is capped so a hang fails loudly, not silently.
await_file() {   # $1 = path to wait for, $2 = failure message
  i=0
  until [ -e "$1" ]; do
    i=$((i + 1)); [ "$i" -le 600 ] || fail "$2 (timed out after 60s)"
    sleep 0.1
  done
}
await_pid() {    # $1 = pid to wait to become observable, $2 = failure message
  i=0
  until kill -0 "$1" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -le 600 ] || fail "$2 (timed out after 60s)"
    sleep 0.1
  done
}
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
grep -q "^## 2026-06-13 — 01:23:45$" "$TMP/digest.md" || fail "digest: section heading missing"
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

# (date, run_id) idempotency: re-append replaces, never duplicates
python3 "$SCRIPTS/append_digest.py" \
  --results fixtures/results_sample.json --digest "$TMP/digest.md" >/dev/null 2>"$TMP/warn"
COUNT=$(grep -c "^## 2026-06-13 — 01:23:45$" "$TMP/digest.md")
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
grep -q "^## 2026-06-13 — 01:23:45$" "$TMP/bootstrap.md" || fail "bootstrap: section not appended"
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
grep -q "^## 2026-06-13 — 01:23:45$" "$CI/digest.md" || fail "index: digest not updated on corrupt index line"
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
grep -q "^## 2026-06-13 — 01:23:45$" "$UW/digest.md" || fail "index: digest not updated when index write fails"
grep -q -- "--rebuild-index" "$UW/warn" || fail "index: failure warning must name --rebuild-index"

# --- append_digest.py: (date, run_id) section key (#1542) --------------------
# Two /scenario-factory cycles can share a date in the same main checkout
# (a re-run after a fix, a second nightly pass). Before #1542 the second
# append silently wiped the first run's judging record — the digest is the
# only durable one — so these cases pin the compound key.
RK="$TMP/runkey"; mkdir -p "$RK"
cp fixtures/digest_seed.md "$RK/digest.md"
jq '.run_id = "02:34:56"
    | .scenarios = [.scenarios[0]]
    | .scenarios[0].id = "factory_20260613_second_run"' \
  fixtures/results_sample.json > "$RK/results_run2.json"

# (a) REGRESSION TEST FOR #1542: same date, different run_ids → both survive.
python3 "$SCRIPTS/append_digest.py" \
  --results fixtures/results_sample.json --digest "$RK/digest.md" >/dev/null
python3 "$SCRIPTS/append_digest.py" \
  --results "$RK/results_run2.json" --digest "$RK/digest.md" >/dev/null
grep -q "^## 2026-06-13 — 01:23:45$" "$RK/digest.md" \
  || fail "runkey: first run's section wiped by a same-date second run (#1542)"
grep -q "^## 2026-06-13 — 02:34:56$" "$RK/digest.md" \
  || fail "runkey: second run's section missing"
grep -q "factory_20260613_test_ok" "$RK/digest.md" || fail "runkey: run-1 rows lost"
grep -q "factory_20260613_second_run" "$RK/digest.md" || fail "runkey: run-2 rows lost"
RKIDX="$RK/digest-index.jsonl"
[ "$(jq -es 'map(select(.run_id=="01:23:45")) | length' "$RKIDX")" -eq 3 ] \
  || fail "runkey: run-1 index lines lost (#1542)"
[ "$(jq -es 'map(select(.run_id=="02:34:56")) | length' "$RKIDX")" -eq 1 ] \
  || fail "runkey: run-2 index line missing"

# (b) re-appending the SAME (date, run_id) replaces only that section
python3 "$SCRIPTS/append_digest.py" \
  --results "$RK/results_run2.json" --digest "$RK/digest.md" >/dev/null 2>"$RK/warn"
grep -q "warning: replaced" "$RK/warn" || fail "runkey: replace warning missing"
[ "$(grep -c "^## 2026-06-13 — 02:34:56$" "$RK/digest.md")" -eq 1 ] \
  || fail "runkey: same-key re-append duplicated the section"
[ "$(grep -c "^## 2026-06-13 — 01:23:45$" "$RK/digest.md")" -eq 1 ] \
  || fail "runkey: sibling run's section disturbed by a same-key re-append"
[ "$(jq -es 'map(select(.run_id=="01:23:45")) | length' "$RKIDX")" -eq 3 ] \
  || fail "runkey: sibling run's index lines disturbed by a same-key re-append"
[ "$(jq -es 'map(select(.run_id=="02:34:56")) | length' "$RKIDX")" -eq 1 ] \
  || fail "runkey: same-key re-append duplicated index lines"

# (c) run_id is REQUIRED and shape-checked; a rejected results JSON must leave
# the digest byte-identical (an unattended run has to be recoverable by hand).
RV="$TMP/runid_valid"; mkdir -p "$RV"
cp "$RK/digest.md" "$RV/digest.md"
cp "$RV/digest.md" "$RV/digest.before"
jq 'del(.run_id)' fixtures/results_sample.json > "$RV/no_run_id.json"
if python3 "$SCRIPTS/append_digest.py" \
  --results "$RV/no_run_id.json" --digest "$RV/digest.md" 2>"$RV/err"; then
  fail "runid: missing run_id should be a hard error"
fi
grep -q "run_id" "$RV/err" || fail "runid: error message must name run_id"
grep -q "no_run_id.json" "$RV/err" || fail "runid: error message must name the results path"
cmp -s "$RV/digest.before" "$RV/digest.md" || fail "runid: digest touched by a rejected append"
# 99:99 has the right shape but is not a real clock time
jq '.run_id = "99:99"' fixtures/results_sample.json > "$RV/bad_clock.json"
if python3 "$SCRIPTS/append_digest.py" \
  --results "$RV/bad_clock.json" --digest "$RV/digest.md" 2>/dev/null; then
  fail "runid: 99:99 should be rejected as a non-clock run_id"
fi
cmp -s "$RV/digest.before" "$RV/digest.md" || fail "runid: digest touched by an invalid run_id"

# (d) --rebuild-index over a digest holding BOTH a legacy date-only section
# and new run_id-suffixed ones: legacy lines carry run_id null (they predate
# the key change and must never collide with a real run_id).
LG="$TMP/legacy"; mkdir -p "$LG"
cat > "$LG/digest.md" <<'EOF'
# Digest
<!-- factory-digest:sections -->

## 2026-06-14 — 02:00:00

| id | name | theme | axis | status | (a) coherence | (b) interaction | (c) breakdown-free | (d) humor | (e) development | comment |
|---|---|---|---|---|---|---|---|---|---|---|
| new_b | 新 | t | – | ok | 4 | 3 | 5 | 2 | 3 | c |

## 2026-06-14 — 01:00:00

| id | name | theme | axis | status | (a) coherence | (b) interaction | (c) breakdown-free | (d) humor | (e) development | comment |
|---|---|---|---|---|---|---|---|---|---|---|
| new_a | 新 | t | – | ok | 4 | 3 | 5 | 2 | 3 | c |

## 2026-06-13

| id | name | theme | axis | status | (a) coherence | (b) interaction | (c) breakdown-free | (d) humor | (e) development | comment |
|---|---|---|---|---|---|---|---|---|---|---|
| old_a | 旧 | t | – | ok | 1 | 2 | 3 | 4 | – | c |

<!-- factory-digest:promotion -->
Promotion: x
EOF
python3 "$SCRIPTS/append_digest.py" \
  --digest "$LG/digest.md" --rebuild-index >/dev/null || fail "legacy: rebuild failed"
LGIDX="$LG/digest-index.jsonl"
[ "$(grep -c . "$LGIDX")" -eq 3 ] \
  || fail "legacy: expected 3 lines, got $(grep -c . "$LGIDX")"
jq -es 'map(select(.id=="old_a"))[0].run_id == null' "$LGIDX" >/dev/null \
  || fail "legacy: date-only section should rebuild with run_id null"
jq -es 'map(select(.id=="new_a"))[0].run_id == "01:00:00"' "$LGIDX" >/dev/null \
  || fail "legacy: suffixed section run_id not parsed"
jq -es 'map(select(.id=="new_b"))[0].run_id == "02:00:00"' "$LGIDX" >/dev/null \
  || fail "legacy: second suffixed section not parsed"

# a hand-edited heading suffix is NOT a run_id: rebuild hard-fails rather than
# letting free text into the index, and writes nothing.
BH="$TMP/badheading"; mkdir -p "$BH"
sed 's/^## 2026-06-14 — 02:00:00$/## 2026-06-14 — rerun after the OOM/' \
  "$LG/digest.md" > "$BH/digest.md"
if python3 "$SCRIPTS/append_digest.py" \
  --digest "$BH/digest.md" --rebuild-index >/dev/null 2>"$BH/err"; then
  fail "badheading: a non-run_id heading suffix should hard-fail the rebuild"
fi
grep -q "run_id" "$BH/err" || fail "badheading: error must name run_id"
[ ! -f "$BH/digest-index.jsonl" ] || fail "badheading: index written despite hard-fail"

# (e) the append really takes an exclusive flock on <digest>.lock — the
# compound key alone does not stop a concurrent read-modify-write from losing
# a whole section. A helper holds the lock while an append is launched.
LK="$TMP/lock"; mkdir -p "$LK"
cp fixtures/digest_seed.md "$LK/digest.md"
# The helper takes the flock and only THEN writes a readiness sentinel; the
# shell waits for that sentinel before launching the append, and releases the
# helper through a second sentinel once the assertion is done — so the hold
# always covers the polls without a guessed duration (the 60s inside is a
# safety cap so a broken test cannot hang CI, not a schedule).
python3 - "$LK/digest.md.lock" "$LK/held" "$LK/release" <<'PY' &
import fcntl, os, sys, time
fd = os.open(sys.argv[1], os.O_CREAT | os.O_RDWR, 0o644)
fcntl.flock(fd, fcntl.LOCK_EX)
open(sys.argv[2], "w").close()   # readiness sentinel: the lock is now HELD
deadline = time.time() + 60
while not os.path.exists(sys.argv[3]) and time.time() < deadline:
    time.sleep(0.05)
fcntl.flock(fd, fcntl.LOCK_UN)
os.close(fd)
PY
HOLDER_PID=$!
await_file "$LK/held" "lock: helper never acquired the flock"
python3 "$SCRIPTS/append_digest.py" \
  --results fixtures/results_sample.json --digest "$LK/digest.md" >/dev/null 2>&1 &
APPEND_PID=$!
await_pid "$APPEND_PID" "lock: the append process never came up"
sleep 0.5   # settle: the holder keeps the lock until the release sentinel
            # below, so a generous settle costs wall time, never a false
            # failure — unlike the fixed margin this replaced.
grep -q "^## 2026-06-13" "$LK/digest.md" \
  && fail "lock: append wrote the digest while the lock was held"
: > "$LK/release"
wait "$HOLDER_PID"
wait "$APPEND_PID" || fail "lock: append failed after the lock was released"
grep -q "^## 2026-06-13 — 01:23:45$" "$LK/digest.md" \
  || fail "lock: section missing after the lock was released"
[ "$(grep -c . "$LK/digest-index.jsonl")" -eq 3 ] \
  || fail "lock: sidecar index not updated after the lock was released"

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
# (c) a fixture mirroring the real 14 cases → no warning (all axis/scaffolding-covered)
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

# --- SKILL.md ↔ .gitignore contract (#1541) ---------------------------------
# The paper-tournament seed bank and the incubator queue are local-only files
# the skill writes every night; if either path drops out of .gitignore the
# nightly Routine dirties the main checkout, and if SKILL.md stops naming them
# the prose and the ignore list have drifted apart.
# check-ignore -v names the SOURCE rule, so a match coming from
# .git/info/exclude or a global excludesfile (the tracked entry deleted) fails.
for P in data/factory/sketches/x.md data/factory/incubator.md; do
  SRC=$(git -C "$REPO_ROOT" check-ignore -v "$P" | cut -f1 | cut -d: -f1 || true)
  [ "$SRC" = ".gitignore" ] || fail "gitignore: $P not ignored by tracked .gitignore (source: ${SRC:-none})"
done
grep -q "data/factory/sketches/" ../SKILL.md || fail "SKILL.md: sketch seed bank path missing"
grep -q "data/factory/incubator.md" ../SKILL.md || fail "SKILL.md: incubator queue path missing"

echo "ALL TESTS PASSED"
