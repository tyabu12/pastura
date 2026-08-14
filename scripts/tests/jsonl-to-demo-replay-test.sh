#!/usr/bin/env bash
#
# scripts/tests/jsonl-to-demo-replay-test.sh — runtime arms for
# scripts/jsonl_to_demo_replay.py.
#
# Distinct from demo-replay-event-coverage-test.sh, which only *locates* the
# converter as a fixture path for the ADR-022 §D4 coverage gate and never
# executes it. This file executes it.
#
# Today it covers one thing: `phase_index` is derived from the transcript's
# `phase_started.phase_path[0]` and a missing `phase_path` is refused rather
# than defaulted to 0 (#1474 — the same invention was removed from
# gallery_highlight_extract.annotate, whose arm is C4 in
# gallery-highlight-test.sh). A guard with no arm is silently unverified, and
# this one is otherwise unreachable from any in-repo test.
#
# CI-wired via the `scripts/tests/*-test.sh` naming convention (the
# `shell-tests` job, ubuntu / bash 5+). The converter imports PyYAML at module
# level, which that job pre-installs. Also runs under macOS /bin/bash 3.2.
set -euo pipefail

command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 missing" >&2; exit 1; }
python3 -c "import yaml" 2>/dev/null || {
  echo "ERROR: PyYAML not available — 'python3 -m pip install pyyaml'" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONVERTER="$REPO_ROOT/scripts/jsonl_to_demo_replay.py"
[ -f "$CONVERTER" ] || {
  echo "FAIL: converter missing at $CONVERTER (renamed? update CONVERTER)" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

# `id` is the only key the converter requires of the preset; everything else it
# reads through `.get()`. Keeping the fixture minimal is deliberate — an arm
# that borrowed a real gallery YAML would redden when that scenario is edited.
cat > "$TMP/preset.yaml" <<'YAML'
id: fixture_v1
name: Fixture
description: fixture preset
YAML

# `phase_path` is [2], NOT [0]: the removed fallback invented 0, so a fixture
# sitting at 0 could not tell derivation from invention.
cat > "$TMP/run.jsonl" <<'JSONL'
{"type":"run_start","run_id":"r1","date":"2026-08-14T00:00:00Z","scenario_id":"fixture_v1","language":"ja","model":"Gemma 4 E2B (Q4_K_M)"}
{"type":"event","t":0.1,"attempt":1,"event":"round_started","round":1,"total_rounds":1}
{"type":"event","t":0.2,"attempt":1,"event":"phase_started","phase_type":"speak_all","phase_path":[2]}
{"type":"event","t":0.3,"attempt":1,"event":"agent_output","agent":"アヤ","phase_type":"speak_all","fields":{"statement":"ひとこと。"}}
{"type":"run_end","run_id":"r1","status":"ok","attempts":1,"duration_sec":1.0}
JSONL
# `run_end` is a LIFECYCLE line (`type: run_end`), not an event — the converter's
# `type != "event"` filter skips it before the ADR-022 §D4 unknown-event guard.
# Writing it as `type: event` (as gallery-highlight-test.sh's mk_run does, where
# no such guard exists) makes this fixture fail for a reason the arm is not about.

# (a) Positive — converts, and the turn carries the index the transcript stated.
if python3 "$CONVERTER" "$TMP/run.jsonl" "$TMP/preset.yaml" "$TMP/out.yaml" >/dev/null 2>&1; then
  got="$(python3 -c "
import yaml, sys
d = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))
print(','.join(str(t['phase_index']) for t in d['turns']))" "$TMP/out.yaml")"
  if [ "$got" = "2" ]; then
    echo "ok   (a) phase_index derived from phase_path"
  else
    echo "FAIL: (a) expected phase_index '2', got '$got'" >&2; fail=1
  fi
else
  echo "FAIL: (a) converter rejected a well-formed transcript" >&2; fail=1
fi

# (b) Negative — a `phase_started` with no `phase_path` is refused. The anchor
# assertion is what stops a silently-no-op edit from reading as a pass here.
python3 - "$TMP" <<'PY'
import sys
p = sys.argv[1] + "/run.jsonl"
text = open(p, encoding="utf-8").read()
old = ',"phase_path":[2]'
assert text.count(old) == 1, f"anchor matched {text.count(old)} times — probe invalid"
open(sys.argv[1] + "/nopath.jsonl", "w", encoding="utf-8").write(text.replace(old, ""))
PY
set +e
out="$(python3 "$CONVERTER" "$TMP/nopath.jsonl" "$TMP/preset.yaml" "$TMP/out2.yaml" 2>&1)"
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
  echo "FAIL: (b) a missing phase_path was accepted (rc=0): $out" >&2; fail=1
else
  case "$out" in
    *"no usable \`phase_path\`"*)
      echo "ok   (b) a missing phase_path is refused by name" ;;
    *)
      # A NameError or a TypeError also exits non-zero, so rc alone cannot tell
      # "refused" from "crashed" — the first cut of this guard referenced two
      # out-of-scope identifiers and would have failed exactly that way.
      echo "FAIL: (b) refused, but not with the intended message: $out" >&2; fail=1 ;;
  esac
fi
# Spelled as an `if` rather than `[ … ] && { … }`: under `set -e` the latter's
# status when the test is false is a subtlety this file should not lean on.
if [ -e "$TMP/out2.yaml" ]; then
  echo "FAIL: (b) wrote an output despite refusing" >&2; fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "jsonl-to-demo-replay-test: all arms passed"
else
  echo "jsonl-to-demo-replay-test: FAILED" >&2
fi
exit "$fail"
