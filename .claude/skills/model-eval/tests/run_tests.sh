#!/bin/bash
# Self-test for the model-eval helper scripts. No Swift toolchain, model, or
# network needed — exercises harness-JSONL metrics analysis
# (analyze_model_eval.py), scorecard journal appending (append_eval.py), and
# the run_scenario.sh `--profile` argv passthrough (via a fake shell
# "harness" canary, PASTURA_HARNESS_BIN test seam) against fixtures.
#
# usage: bash .claude/skills/model-eval/tests/run_tests.sh
set -eu
cd "$(dirname "$0")"
SCRIPTS=../scripts
REPO_ROOT="$(cd ../../../.. && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- analyze_model_eval.py --------------------------------------------------
RESULT=$(python3 "$SCRIPTS/analyze_model_eval.py" fixtures/run_ok.jsonl fixtures/run_crashed.jsonl)
echo "$RESULT" > "$TMP/analyze_out.json"

python3 - "$TMP/analyze_out.json" <<'PYEOF' || fail "analyze: field assertions failed"
import json, sys

with open(sys.argv[1], encoding="utf-8") as f:
    d = json.load(f)

runs = d["runs"]
assert len(runs) == 2, f"expected 2 runs, got {len(runs)}"

ok = runs[0]
assert ok["file"] == "run_ok.jsonl", ok
assert ok["run_id"] == "20260707-000000-aaaa", ok
assert ok["scenario_id"] == "bokete", ok
assert ok["language"] == "ja", ok
assert ok["model"] == "qwen-3-4b-q4-k-m", ok
assert ok["status"] == "ok", ok
assert ok["attempts"] == 2, ok
assert ok["inferences"] == 2, ok
assert ok["language_mismatches"] == 1, ok
assert ok["tokens"] == 150, ok
assert ok["gen_seconds"] == 10.0, ok
assert ok["tok_per_sec"] == 15.0, ok
assert ok["skipped_lines"] == 0, ok

crashed = runs[1]
assert crashed["file"] == "run_crashed.jsonl", crashed
assert crashed["run_id"] == "20260707-000001-bbbb", crashed
assert crashed["status"] == "crashed", crashed
assert crashed["attempts"] is None, crashed
assert crashed["inferences"] == 0, crashed
assert crashed["skipped_lines"] == 1, crashed

agg = d["aggregate"]
assert agg["runs_total"] == 2, agg
assert agg["runs_ok"] == 1, agg
assert agg["runs_failed"] == 1, agg
assert agg["attempts_total"] == 2, agg
assert agg["attempts_mean"] == 2.0, agg
assert agg["inferences_total"] == 2, agg
assert agg["language_mismatch_total"] == 1, agg
assert agg["tok_per_sec_overall"] == 15.0, agg

print("analyze: OK")
PYEOF

# no-args invocation exits 2
set +e
python3 "$SCRIPTS/analyze_model_eval.py" >/dev/null 2>"$TMP/noargs_err"
RC=$?
set -e
[ "$RC" -eq 2 ] || fail "analyze: no-args invocation should exit 2, got $RC"

# --- append_eval.py ----------------------------------------------------------
JOURNAL="$TMP/eval-digest.md"

python3 "$SCRIPTS/append_eval.py" \
  --results fixtures/results_sample.json --journal "$JOURNAL" >/dev/null \
  || fail "append: bootstrap + first append should succeed"

SECTIONS_COUNT=$(grep -c -- "<!-- model-eval:sections -->" "$JOURNAL")
[ "$SECTIONS_COUNT" -eq 1 ] || fail "append: sections marker should appear once, got $SECTIONS_COUNT"
FOOTER_COUNT=$(grep -c -- "<!-- model-eval:footer -->" "$JOURNAL")
[ "$FOOTER_COUNT" -eq 1 ] || fail "append: footer marker should appear once, got $FOOTER_COUNT"
grep -q "^## 2026-07-07 — qwen-3-4b-q4-k-m" "$JOURNAL" \
  || fail "append: section heading missing"

DATA=$(grep -o -- '<!-- eval-data: .* -->' "$JOURNAL" | sed 's/^<!-- eval-data: //; s/ -->$//' | head -1)
printf '%s' "$DATA" | python3 -c "import json, sys; json.loads(sys.stdin.read())" \
  || fail "append: eval-data comment is not valid JSON"

# re-append the SAME (date, profile_id) -> replace, not duplicate
python3 "$SCRIPTS/append_eval.py" \
  --results fixtures/results_sample.json --journal "$JOURNAL" >/dev/null 2>"$TMP/warn1"
COUNT=$(grep -c "^## 2026-07-07 — qwen-3-4b-q4-k-m" "$JOURNAL")
[ "$COUNT" -eq 1 ] || fail "append: re-append duplicated the section ($COUNT)"
grep -q "warning: replaced" "$TMP/warn1" || fail "append: replace warning missing on stderr"

# a second profile_id, same date -> 2 sections for that date
python3 "$SCRIPTS/append_eval.py" \
  --results fixtures/results_sample_profile2.json --journal "$JOURNAL" >/dev/null \
  || fail "append: second profile append should succeed"
COUNT2=$(grep -c "^## 2026-07-07 — " "$JOURNAL")
[ "$COUNT2" -eq 2 ] || fail "append: expected 2 sections for 2026-07-07, got $COUNT2"

# invalid fixture (verdict.gate "maybe") -> exit 1, journal untouched
set +e
python3 "$SCRIPTS/append_eval.py" \
  --results fixtures/results_invalid_gate.json --journal "$JOURNAL" >/dev/null 2>"$TMP/invalid_err"
RC=$?
set -e
[ "$RC" -eq 1 ] || fail "append: invalid verdict.gate fixture should exit 1, got $RC"
grep -q "gate" "$TMP/invalid_err" || fail "append: invalid-gate error message missing"

# --- run_scenario.sh --profile canary (PASTURA_HARNESS_BIN test seam) ------
FAKE_BIN="$TMP/fake_harness.sh"
cat > "$FAKE_BIN" <<'EOF'
#!/bin/bash
# Fake harness: records its argv, writes a minimal valid run JSONL to the
# path after --out, exits 0. Used to canary run_scenario.sh's argv building
# (esp. the --profile passthrough) without a Swift toolchain.
set -eu
: "${FAKE_ARGV_CAPTURE:?FAKE_ARGV_CAPTURE not set}"
printf '%s\n' "$*" >> "$FAKE_ARGV_CAPTURE"
OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT=$2; shift 2 ;;
    *) shift ;;
  esac
done
if [ -n "$OUT" ]; then
  printf '%s\n' '{"type":"run_start","estimated_inferences":1}' > "$OUT"
  printf '%s\n' '{"type":"run_end","status":"ok"}' >> "$OUT"
fi
exit 0
EOF
chmod +x "$FAKE_BIN"

DUMMY_YAML="$TMP/dummy.yaml"
DUMMY_GGUF="$TMP/dummy.gguf"
: > "$DUMMY_YAML"
: > "$DUMMY_GGUF"

# with a 5th positional arg -> --profile passed through
ARGV1="$TMP/argv1.log"
STATUS1=$(
  cd "$REPO_ROOT" && \
  PASTURA_HARNESS_BIN="$FAKE_BIN" FAKE_ARGV_CAPTURE="$ARGV1" \
  bash .claude/skills/scenario-factory/scripts/run_scenario.sh \
    "$DUMMY_YAML" "$DUMMY_GGUF" "$TMP/out1.jsonl" 60 qwen-3-4b-q4-k-m
)
printf '%s' "$STATUS1" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['status']=='ok', d" \
  || fail "run_scenario: profile canary expected status ok, got: $STATUS1"
grep -q -- "--profile qwen-3-4b-q4-k-m" "$ARGV1" \
  || fail "run_scenario: --profile not passed through argv"

# without the 5th arg -> no --profile in argv
ARGV2="$TMP/argv2.log"
STATUS2=$(
  cd "$REPO_ROOT" && \
  PASTURA_HARNESS_BIN="$FAKE_BIN" FAKE_ARGV_CAPTURE="$ARGV2" \
  bash .claude/skills/scenario-factory/scripts/run_scenario.sh \
    "$DUMMY_YAML" "$DUMMY_GGUF" "$TMP/out2.jsonl" 60
)
printf '%s' "$STATUS2" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['status']=='ok', d" \
  || fail "run_scenario: no-profile invocation expected status ok, got: $STATUS2"
if grep -q -- "--profile" "$ARGV2"; then
  fail "run_scenario: --profile should NOT be passed without the 5th arg"
fi

# --- run_scenario.sh --backend / --guardrails canary (#1072) ----------------
# The foundation-models re-run drives these; they are trailing FLAGS, so they
# must be reachable without a profile placeholder, and `-` must suppress
# --model (FM has no GGUF file).
ARGV3="$TMP/argv3.log"
STATUS3=$(
  cd "$REPO_ROOT" && \
  PASTURA_HARNESS_BIN="$FAKE_BIN" FAKE_ARGV_CAPTURE="$ARGV3" \
  bash .claude/skills/scenario-factory/scripts/run_scenario.sh \
    "$DUMMY_YAML" - "$TMP/out3.jsonl" 60 --backend foundation-models --guardrails permissive
)
printf '%s' "$STATUS3" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['status']=='ok', d" \
  || fail "run_scenario: fm canary expected status ok, got: $STATUS3"
grep -q -- "--backend foundation-models" "$ARGV3" \
  || fail "run_scenario: --backend not passed through argv"
grep -q -- "--guardrails permissive" "$ARGV3" \
  || fail "run_scenario: --guardrails not passed through argv"
if grep -q -- "--model" "$ARGV3"; then
  fail "run_scenario: --model must be omitted when the model arg is '-'"
fi
if grep -q -- "--profile" "$ARGV3"; then
  fail "run_scenario: --profile should NOT be passed when only trailing flags follow timeout"
fi

# --- run_scenario.sh --max-response-tokens / --guided-generation (#1154) ----
# The FM token-budget battery drives these. `--guided-generation` is a BOOLEAN
# flag consuming no value; a parser that treated it as value-taking would
# silently swallow whatever followed it, so the canary puts another flag after
# it and asserts that one survives.
ARGV_FM="$TMP/argv_fm.log"
STATUS_FM=$(
  cd "$REPO_ROOT" && \
  PASTURA_HARNESS_BIN="$FAKE_BIN" FAKE_ARGV_CAPTURE="$ARGV_FM" \
  bash .claude/skills/scenario-factory/scripts/run_scenario.sh \
    "$DUMMY_YAML" - "$TMP/out_fm.jsonl" 60 --backend foundation-models \
    --guided-generation --max-response-tokens 512
)
printf '%s' "$STATUS_FM" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['status']=='ok', d" \
  || fail "run_scenario: fm token-budget canary expected status ok, got: $STATUS_FM"
grep -q -- "--guided-generation" "$ARGV_FM" \
  || fail "run_scenario: --guided-generation not passed through argv"
grep -q -- "--max-response-tokens 512" "$ARGV_FM" \
  || fail "run_scenario: --max-response-tokens not passed through argv (swallowed by the boolean flag?)"

# neither flag appears unless asked for — otherwise every prior battery's argv
# would silently change shape
if grep -q -- "--guided-generation" "$ARGV3"; then
  fail "run_scenario: --guided-generation must not appear unless requested"
fi
if grep -q -- "--max-response-tokens" "$ARGV3"; then
  fail "run_scenario: --max-response-tokens must not appear unless requested"
fi

# trailing flags must not disturb the llama-cpp default path
ARGV4="$TMP/argv4.log"
STATUS4=$(
  cd "$REPO_ROOT" && \
  PASTURA_HARNESS_BIN="$FAKE_BIN" FAKE_ARGV_CAPTURE="$ARGV4" \
  bash .claude/skills/scenario-factory/scripts/run_scenario.sh \
    "$DUMMY_YAML" "$DUMMY_GGUF" "$TMP/out4.jsonl" 60 gemma-4-e2b --guardrails permissive
)
printf '%s' "$STATUS4" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['status']=='ok', d" \
  || fail "run_scenario: profile+flag canary expected status ok, got: $STATUS4"
grep -q -- "--model $DUMMY_GGUF" "$ARGV4" \
  || fail "run_scenario: --model must still pass through alongside trailing flags"
grep -q -- "--profile gemma-4-e2b" "$ARGV4" \
  || fail "run_scenario: --profile must still pass through alongside trailing flags"
grep -q -- "--guardrails permissive" "$ARGV4" \
  || fail "run_scenario: --guardrails not passed through after a profile positional"

# an unknown trailing flag is a usage error (exit 2), not a silent drop
if (
  cd "$REPO_ROOT" && \
  PASTURA_HARNESS_BIN="$FAKE_BIN" FAKE_ARGV_CAPTURE="$TMP/argv5.log" \
  bash .claude/skills/scenario-factory/scripts/run_scenario.sh \
    "$DUMMY_YAML" - "$TMP/out5.jsonl" 60 --bogus x >/dev/null 2>&1
); then
  fail "run_scenario: unknown trailing flag should exit non-zero"
fi

echo "ALL TESTS PASSED"
