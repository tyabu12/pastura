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
