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

echo "ALL TESTS PASSED"
