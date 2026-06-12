#!/bin/bash
# Crash-tolerant single-scenario runner for the /scenario-factory skill.
#
# usage:
#   run_scenario.sh <scenario.yaml> <model.gguf> <out.jsonl> [timeout_sec]
#   run_scenario.sh --classify <out.jsonl> <exit_code>
#
# Run from the repository root (Package.swift must be in the cwd).
# Emits exactly one JSON status line on stdout. Harness stderr goes to
# `<out-minus-.jsonl>.stderr.log` — llama.cpp parser-internal errors only
# surface there, not in the JSONL (see #253 diagnostics).
#
# Status contract, pinned to the real harness behavior
# (tools/harness/Sources/pastura-harness/Main.swift, issue #521):
#
#   config_error  harness exit 2 (CLI / YAML-load / model-path error — no
#                 run JSONL is written), swift build failure, or
#                 run_start.estimated_inferences > 100 (run killed early
#                 instead of burning a full model-load cycle)
#   failed        any other non-zero exit — #253 SIGABRT arrives as 134
#                 (128+SIGABRT) — OR run_end line absent / truncated OR
#                 run_end.status != "ok"
#   ok            exit 0 AND run_end.status == "ok"
#
# This script exits 0 even when the run fails (the status line carries the
# result) — one bad scenario must never abort the nightly batch. Usage
# errors exit 2.
#
# --classify reruns only the classification against an existing JSONL +
# exit code; used by tests/run_tests.sh (no Swift toolchain, no model).

set -u

HARD_BLOCK=100          # ScenarioValidator hard limit (est. inferences)
RUN_START_WAIT_SEC=90   # run_start poll budget; build is done beforehand

usage() {
  cat >&2 <<'EOF'
usage: run_scenario.sh <scenario.yaml> <model.gguf> <out.jsonl> [timeout_sec]
       run_scenario.sh --classify <out.jsonl> <exit_code>
EOF
  exit 2
}

# Prints the last parseable run_end line (compact JSON), or nothing.
# `fromjson?` skips unparseable lines, so a truncated final line from a
# mid-write crash cannot break the scan.
last_run_end() {
  [ -f "$1" ] || return 0
  jq -Rc 'fromjson? | select(.type == "run_end")' "$1" 2>/dev/null | tail -1
}

# Prints run_start.estimated_inferences, or nothing.
run_start_estimate() {
  [ -f "$1" ] || return 0
  jq -Rr 'fromjson? | select(.type == "run_start") | .estimated_inferences' \
    "$1" 2>/dev/null | head -1
}

# emit <status> <exit_code> <scenario> <out> <run_end_json> <est> <error>
emit() {
  jq -cn \
    --arg status "$1" \
    --argjson exit_code "$2" \
    --arg scenario "$3" \
    --arg out "$4" \
    --argjson run_end "${5:-null}" \
    --argjson estimated_inferences "${6:-null}" \
    --arg error "${7:-}" \
    '{status: $status, exit_code: $exit_code, scenario: $scenario, out: $out,
      run_end: $run_end, estimated_inferences: $estimated_inferences,
      error: (if $error == "" then null else $error end)}'
}

# classify <out.jsonl> <exit_code> <scenario> [error]
classify() {
  local out=$1 exit_code=$2 scenario=$3 err=${4:-}
  local run_end est status
  run_end=$(last_run_end "$out")
  est=$(run_start_estimate "$out")

  if [ "$exit_code" -eq 2 ]; then
    status="config_error"
  elif [ -n "$est" ] && [ "$est" -gt "$HARD_BLOCK" ]; then
    status="config_error"
    err=${err:-"estimated_inferences ($est) exceeds hard block ($HARD_BLOCK)"}
  elif [ "$exit_code" -ne 0 ] || [ -z "$run_end" ]; then
    status="failed"
    if [ -z "$run_end" ]; then
      err=${err:-"run_end line missing — process died mid-run (#253)"}
    fi
  elif [ "$(printf '%s' "$run_end" | jq -r '.status')" = "ok" ]; then
    status="ok"
  else
    status="failed"
  fi

  emit "$status" "$exit_code" "$scenario" "$out" \
    "${run_end:-null}" "${est:-null}" "$err"
}

command -v jq >/dev/null 2>&1 || { echo "jq is required (brew install jq)" >&2; exit 2; }

if [ "${1:-}" = "--classify" ]; then
  [ $# -eq 3 ] || usage
  case "$3" in *[!0-9]*) usage ;; esac
  classify "$2" "$3" "(classify-only)"
  exit 0
fi

[ $# -ge 3 ] && [ $# -le 4 ] || usage
SCENARIO=$1
MODEL=$2
OUT=$3
TIMEOUT=${4:-600}
[ -f Package.swift ] || { echo "run from the repository root (Package.swift not found)" >&2; exit 2; }

mkdir -p "$(dirname "$OUT")"
STDERR_LOG="${OUT%.jsonl}.stderr.log"

# Build first so the run_start poll below measures the harness, not the
# compiler. A build failure is an environment problem, not a run failure.
if ! BUILD_OUT=$(swift build 2>&1); then
  emit "config_error" 1 "$SCENARIO" "$OUT" null null \
    "swift build failed: $(printf '%s' "$BUILD_OUT" | tail -3 | tr '\n' ' ')"
  exit 0
fi
BIN="$(swift build --show-bin-path)/pastura-harness"
if [ ! -x "$BIN" ]; then
  # Guard against bin-path/config drift — a missing binary must read as an
  # environment problem, not get misattributed to a #253 crash.
  emit "config_error" 1 "$SCENARIO" "$OUT" null null \
    "harness binary not found at $BIN (build/config drift?)"
  exit 0
fi

"$BIN" --scenario "$SCENARIO" --model "$MODEL" --out "$OUT" \
  --timeout "$TIMEOUT" --quiet 2>"$STDERR_LOG" &
PID=$!

# Fast-abort: run_start (with the inference estimate) is written before
# model load, so an oversized generated scenario can be killed in seconds
# instead of after a full run.
OVERSIZE=""
for _ in $(seq 1 "$RUN_START_WAIT_SEC"); do
  kill -0 "$PID" 2>/dev/null || break
  EST=$(run_start_estimate "$OUT")
  if [ -n "$EST" ]; then
    if [ "$EST" -gt "$HARD_BLOCK" ]; then
      OVERSIZE=1
      kill "$PID" 2>/dev/null
    fi
    break
  fi
  sleep 1
done

wait "$PID"
EXIT_CODE=$?

# Ordering invariant: this OVERSIZE branch MUST precede classify — it
# overrides the SIGTERM exit code (143) from our own fast-abort kill,
# which classify would otherwise mislabel as a failed run.
if [ -n "$OVERSIZE" ]; then
  EST=$(run_start_estimate "$OUT")
  emit "config_error" "$EXIT_CODE" "$SCENARIO" "$OUT" null "${EST:-null}" \
    "estimated_inferences ($EST) exceeds hard block ($HARD_BLOCK) — killed before run"
  exit 0
fi

classify "$OUT" "$EXIT_CODE" "$SCENARIO"
