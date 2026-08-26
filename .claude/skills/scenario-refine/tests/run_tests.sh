#!/bin/bash
# Self-test for the scenario-refine helper scripts. No Swift toolchain or
# model needed — exercises inventory selection (rotation / category resolution
# / ja-en tiering) and audit-journal appending ((date, run_id) idempotency /
# baseline delta / failed-run exclusion) against fixtures.
#
# usage: bash .claude/skills/scenario-refine/tests/run_tests.sh
set -eu
cd "$(dirname "$0")"
SCRIPTS=../scripts
INV=fixtures/inv
TMP=$(mktemp -d)
HOLDER_PID=""
# The flock cases below run a lock holder with a 60s deadline. A failing
# assertion must not orphan it: it inherits the harness's stdout, so an
# orphan can stall a piped CI invocation for the whole deadline.
cleanup() { [ -n "$HOLDER_PID" ] && kill "$HOLDER_PID" 2>/dev/null; rm -rf "$TMP"; return 0; }
trap cleanup EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }

# Bounded poll helpers for the flock cases below. Synchronization is by
# sentinel file: the append is launched through a wrapper that touches a
# "started" sentinel immediately before exec'ing python, and the holder keeps
# the lock until the release sentinel. The short settle after the started
# sentinel IS a sleep margin, but a one-sided one — the lock is still held
# across it, so a slow python start can only yield a false PASS, never a false
# failure. What makes the case bite is the liveness assertion immediately
# before the release (the append must still be running, and not defunct)
# together with the post-release assertions. Every poll is capped so a hang
# fails loudly, not silently.
await_file() {   # $1 = path to wait for, $2 = failure message
  local i=0
  until [ -e "$1" ]; do
    i=$((i + 1)); [ "$i" -le 600 ] || fail "$2 (timed out after ~600 polls)"
    sleep 0.1
  done
}

sel() { # run select_inventory.py against the fixture inventory
  python3 "$SCRIPTS/select_inventory.py" \
    --presets-dir "$INV/presets" \
    --gallery-dir "$INV/gallery" \
    --gallery-json "$INV/gallery/gallery.json" \
    "$@"
}

# --- select_inventory.py: category / 4th-axis resolution --------------------
J=$(sel --count 99 --journal fixtures/journal_seed.md)
axis() { echo "$J" | jq -r --arg id "$1" '.[] | select(.id==$id) | .payoff_axis'; }
cat_of() { echo "$J" | jq -r --arg id "$1" '.[] | select(.id==$id) | .category'; }

[ "$(cat_of bokete)" = "creative" ] || fail "bokete category != creative"
[ "$(axis bokete)" = "humor" ] || fail "bokete axis != humor"
[ "$(cat_of word_wolf)" = "game_theory" ] || fail "word_wolf category != game_theory"
[ "$(axis word_wolf)" = "strategic_tension" ] || fail "word_wolf axis != strategic_tension"
[ "$(cat_of asch_conformity_v1)" = "social_psychology" ] || fail "asch category"
[ "$(axis asch_conformity_v1)" = "phenomenon_visible" ] || fail "asch axis"
[ "$(cat_of trolley_dilemma_v1)" = "ethics" ] || fail "trolley category"
[ "$(axis trolley_dilemma_v1)" = "moral_divergence" ] || fail "trolley axis"
# experimental category is not in CATEGORY_AXIS → generic fallback, no KeyError
[ "$(cat_of weird_experimental_v1)" = "experimental" ] || fail "experimental category"
[ "$(axis weird_experimental_v1)" = "overall_engagement" ] || fail "experimental fallback axis"

# --- select_inventory.py: rotation (least-recently-evaluated first) ---------
# word_wolf was evaluated 2026-06-20 in the seed; everything else is new.
WW_DATE=$(echo "$J" | jq -r '.[] | select(.id=="word_wolf") | .last_evaluated')
[ "$WW_DATE" = "2026-06-20" ] || fail "word_wolf last_evaluated should be 2026-06-20, got $WW_DATE"
FIRST_DATE=$(echo "$J" | jq -r '.[0].last_evaluated')
[ "$FIRST_DATE" = "null" ] || fail "first selected should be never-evaluated (null), got $FIRST_DATE"
# the evaluated scenario must not outrank a never-evaluated one
WW_POS=$(echo "$J" | jq -r 'to_entries | .[] | select(.value.id=="word_wolf") | .key')
[ "$WW_POS" -gt 0 ] || fail "evaluated word_wolf should not be ranked first"

# --- select_inventory.py: model keying -------------------------------------
# A different model has never evaluated anything → word_wolf reads as new.
JM=$(sel --count 99 --journal fixtures/journal_seed.md --model other-model)
WW_OTHER=$(echo "$JM" | jq -r '.[] | select(.id=="word_wolf") | .last_evaluated')
[ "$WW_OTHER" = "null" ] || fail "model-mismatch should null out last_evaluated, got $WW_OTHER"

# --- select_inventory.py: ja primary before en sampling --------------------
# 5 ja/non-en primaries + 1 en (bokete_en). count=5 must exclude the en sibling.
J5=$(sel --count 5 --journal fixtures/journal_seed.md)
echo "$J5" | jq -e '[.[].id] | index("bokete_en") | not' >/dev/null \
  || fail "en sibling selected before primaries exhausted (count=5)"
echo "$J5" | jq -e 'length == 5' >/dev/null || fail "count=5 should select 5"
# count=6 reaches into the en tier
J6=$(sel --count 6 --journal fixtures/journal_seed.md)
echo "$J6" | jq -e '[.[].id] | index("bokete_en")' >/dev/null \
  || fail "en sibling should be reached at count=6"

# --- select_inventory.py: --only explicit pick (skips rotation/count) ------
JO=$(sel --count 1 --journal fixtures/journal_seed.md --only "bokete,word_wolf")
echo "$JO" | jq -e 'length == 2' >/dev/null || fail "--only should return exactly the 2 named (ignoring count)"
echo "$JO" | jq -e '[.[].id] | sort == ["bokete","word_wolf"]' >/dev/null \
  || fail "--only returned the wrong ids"

# --- select_inventory.py: empty / absent journal (first-run path) -----------
JE=$(sel --count 99 --journal "$TMP/does_not_exist.md")
echo "$JE" | jq -e 'all(.last_evaluated == null)' >/dev/null \
  || fail "absent journal should leave every last_evaluated null"
echo "$JE" | jq -e 'length >= 6' >/dev/null || fail "absent journal should still enumerate inventory"

# --- append_audit.py: section render + baseline delta ----------------------
cp fixtures/journal_seed.md "$TMP/journal.md"
python3 "$SCRIPTS/append_audit.py" \
  --results fixtures/results_sample.json --journal "$TMP/journal.md" >/dev/null
grep -q "^## 2026-06-21 — 01:00:00$" "$TMP/journal.md" || fail "audit: section heading missing"

# The Δ cell is field 11 when the row is split on " | " (the development
# column shifted it from 10 to 11); its first token is the signed delta, any
# ⚠️ / ✅ flag follows. Always compare that token for EQUALITY — a bare
# `grep -- "+1"` also matches +10, a raw score column, or a comment.
# NR==1: a whole-journal grep returns one row per section, newest first, and
# these assertions are about the section just appended.
delta_of() { echo "$1" | awk -F' \\| ' 'NR==1 {print $11}' | awk '{print $1}'; }
# Whole-cell variant, for a Δ whose text is multi-token and so has no single
# "delta token" to isolate: "vs base +2 ✅" (A/B candidate) as well as
# "-4 ⚠️" (regression). Same reason as above — `grep -q "vs base +2"` also
# matches "vs base +20", and a Δ against a 25-point total can reach ±20.
delta_cell() { echo "$1" | awk -F' \\| ' 'NR==1 {print $11}'; }

# regression: word_wolf prior total 16 (2026-06-20) → new 12 → Δ-4, flagged ⚠️
WW_ROW=$(grep '^| word_wolf ' "$TMP/journal.md")
WW_DELTA=$(delta_of "$WW_ROW")
[ "$WW_DELTA" = "-4" ] \
  || fail "audit: word_wolf regression delta must be exactly -4, got '$WW_DELTA'"
echo "$WW_ROW" | grep -q "⚠️" || fail "audit: regression ⚠️ flag missing"

# A/B candidate: bokete__v2 total 20 vs same-run baseline bokete 18 → vs base +2
CAND_ROW=$(grep '^| bokete__v2 ' "$TMP/journal.md")
CAND_DELTA=$(delta_cell "$CAND_ROW")
[ "$CAND_DELTA" = "vs base +2 ✅" ] \
  || fail "audit: A/B delta cell must be exactly 'vs base +2 ✅', got '$CAND_DELTA'"
echo "$CAND_ROW" | grep -q "✅" || fail "audit: A/B win ✅ missing"

# bokete itself has no prior baseline → Δ em-dash, not a number. Field 11
# (split on " | ") is the Δ cell — the development column shifted it from 10 to
# 11; reverting the "if base is None: return –" arm would make this a spurious
# number and fail here.
BK_ROW=$(grep '^| bokete ' "$TMP/journal.md")
BK_DELTA=$(echo "$BK_ROW" | awk -F' \\| ' '{print $11}')
[ "$BK_DELTA" = "–" ] || fail "audit: no-prior-baseline Δ must be em-dash, got '$BK_DELTA'"

# header carries the new universal (d) development column, and the payoff
# column still renders the per-scenario payoff_axis name (word_wolf →
# strategic_tension), not a static "payoff" label.
grep -q "(d) development" "$TMP/journal.md" || fail "audit: (d) development header column missing"
echo "$WW_ROW" | grep -q "strategic_tension" \
  || fail "audit: payoff column lost per-scenario payoff_axis name"

# failed run: no scores, Δ em-dash, error surfaced in comment
DET_ROW=$(grep '^| detective_scene_v1 ' "$TMP/journal.md")
echo "$DET_ROW" | grep -q "failed" || fail "audit: failed status missing"
echo "$DET_ROW" | grep -q "#253" || fail "audit: failed error not surfaced in comment"

# machine-readable comment present; pipe escaped in human comment cell
grep -q "audit-data:" "$TMP/journal.md" || fail "audit: data comment missing"
echo "$WW_ROW" | grep -q '噛み合わせ \\| が弱い' || fail "audit: pipe not escaped in comment"

# failed run excluded from scores in the data comment (status only)
DATA=$(grep -o '<!-- audit-data: .* -->' "$TMP/journal.md" \
  | sed 's/^<!-- audit-data: //; s/ -->$//' | jq -s '.[] | select(.date=="2026-06-21")')
echo "$DATA" | jq -e '.scenarios.detective_scene_v1.status == "failed"' >/dev/null \
  || fail "audit: failed run should be in data comment as failed"
echo "$DATA" | jq -e '.scenarios.detective_scene_v1 | has("coherence") | not' >/dev/null \
  || fail "audit: failed run must carry no scores"
echo "$DATA" | jq -e '.scenarios.word_wolf.coherence == 3' >/dev/null \
  || fail "audit: ok run scores missing from data comment"

# --- append_audit.py: round-trip into select rotation ----------------------
# After appending, the evaluated ids must read as evaluated-today in select.
RT=$(python3 "$SCRIPTS/select_inventory.py" \
  --presets-dir "$INV/presets" --gallery-dir "$INV/gallery" \
  --gallery-json "$INV/gallery/gallery.json" --count 99 --journal "$TMP/journal.md")
RT_WW=$(echo "$RT" | jq -r '.[] | select(.id=="word_wolf") | .last_evaluated')
[ "$RT_WW" = "2026-06-21" ] || fail "round-trip: word_wolf should read evaluated 2026-06-21, got $RT_WW"

# --- append_audit.py: (date, run_id) idempotency ----------------------------
python3 "$SCRIPTS/append_audit.py" \
  --results fixtures/results_sample.json --journal "$TMP/journal.md" >/dev/null 2>"$TMP/warn"
COUNT=$(grep -c "^## 2026-06-21 — 01:00:00$" "$TMP/journal.md")
[ "$COUNT" -eq 1 ] || fail "audit: re-append duplicated the section ($COUNT)"
grep -q "warning: replaced" "$TMP/warn" || fail "audit: replace warning missing"
# re-running the same (date, run_id) must NOT use the replaced section as its
# own baseline — word_wolf still compares to 2026-06-20, so Δ stays -4 (not 0).
RERUN_DELTA=$(delta_of "$(grep '^| word_wolf ' "$TMP/journal.md")")
[ "$RERUN_DELTA" = "-4" ] \
  || fail "audit: same-key re-run must not self-baseline (Δ should stay -4, got '$RERUN_DELTA')"

# --- append_audit.py: markers + bootstrap ----------------------------------
echo "# broken" > "$TMP/broken.md"
if python3 "$SCRIPTS/append_audit.py" \
  --results fixtures/results_sample.json --journal "$TMP/broken.md" 2>/dev/null; then
  fail "audit: missing markers should be a hard error"
fi
python3 "$SCRIPTS/append_audit.py" \
  --results fixtures/results_sample.json --journal "$TMP/bootstrap.md" >/dev/null \
  || fail "audit: absent file should bootstrap, not error"
grep -q "audit-digest:sections" "$TMP/bootstrap.md" || fail "bootstrap: sections marker missing"
grep -q "audit-digest:promotion" "$TMP/bootstrap.md" || fail "bootstrap: promotion marker missing"
grep -q "^## 2026-06-21 — 01:00:00$" "$TMP/bootstrap.md" || fail "bootstrap: section not appended"
tail -1 "$TMP/bootstrap.md" | grep -q "^Promotion:" || fail "bootstrap: promotion line not last"

# --- append_audit.py: malformed prior ok record warns (not silent) ---------
# A prior ok record missing an axis must emit a stderr warning rather than
# silently dropping out of the baseline.
cat > "$TMP/malformed.md" <<'EOF'
# seed
<!-- audit-digest:sections -->
## 2026-06-19

<!-- audit-data: {"date": "2026-06-19", "model": "gemma-4-E2B-it-Q4_K_M", "scenarios": {"bokete": {"coherence": 4, "interaction": 4, "breakdown_free": 4, "status": "ok"}}} -->

<!-- audit-digest:promotion -->
Promotion: x
EOF
python3 "$SCRIPTS/append_audit.py" \
  --results fixtures/results_sample.json --journal "$TMP/malformed.md" \
  >/dev/null 2>"$TMP/mwarn"
grep -q "missing score axes" "$TMP/mwarn" \
  || fail "audit: malformed prior ok record should warn, not silently skip"
# the warning is AGGREGATED — a single summary line for the whole run, not one
# line per skipped record.
MWARN_COUNT=$(grep -c "missing score axes" "$TMP/mwarn")
[ "$MWARN_COUNT" -eq 1 ] || fail "audit: skip warning should be a single aggregated line, got $MWARN_COUNT"

# --- append_audit.py: old-4-key (pre-development) baseline migration --------
# A prior ok record from before `development` existed (4 keys) is a different
# total scale, so it is skipped as a baseline and the Δ one-time-resets to –
# (em-dash) — never a bogus number. The skip must not crash the append, and it
# emits exactly one aggregated warning containing "missing score axes".
cat > "$TMP/migrate.md" <<'EOF'
# seed
<!-- audit-digest:sections -->
## 2026-06-19

<!-- audit-data: {"date": "2026-06-19", "model": "gemma-4-E2B-it-Q4_K_M", "scenarios": {"word_wolf": {"coherence": 4, "interaction": 4, "breakdown_free": 5, "payoff": 3, "payoff_axis": "strategic_tension", "status": "ok"}}} -->

<!-- audit-digest:promotion -->
Promotion: x
EOF
python3 "$SCRIPTS/append_audit.py" \
  --results fixtures/results_sample.json --journal "$TMP/migrate.md" \
  >/dev/null 2>"$TMP/migwarn" || fail "migration: old-4-key prior must not crash append"
MIG_WW=$(grep '^| word_wolf ' "$TMP/migrate.md")
MIG_DELTA=$(echo "$MIG_WW" | awk -F' \\| ' '{print $11}')
[ "$MIG_DELTA" = "–" ] || fail "migration: old-4-key prior must reset Δ to em-dash, got '$MIG_DELTA'"
MIG_COUNT=$(grep -c "missing score axes" "$TMP/migwarn")
[ "$MIG_COUNT" -eq 1 ] || fail "migration: aggregated warning should appear exactly once, got $MIG_COUNT"

# --- append_audit.py: null development (single-round scenario) --------------
# `development` (cross-round development / surprise) is null for single-round
# scenarios. total() must not crash on the present-but-null key, and the (d)
# column renders – via the null-cell path.
cat > "$TMP/nulldev.json" <<'EOF'
{
  "date": "2026-06-22",
  "run_id": "01:00:00",
  "model": "gemma-4-E2B-it-Q4_K_M",
  "scenarios": [
    {"id": "single_round_v1", "name": "SR", "channel": "preset",
     "category": "creative", "status": "ok",
     "scores": {"coherence": 4, "interaction": 4, "breakdown_free": 4,
                "development": null, "payoff": 3},
     "payoff_axis": "humor", "comment": "single round", "candidate_of": null}
  ]
}
EOF
python3 "$SCRIPTS/append_audit.py" \
  --results "$TMP/nulldev.json" --journal "$TMP/nulldev.md" >/dev/null 2>&1 \
  || fail "null development must not crash append_audit"
ND_ROW=$(grep '^| single_round_v1 ' "$TMP/nulldev.md")
ND_DEV=$(echo "$ND_ROW" | awk -F' \\| ' '{print $9}')
[ "$ND_DEV" = "–" ] || fail "null development must render em-dash in (d) column, got '$ND_DEV'"

# --- append_audit.py: (date, run_id) section key (#1542) --------------------
# Two /scenario-refine cycles can share a date in the same main checkout (a
# re-run after a fix, a second nightly pass). Before #1542 the second append
# silently wiped the first run's audit record — the journal is the only
# durable one — so these cases pin the compound key.
RK="$TMP/runkey"; mkdir -p "$RK"
cp fixtures/journal_seed.md "$RK/journal.md"
# run 2: same date, later run_id, word_wolf one point better (total 17).
jq '.run_id = "02:00:00" | .scenarios[0].scores.coherence = 4' \
  fixtures/results_sample.json > "$RK/results_run2.json"

# (a) REGRESSION TEST FOR #1542: same date, different run_ids → both survive.
python3 "$SCRIPTS/append_audit.py" \
  --results fixtures/results_sample.json --journal "$RK/journal.md" >/dev/null
python3 "$SCRIPTS/append_audit.py" \
  --results "$RK/results_run2.json" --journal "$RK/journal.md" >/dev/null
grep -q "^## 2026-06-21 — 01:00:00$" "$RK/journal.md" \
  || fail "runkey: first run's section wiped by a same-date second run (#1542)"
grep -q "^## 2026-06-21 — 02:00:00$" "$RK/journal.md" \
  || fail "runkey: second run's section missing"
[ "$(grep -c '<!-- audit-data: ' "$RK/journal.md")" -eq 3 ] \
  || fail "runkey: expected 3 audit-data comments (seed + 2 runs)"
# run_id rides in the audit-data payload alongside date
grep -o '<!-- audit-data: .* -->' "$RK/journal.md" \
  | sed 's/^<!-- audit-data: //; s/ -->$//' \
  | jq -es 'map(select(.run_id=="02:00:00")) | length == 1' >/dev/null \
  || fail "runkey: run_id missing from the audit-data payload"

# (d) refine-specific: a sibling run EARLIER the same date is a legitimate Δ
# baseline — the exclusion unit is (date, run_id), not the whole date. run 2's
# word_wolf (17) is scored against run 1 (16) → +1, not against 2026-06-20
# (20, which would give -3).
ww_row_of() { # $1 = run_id: the word_wolf row inside that run's section
  awk -v h="## 2026-06-21 — $1" \
    '$0 == h {inside=1; next} /^## / {inside=0} inside' "$RK/journal.md" \
    | grep '^| word_wolf '
}
RK_WW=$(delta_of "$(ww_row_of "02:00:00")")
[ "$RK_WW" = "+1" ] \
  || fail "runkey: same-date sibling run must stay available as a Δ baseline (expected +1, got '$RK_WW')"

# (b) re-appending the SAME (date, run_id) replaces only that section, and
# still excludes itself from its own baseline (Δ stays +1, never 0).
python3 "$SCRIPTS/append_audit.py" \
  --results "$RK/results_run2.json" --journal "$RK/journal.md" >/dev/null 2>"$RK/warn"
grep -q "warning: replaced" "$RK/warn" || fail "runkey: replace warning missing"
[ "$(grep -c "^## 2026-06-21 — 02:00:00$" "$RK/journal.md")" -eq 1 ] \
  || fail "runkey: same-key re-append duplicated the section"
[ "$(grep -c "^## 2026-06-21 — 01:00:00$" "$RK/journal.md")" -eq 1 ] \
  || fail "runkey: sibling run's section disturbed by a same-key re-append"
RK_WW2=$(delta_of "$(ww_row_of "02:00:00")")
[ "$RK_WW2" = "+1" ] \
  || fail "runkey: same-key re-append must not self-baseline (expected +1, got '$RK_WW2')"

# the newest of two same-date siblings wins the "most recent prior" pick, so a
# third run resolves deterministically against run 2 (17) → Δ 0, not run 1.
jq '.run_id = "03:00:00" | .scenarios[0].scores.coherence = 4' \
  fixtures/results_sample.json > "$RK/results_run3.json"
python3 "$SCRIPTS/append_audit.py" \
  --results "$RK/results_run3.json" --journal "$RK/journal.md" >/dev/null
RK_WW3=$(delta_of "$(ww_row_of "03:00:00")")
[ "$RK_WW3" = "+0" ] \
  || fail "runkey: baseline pick must order by (date, run_id) (expected +0, got '$RK_WW3')"

# a legacy date-only heading in an existing local journal survives untouched
LG="$TMP/legacy"; mkdir -p "$LG"
cp fixtures/journal_seed.md "$LG/journal.md"
jq '.run_id = "01:00:00" | .date = "2026-06-20"' \
  fixtures/results_sample.json > "$LG/results_same_date.json"
python3 "$SCRIPTS/append_audit.py" \
  --results "$LG/results_same_date.json" --journal "$LG/journal.md" >/dev/null
grep -q "^## 2026-06-20$" "$LG/journal.md" \
  || fail "legacy: pre-#1542 date-only section must survive an append on its date"
grep -q "^## 2026-06-20 — 01:00:00$" "$LG/journal.md" \
  || fail "legacy: new section missing"

# (c) run_id is REQUIRED and shape-checked; a rejected results JSON must leave
# the journal byte-identical (an unattended run has to be recoverable by hand).
RV="$TMP/runid_valid"; mkdir -p "$RV"
cp "$RK/journal.md" "$RV/journal.md"
cp "$RV/journal.md" "$RV/journal.before"
jq 'del(.run_id)' fixtures/results_sample.json > "$RV/no_run_id.json"
if python3 "$SCRIPTS/append_audit.py" \
  --results "$RV/no_run_id.json" --journal "$RV/journal.md" 2>"$RV/err"; then
  fail "runid: missing run_id should be a hard error"
fi
grep -q "run_id" "$RV/err" || fail "runid: error message must name run_id"
grep -q "no_run_id.json" "$RV/err" || fail "runid: error message must name the results path"
cmp -s "$RV/journal.before" "$RV/journal.md" || fail "runid: journal touched by a rejected append"
# 99:99 has the right shape but is not a real clock time
jq '.run_id = "99:99"' fixtures/results_sample.json > "$RV/bad_clock.json"
if python3 "$SCRIPTS/append_audit.py" \
  --results "$RV/bad_clock.json" --journal "$RV/journal.md" 2>/dev/null; then
  fail "runid: 99:99 should be rejected as a non-clock run_id"
fi
cmp -s "$RV/journal.before" "$RV/journal.md" || fail "runid: journal touched by an invalid run_id"

# (e) the append really takes an exclusive flock on <journal>.lock — the
# compound key alone does not stop a concurrent read-modify-write from losing
# a whole section. A helper holds the lock while an append is launched.
LK="$TMP/lock"; mkdir -p "$LK"
cp fixtures/journal_seed.md "$LK/journal.md"
# The helper takes the flock and only THEN writes a readiness sentinel; the
# shell waits for that sentinel before launching the append, and releases the
# helper through a second sentinel once the assertion is done — so the hold
# always covers the polls without a guessed duration (the 60s inside is a
# safety cap so a broken test cannot hang CI, not a schedule — blowing it
# exits the helper non-zero, which the wait below turns into a FAIL).
python3 - "$LK/journal.md.lock" "$LK/held" "$LK/release" <<'PY' &
import fcntl, os, sys, time
fd = os.open(sys.argv[1], os.O_CREAT | os.O_RDWR, 0o644)
fcntl.flock(fd, fcntl.LOCK_EX)
open(sys.argv[2], "w").close()   # readiness sentinel: the lock is now HELD
deadline = time.time() + 60
while not os.path.exists(sys.argv[3]):
    if time.time() >= deadline:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)
        sys.exit("lock helper: release sentinel never appeared")
    time.sleep(0.05)
fcntl.flock(fd, fcntl.LOCK_UN)
os.close(fd)
PY
HOLDER_PID=$!
await_file "$LK/held" "lock: helper never acquired the flock"
# bash assigns $! at fork and `kill -0` also succeeds on an unreaped zombie,
# so neither proves the append got as far as the lock. Launch it through a
# wrapper that touches a "started" sentinel immediately before exec'ing
# python (exec keeps $! pointing at the python process itself).
cat > "$LK/append_wrapper.sh" <<'EOF'
#!/bin/bash
# $1 = "started" sentinel; the rest is the command to exec.
started=$1; shift
: > "$started"
exec "$@"
EOF
bash "$LK/append_wrapper.sh" "$LK/started" \
  python3 "$SCRIPTS/append_audit.py" \
  --results fixtures/results_sample.json --journal "$LK/journal.md" >/dev/null 2>&1 &
APPEND_PID=$!
await_file "$LK/started" "lock: the append never started"
sleep 0.5   # one-sided settle: the holder keeps the lock across it, so this
            # can only cost wall time, never a false failure.
# ...and the append must still be ALIVE and blocked here. An append that
# already exited — or that never took the lock at all — would satisfy the
# "did not write" assertion below vacuously.
APPEND_STATE=$(ps -o state= -p "$APPEND_PID" 2>/dev/null | tr -d '[:space:]' || true)
[ -n "$APPEND_STATE" ] \
  || fail "lock: the append exited instead of blocking on the held lock"
case "$APPEND_STATE" in
  Z*) fail "lock: the append is defunct — it exited instead of blocking on the held lock" ;;
esac
grep -q "^## 2026-06-21" "$LK/journal.md" \
  && fail "lock: append wrote the journal while the lock was held"
: > "$LK/release"
wait "$HOLDER_PID" || fail "lock: holder timed out waiting for the release sentinel"
HOLDER_PID=""
wait "$APPEND_PID" || fail "lock: append failed after the lock was released"
grep -q "^## 2026-06-21 — 01:00:00$" "$LK/journal.md" \
  || fail "lock: section missing after the lock was released"

echo "ALL TESTS PASSED"
