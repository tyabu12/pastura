#!/usr/bin/env bash
#
# scripts/tests/jsonl-to-demo-replay-test.sh — runtime arms for
# scripts/jsonl_to_demo_replay.py.
#
# Distinct from demo-replay-event-coverage-test.sh, which only *locates* the
# converter as a fixture path for the ADR-022 §D4 coverage gate and never
# executes it. This file executes it.
#
# Two things today:
#   - `phase_index` derivation and its refusals (#1474 — the same invention was
#     removed from gallery_highlight_extract.annotate, whose arm is C4 in
#     gallery-highlight-test.sh);
#   - `branch` resolution for a `conditional`'s sub-phases (#1505), including
#     each of its five refusals — an unarmed refusal is what this header's own
#     rule below forbids, and three of them were unarmed when first written.
# A guard with no arm is silently unverified, and both are otherwise unreachable
# from any in-repo test. The `branch` arms matter more than they look: NO shipped
# demo has a conditional, so the Swift-side alignment gate cannot reach that
# resolver either — this file is the only place it executes at all.
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
# An `if`, not `[ … ] && { … }` — under `set -e` the latter's false-test status
# is a subtlety this file should not lean on.
if [ -e "$TMP/out2.yaml" ]; then
  echo "FAIL: (b) wrote an output despite refusing" >&2; fail=1
fi

# (c) Negative — an event BEFORE the first `phase_started` is refused too. The
# missing-`phase_path` guard (b) covers only one of the two ways the index can
# be absent; the other was the `phase_idx = 0` initializer, which invented the
# same index the guard exists to stop.
cat > "$TMP/early.jsonl" <<'JSONL'
{"type":"run_start","run_id":"r1","date":"2026-08-14T00:00:00Z","scenario_id":"fixture_v1","language":"ja","model":"Gemma 4 E2B (Q4_K_M)"}
{"type":"event","t":0.1,"attempt":1,"event":"round_started","round":1,"total_rounds":1}
{"type":"event","t":0.2,"attempt":1,"event":"agent_output","agent":"アヤ","phase_type":"speak_all","fields":{"statement":"ひとこと。"}}
{"type":"run_end","run_id":"r1","status":"ok","attempts":1,"duration_sec":1.0}
JSONL
set +e
out_c="$(python3 "$CONVERTER" "$TMP/early.jsonl" "$TMP/preset.yaml" "$TMP/out3.yaml" 2>&1)"
rc_c=$?
set -e
if [ "$rc_c" -eq 0 ]; then
  echo "FAIL: (c) an event before the first phase_started was accepted: $out_c" >&2; fail=1
else
  case "$out_c" in
    *"precedes the first"*)
      echo "ok   (c) an event before the first phase_started is refused by name" ;;
    *)
      echo "FAIL: (c) refused, but not with the intended message: $out_c" >&2; fail=1 ;;
  esac
fi

# ---------------------------------------------------------------------------
# `branch` resolution (#1505). `then[j]` and `else[j]` carry the IDENTICAL
# `phase_path`, so the two arms below differ only in the `conditional_evaluated`
# verdict — anything that read the branch off the path instead would return the
# same answer for both and pass one of them by luck.

# $1 = result literal (true/false), $2 = output filename
write_branch_run() {
  cat > "$TMP/$2.jsonl" <<JSONL
{"type":"run_start","run_id":"r1","date":"2026-08-14T00:00:00Z","scenario_id":"fixture_v1","language":"ja","model":"Gemma 4 E2B (Q4_K_M)"}
{"type":"event","t":0.1,"attempt":1,"event":"round_started","round":1,"total_rounds":1}
{"type":"event","t":0.2,"attempt":1,"event":"phase_started","phase_type":"conditional","phase_path":[1]}
{"type":"event","t":0.3,"attempt":1,"event":"conditional_evaluated","condition":"x > 0","result":$1}
{"type":"event","t":0.4,"attempt":1,"event":"phase_started","phase_type":"speak_all","phase_path":[1,0]}
{"type":"event","t":0.5,"attempt":1,"event":"agent_output","agent":"アヤ","phase_type":"speak_all","fields":{"statement":"ひとこと。"}}
{"type":"run_end","run_id":"r1","status":"ok","attempts":1,"duration_sec":1.0}
JSONL
}

read_coords() {
  python3 -c "
import yaml, sys
d = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))
t = d['turns'][0]
print('%s|%s|%s|%s' % (d['schema_version'], t['phase_index'],
                       t['phase_path'], t.get('branch')))" "$1"
}

# (d) then-branch
write_branch_run true then
if python3 "$CONVERTER" "$TMP/then.jsonl" "$TMP/preset.yaml" "$TMP/out_then.yaml" >/dev/null 2>&1; then
  got_d="$(read_coords "$TMP/out_then.yaml")"
  if [ "$got_d" = "2|1|[1, 0]|then" ]; then
    echo "ok   (d) then-branch: v2 + phase_path [1, 0] + branch then"
  else
    echo "FAIL: (d) expected '2|1|[1, 0]|then', got '$got_d'" >&2; fail=1
  fi
else
  echo "FAIL: (d) converter rejected a well-formed conditional transcript" >&2; fail=1
fi

# (e) else-branch — same path, opposite verdict.
write_branch_run false else
if python3 "$CONVERTER" "$TMP/else.jsonl" "$TMP/preset.yaml" "$TMP/out_else.yaml" >/dev/null 2>&1; then
  got_e="$(read_coords "$TMP/out_else.yaml")"
  if [ "$got_e" = "2|1|[1, 0]|else" ]; then
    echo "ok   (e) else-branch resolves from the verdict, not the path"
  else
    echo "FAIL: (e) expected '2|1|[1, 0]|else', got '$got_e'" >&2; fail=1
  fi
else
  echo "FAIL: (e) converter rejected a well-formed conditional transcript" >&2; fail=1
fi

# (f) Negative — a branch `phase_started` with no preceding verdict is refused
# rather than guessed. Built by DELETING the verdict line from (d)'s fixture, so
# the arm cannot drift away from the positive it is the control for.
python3 - "$TMP" <<'PY'
import sys
src = sys.argv[1] + "/then.jsonl"
kept = [ln for ln in open(src, encoding="utf-8") if '"conditional_evaluated"' not in ln]
assert len(kept) == 6, f"expected to drop exactly 1 of 7 lines, kept {len(kept)} — probe invalid"
open(sys.argv[1] + "/noverdict.jsonl", "w", encoding="utf-8").writelines(kept)
PY
set +e
out_f="$(python3 "$CONVERTER" "$TMP/noverdict.jsonl" "$TMP/preset.yaml" "$TMP/out_f.yaml" 2>&1)"
rc_f=$?
set -e
if [ "$rc_f" -eq 0 ]; then
  echo "FAIL: (f) a branch phase with no verdict was accepted: $out_f" >&2; fail=1
else
  case "$out_f" in
    *"is inside a branch, but no"*)
      echo "ok   (f) an unattributed branch is refused by name" ;;
    *)
      echo "FAIL: (f) refused, but not with the intended message: $out_f" >&2; fail=1 ;;
  esac
fi
if [ -e "$TMP/out_f.yaml" ]; then
  echo "FAIL: (f) wrote an output despite refusing" >&2; fail=1
fi

# (g) Negative — a non-boolean verdict is refused. `result` decides then-vs-else
# by truthiness, so a string would silently resolve every non-empty value to
# `then`; that is a wrong branch recorded as measured fact, not a crash.
python3 - "$TMP" <<'PY'
import sys
src = sys.argv[1] + "/then.jsonl"
text = open(src, encoding="utf-8").read()
old = '"result":true'
assert text.count(old) == 1, f"anchor matched {text.count(old)} times — probe invalid"
open(sys.argv[1] + "/badresult.jsonl", "w", encoding="utf-8").write(
    text.replace(old, '"result":"true"'))
PY
set +e
out_g="$(python3 "$CONVERTER" "$TMP/badresult.jsonl" "$TMP/preset.yaml" "$TMP/out_g.yaml" 2>&1)"
rc_g=$?
set -e
if [ "$rc_g" -eq 0 ]; then
  echo "FAIL: (g) a non-boolean conditional result was accepted: $out_g" >&2; fail=1
else
  case "$out_g" in
    *"not a boolean"*)
      echo "ok   (g) a non-boolean conditional result is refused by name" ;;
    *)
      echo "FAIL: (g) refused, but not with the intended message: $out_g" >&2; fail=1 ;;
  esac
fi
if [ -e "$TMP/out_g.yaml" ]; then
  echo "FAIL: (g) wrote an output despite refusing" >&2; fail=1
fi

# (h) A top-level phase clears the branch — otherwise a later top-level turn
# would inherit the verdict of a conditional that already closed.
cat > "$TMP/clears.jsonl" <<'JSONL'
{"type":"run_start","run_id":"r1","date":"2026-08-14T00:00:00Z","scenario_id":"fixture_v1","language":"ja","model":"Gemma 4 E2B (Q4_K_M)"}
{"type":"event","t":0.1,"attempt":1,"event":"round_started","round":1,"total_rounds":1}
{"type":"event","t":0.2,"attempt":1,"event":"phase_started","phase_type":"conditional","phase_path":[1]}
{"type":"event","t":0.3,"attempt":1,"event":"conditional_evaluated","condition":"x > 0","result":true}
{"type":"event","t":0.4,"attempt":1,"event":"phase_started","phase_type":"speak_all","phase_path":[1,0]}
{"type":"event","t":0.5,"attempt":1,"event":"agent_output","agent":"アヤ","phase_type":"speak_all","fields":{"statement":"branch."}}
{"type":"event","t":0.6,"attempt":1,"event":"phase_started","phase_type":"vote","phase_path":[2]}
{"type":"event","t":0.7,"attempt":1,"event":"agent_output","agent":"アヤ","phase_type":"vote","fields":{"vote":"ボブ"}}
{"type":"run_end","run_id":"r1","status":"ok","attempts":1,"duration_sec":1.0}
JSONL
if python3 "$CONVERTER" "$TMP/clears.jsonl" "$TMP/preset.yaml" "$TMP/out_h.yaml" >/dev/null 2>&1; then
  got_h="$(python3 -c "
import yaml, sys
d = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))
print(';'.join('%s/%s' % (t['phase_path'], t.get('branch')) for t in d['turns']))" \
    "$TMP/out_h.yaml")"
  if [ "$got_h" = "[1, 0]/then;[2]/None" ]; then
    echo "ok   (h) a top-level phase clears the pending branch"
  else
    echo "FAIL: (h) expected '[1, 0]/then;[2]/None', got '$got_h'" >&2; fail=1
  fi
else
  echo "FAIL: (h) converter rejected a well-formed mixed transcript" >&2; fail=1
fi

# (i) Negative — a verdict with no conditional in flight. Distinct from (f):
# there the branch phase had no verdict, here the verdict has no phase to
# attribute it to, and only this arm reaches that refusal.
python3 - "$TMP" <<'PY'
import sys
src = sys.argv[1] + "/then.jsonl"
text = open(src, encoding="utf-8").read()
old = '"phase_type":"conditional","phase_path":[1]'
assert text.count(old) == 1, f"anchor matched {text.count(old)} times — probe invalid"
# Retype the opening phase so no conditional is ever in flight; the verdict
# line that follows is then unattributable.
open(sys.argv[1] + "/orphanverdict.jsonl", "w", encoding="utf-8").write(
    text.replace(old, '"phase_type":"speak_all","phase_path":[1]'))
PY
set +e
out_i="$(python3 "$CONVERTER" "$TMP/orphanverdict.jsonl" "$TMP/preset.yaml" "$TMP/out_i.yaml" 2>&1)"
rc_i=$?
set -e
if [ "$rc_i" -eq 0 ]; then
  echo "FAIL: (i) an orphan conditional_evaluated was accepted: $out_i" >&2; fail=1
else
  case "$out_i" in
    *"has no preceding"*)
      echo "ok   (i) an orphan conditional_evaluated is refused by name" ;;
    *)
      echo "FAIL: (i) refused, but not with the intended message: $out_i" >&2; fail=1 ;;
  esac
fi

# (j) Negative — a bool element in `phase_path`. `isinstance(True, int)` is True
# in Python, so this guard is the only thing between `[true, 0]` and a demo
# naming phase 1; every other check downstream would see a well-formed int.
python3 - "$TMP" <<'PY'
import sys
src = sys.argv[1] + "/then.jsonl"
text = open(src, encoding="utf-8").read()
old = '"phase_path":[1,0]'
assert text.count(old) == 1, f"anchor matched {text.count(old)} times — probe invalid"
open(sys.argv[1] + "/boolpath.jsonl", "w", encoding="utf-8").write(
    text.replace(old, '"phase_path":[true,0]'))
PY
set +e
out_j="$(python3 "$CONVERTER" "$TMP/boolpath.jsonl" "$TMP/preset.yaml" "$TMP/out_j.yaml" 2>&1)"
rc_j=$?
set -e
if [ "$rc_j" -eq 0 ]; then
  echo "FAIL: (j) a bool phase_path element was accepted: $out_j" >&2; fail=1
else
  case "$out_j" in
    *"a bool"*)
      echo "ok   (j) a bool phase_path element is refused by name" ;;
    *)
      echo "FAIL: (j) refused, but not with the intended message: $out_j" >&2; fail=1 ;;
  esac
fi

# (k) Negative — a path deeper than the engine's depth-1 rule allows.
python3 - "$TMP" <<'PY'
import sys
src = sys.argv[1] + "/then.jsonl"
text = open(src, encoding="utf-8").read()
old = '"phase_path":[1,0]'
assert text.count(old) == 1, f"anchor matched {text.count(old)} times — probe invalid"
open(sys.argv[1] + "/deeppath.jsonl", "w", encoding="utf-8").write(
    text.replace(old, '"phase_path":[1,0,0]'))
PY
set +e
out_k="$(python3 "$CONVERTER" "$TMP/deeppath.jsonl" "$TMP/preset.yaml" "$TMP/out_k.yaml" 2>&1)"
rc_k=$?
set -e
if [ "$rc_k" -eq 0 ]; then
  echo "FAIL: (k) an over-deep phase_path was accepted: $out_k" >&2; fail=1
else
  case "$out_k" in
    *"deep, but the engine's"*)
      echo "ok   (k) an over-deep phase_path is refused by name" ;;
    *)
      echo "FAIL: (k) refused, but not with the intended message: $out_k" >&2; fail=1 ;;
  esac
fi

# (l) The hazard arm (h)'s comment actually names is MULTI-round: round 2's
# branch must NOT inherit round 1's verdict. (h) shows the clear happens; only
# this shows what the clear buys — round 2 has no verdict of its own, so the
# branch phase must be refused rather than resolved against round 1's.
cat > "$TMP/tworound.jsonl" <<'JSONL'
{"type":"run_start","run_id":"r1","date":"2026-08-14T00:00:00Z","scenario_id":"fixture_v1","language":"ja","model":"Gemma 4 E2B (Q4_K_M)"}
{"type":"event","t":0.1,"attempt":1,"event":"round_started","round":1,"total_rounds":2}
{"type":"event","t":0.2,"attempt":1,"event":"phase_started","phase_type":"conditional","phase_path":[1]}
{"type":"event","t":0.3,"attempt":1,"event":"conditional_evaluated","condition":"x > 0","result":true}
{"type":"event","t":0.4,"attempt":1,"event":"phase_started","phase_type":"speak_all","phase_path":[1,0]}
{"type":"event","t":0.5,"attempt":1,"event":"agent_output","agent":"アヤ","phase_type":"speak_all","fields":{"statement":"r1."}}
{"type":"event","t":0.6,"attempt":1,"event":"round_started","round":2,"total_rounds":2}
{"type":"event","t":0.7,"attempt":1,"event":"phase_started","phase_type":"conditional","phase_path":[1]}
{"type":"event","t":0.8,"attempt":1,"event":"phase_started","phase_type":"speak_all","phase_path":[1,0]}
{"type":"event","t":0.9,"attempt":1,"event":"agent_output","agent":"アヤ","phase_type":"speak_all","fields":{"statement":"r2."}}
{"type":"run_end","run_id":"r1","status":"ok","attempts":1,"duration_sec":1.0}
JSONL
set +e
out_l="$(python3 "$CONVERTER" "$TMP/tworound.jsonl" "$TMP/preset.yaml" "$TMP/out_l.yaml" 2>&1)"
rc_l=$?
set -e
if [ "$rc_l" -eq 0 ]; then
  echo "FAIL: (l) round 2 inherited round 1's verdict instead of refusing" >&2; fail=1
else
  case "$out_l" in
    *"is inside a branch, but no"*)
      echo "ok   (l) a later round does not inherit an earlier verdict" ;;
    *)
      echo "FAIL: (l) refused, but not with the intended message: $out_l" >&2; fail=1 ;;
  esac
fi

if [ "$fail" -eq 0 ]; then
  echo "jsonl-to-demo-replay-test: all arms passed"
else
  echo "jsonl-to-demo-replay-test: FAILED" >&2
fi
exit "$fail"
