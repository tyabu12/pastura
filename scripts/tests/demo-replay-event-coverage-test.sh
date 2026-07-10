#!/usr/bin/env bash
#
# scripts/tests/demo-replay-event-coverage-test.sh — tripwire for the
# ADR-022 §D4 (P8) demo-replay event-coverage gate
# (scripts/check_demo_replay_event_coverage.py).
#
# CI-wired: the `*-test.sh` naming convention makes this a gate under the
# .github/workflows/ci.yml "Shell gate tests" job ("Run scripts/tests/*-test.sh").
# Pure python3 + git + bash — no Xcode, no PyYAML (the synthetic converter
# fixtures define only the two sets, so importing them never runs `import yaml`).
# Run manually: bash scripts/tests/demo-replay-event-coverage-test.sh
#
# Structure mirrors the census tripwire (the gallery_census.py drift chain in
# .claude/skills/scenario-factory/tests/run_tests.sh (e), and its
# phase_types_current.swift fixture): a repo-root existence assertion, a
# synthetic-drift positive fixture, and a count-floor pin on the real file. The
# shell scaffold (tempdir + `trap rm EXIT` + `fail=0` accumulator + per-case
# subshell) follows scripts/tests/p8-precommit-gate-test.sh — note its "P8" is
# ADR-014's App Store `.p8` secret-gate, unrelated to ADR-022's projection
# site P8; only the scaffold shape is borrowed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check_demo_replay_event_coverage.py"
MAPPER="$REPO_ROOT/tools/harness/Sources/PasturaHarnessKit/EventLineMapper.swift"
CONVERTER="$REPO_ROOT/scripts/jsonl_to_demo_replay.py"

# (a) Repo-root existence assertion — a harness/SPM move or a rename fails
# loudly HERE rather than silently disabling the coverage cross-check (the
# checker's defaults would resolve to a missing path and the live check below
# would error, but an explicit assertion names the cause).
[ -f "$CHECKER" ] || { echo "FAIL: gate script missing at $CHECKER" >&2; exit 1; }
[ -f "$MAPPER" ] || {
  echo "FAIL: real EventLineMapper.swift not found at $MAPPER (harness move? update MAPPER)" >&2
  exit 1
}
[ -f "$CONVERTER" ] || {
  echo "FAIL: real jsonl_to_demo_replay.py not found at $CONVERTER" >&2
  exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

# Writes a synthetic mapper source: each argument becomes one `event: "…"`
# emit literal (plus non-matching noise, to prove the regex is specific).
mk_mapper() { # <path> <event-name>...
  local path="$1"
  shift
  {
    echo 'func map(_ event: SimulationEvent) -> EventLine? {'  # must NOT match
    local ev
    for ev in "$@"; do
      echo "    return EventLine(t: t, attempt: attempt, event: \"$ev\")"
    done
    echo '}'
  } >"$path"
}

# Writes a synthetic converter defining just the two classification sets
# (no `import yaml`, so importing it is cheap). Sets are passed as
# space-separated event lists.
mk_converter() { # <path> <handled> <ignored>
  local path="$1" handled="$2" ignored="$3"
  {
    printf 'HANDLED_EVENTS = {'
    local ev
    for ev in $handled; do printf '"%s", ' "$ev"; done
    printf '}\n'
    printf 'IGNORED_EVENTS = {'
    for ev in $ignored; do printf '"%s", ' "$ev"; done
    printf '}\n'
  } >"$path"
}

# (d) Live check — the actual drift guard. The REAL mapper's emit literals must
# all be classified in the REAL converter, and the count-floor pins against
# regex under-extraction. Bump --min-events when EventLineMapper gains an emit
# literal (currently 22).
if ! python3 "$CHECKER" --mapper "$MAPPER" --converter "$CONVERTER" --min-events 22 >/dev/null; then
  echo "FAIL: real EventLineMapper emits an event unclassified in HANDLED/IGNORED, or count < 22" >&2
  fail=1
fi

# (b) Synthetic-drift POSITIVE fixture — a `ghost_event` classified in neither
# set must make the gate exit non-zero. Without this the fail-closed claim is
# untested (the live check only ever exercises the pass path).
mk_mapper "$TMP/drift_mapper.swift" alpha beta ghost_event
mk_converter "$TMP/drift_converter.py" "alpha" "beta"
if python3 "$CHECKER" --mapper "$TMP/drift_mapper.swift" \
    --converter "$TMP/drift_converter.py" --min-events 1 >/dev/null 2>&1; then
  echo "FAIL: gate accepted an unclassified 'ghost_event' (drift not detected)" >&2
  fail=1
fi

# Negative control — the same three events, all classified, must PASS.
mk_converter "$TMP/covered_converter.py" "alpha ghost_event" "beta"
if ! python3 "$CHECKER" --mapper "$TMP/drift_mapper.swift" \
    --converter "$TMP/covered_converter.py" --min-events 1 >/dev/null 2>&1; then
  echo "FAIL: gate rejected a fully-classified fixture (false positive)" >&2
  fail=1
fi

# (c) Count-floor fixture — a fully-classified mapper with FEWER literals than
# --min-events must still fail, proving the floor catches regex under-extraction
# independently of coverage.
mk_mapper "$TMP/floor_mapper.swift" alpha beta
mk_converter "$TMP/floor_converter.py" "alpha beta" ""
if python3 "$CHECKER" --mapper "$TMP/floor_mapper.swift" \
    --converter "$TMP/floor_converter.py" --min-events 5 >/dev/null 2>&1; then
  echo "FAIL: count-floor not enforced (2 literals passed --min-events 5)" >&2
  fail=1
fi

# Overlap guard — an event in BOTH sets is a classification bug and must fail.
mk_converter "$TMP/overlap_converter.py" "alpha beta" "beta"
if python3 "$CHECKER" --mapper "$TMP/floor_mapper.swift" \
    --converter "$TMP/overlap_converter.py" --min-events 1 >/dev/null 2>&1; then
  echo "FAIL: gate accepted an event in BOTH HANDLED and IGNORED" >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "demo-replay-event-coverage: all cases passed"
else
  echo "demo-replay-event-coverage: FAILURES" >&2
  exit 1
fi
