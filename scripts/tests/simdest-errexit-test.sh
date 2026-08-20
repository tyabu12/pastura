#!/usr/bin/env bash
#
# scripts/tests/simdest-errexit-test.sh — regression test for #1503.
#
# THE DEFECT. `scripts/sim-dest.sh` saved the caller's shell options with
# `_simdest_old_opts=$(set +o)`. bash clears errexit inside a command
# substitution, so that snapshot recorded `set +o errexit` no matter what the
# caller had set, and restoring it DROPPED a caller's `set -e`. pipefail came
# back correctly through the same snapshot — it is not a `$-` letter flag —
# which is why only errexit went missing and the loss stayed invisible for so
# long. Mechanism: `.claude/rules/xcodebuild-cli.md` (no § anchor — that section
# is compressible, and a named one here would dangle).
#
# WHAT EACH ARM RUNS. A1, A2 and A6 source the REAL `scripts/sim-dest.sh`; A3
# and A4 run in-file fixtures. The split is forced by the runner: the CI
# "Shell gate tests" job is ubuntu with no `xcrun`, so the real script's
# SUCCESS path cannot execute there. Its FAILURE path can, and it restores
# options through the same helper, so A1/A2 still bind the real file on both
# OSes — A1 from an errexit-ON caller (must abort), A2 from an errexit-OFF one
# (must NOT be promoted to on). A5 covers the success path and SKIPS loudly
# where it cannot run; do not silence that notice.
#
# NOT COVERED. sim-dest.sh restores on four paths; the arms below reach two of
# them (the simulator-resolution failure and, on macOS, the success path). The
# `git rev-parse` guard and the wait-gate timeout are unexercised — the latter
# unreachable while every arm exports PASTURA_SKIP_SIM_WAIT=1. Read this file as
# pinning the capture, not the whole restore contract.
#
# A3 IS THE NEGATIVE CONTROL AND IS NOT OPTIONAL. It reproduces the pre-#1503
# capture and requires errexit to end up OFF. Without it, A1 and A2 would pass
# against a sim-dest.sh that never restores anything, and nothing here would
# say so. A4 is its positive twin — same harness, corrected capture — so a
# fixture harness that stopped executing anything at all cannot read as green.
# Both are fixtures on purpose: a control borrowed from the file under test
# stops discriminating the moment that file changes (#1481).
#
# CI-wired: the `*-test.sh` naming convention makes this a gate under
# .github/workflows/ci.yml ("Run scripts/tests/*-test.sh"). Run manually:
#   bash scripts/tests/simdest-errexit-test.sh

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
SIMDEST="$ROOT/scripts/sim-dest.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
bad() { printf 'FAIL: %s\n' "$*" >&2; fail=1; }
ok()  { printf '  ok: %s\n' "$*"; }

# Runs a probe script and reports its combined output plus exit status through
# two globals. `|| true` is required: several arms probe an ABORT, and this
# suite itself runs under `set -e`.
probe_out=""
probe_rc=0
run_probe() { # $1 = script path
  # The status is carried out INSIDE the substitution: `x="$(cmd)" || true`
  # would leave `$?` holding `true`'s status, and without some `|| true` this
  # suite's own `set -e` aborts on the arms that probe a deliberate failure.
  probe_out="$(/bin/bash "$1" 2>&1; printf '__RC__%s' "$?")"
  probe_rc="${probe_out##*__RC__}"
  probe_out="${probe_out%__RC__*}"
}

has() { # $1 = needle, $2 = haystack
  case "$2" in *"$1"*) return 0 ;; *) return 1 ;; esac
}

# A nonexistent device name drives the real script down its "No available iOS
# Simulator found" path on macOS. On ubuntu it lands there anyway (no `xcrun`),
# so both runners exercise the same restore-then-return-1 code.
NO_SUCH_SIM='__pastura_no_such_simulator__'

# --- A1: real script, errexit-ON caller, failure path ----------------------
cat > "$TMP/a1.sh" <<A1
export PASTURA_SKIP_SIM_WAIT=1
export PASTURA_SIM_NAME='$NO_SUCH_SIM'
set -euo pipefail
source '$SIMDEST'
echo 'A1_REACHED_AFTER_FAILED_SOURCE'
A1
run_probe "$TMP/a1.sh"
if [ "$probe_rc" != "0" ] && ! has 'A1_REACHED_AFTER_FAILED_SOURCE' "$probe_out"; then
  ok "A1 a failing plain \`source\` aborts an errexit-on caller (no \`||\` handler needed)"
else
  bad "A1 the caller survived a failing \`source\` (rc=$probe_rc). errexit was not" \
      "restored before sim-dest.sh returned 1. Output: $probe_out"
fi

# --- A2: real script, errexit-OFF caller, failure path ---------------------
cat > "$TMP/a2.sh" <<A2
export PASTURA_SKIP_SIM_WAIT=1
export PASTURA_SIM_NAME='$NO_SUCH_SIM'
set +e
source '$SIMDEST'
case "\$-" in *e*) echo 'A2_ERREXIT_ON' ;; *) echo 'A2_ERREXIT_OFF' ;; esac
A2
run_probe "$TMP/a2.sh"
if has 'A2_ERREXIT_OFF' "$probe_out"; then
  ok "A2 an errexit-off caller is not promoted to errexit-on by sourcing"
else
  bad "A2 sourcing turned errexit ON for a caller that had it off — the restore" \
      "is unconditional rather than reproducing the caller's state. Output: $probe_out"
fi

# --- A3: NEGATIVE CONTROL — the pre-#1503 capture must still lose errexit ---
cat > "$TMP/broken-lib.sh" <<'BROKEN'
_old=$(set +o)
set -euo pipefail
eval "$_old"
BROKEN
cat > "$TMP/a3.sh" <<A3
set -euo pipefail
source '$TMP/broken-lib.sh'
case "\$-" in *e*) echo 'A3_ERREXIT_ON' ;; *) echo 'A3_ERREXIT_OFF' ;; esac
A3
run_probe "$TMP/a3.sh"
if has 'A3_ERREXIT_OFF' "$probe_out"; then
  ok "A3 control: the old \`\$(set +o)\`-only capture still drops errexit, so A1/A2 discriminate"
else
  bad "A3 control did NOT lose errexit. Either this bash no longer clears errexit inside a" \
      "command substitution — in which case #1503's premise changed and every arm here is" \
      "vacuous — or the fixture stopped running. Output: $probe_out"
fi

# --- A4: positive twin of A3 — the corrected capture keeps errexit ---------
cat > "$TMP/fixed-lib.sh" <<'FIXED'
case $- in
  *e*) _had=1 ;;
  *) _had=0 ;;
esac
_old=$(set +o)
set -euo pipefail
eval "$_old"
if [ "$_had" = 1 ]; then
  set -e
fi
unset _old _had
FIXED
cat > "$TMP/a4.sh" <<A4
set -euo pipefail
source '$TMP/fixed-lib.sh'
case "\$-" in *e*) echo 'A4_ERREXIT_ON' ;; *) echo 'A4_ERREXIT_OFF' ;; esac
A4
run_probe "$TMP/a4.sh"
if has 'A4_ERREXIT_ON' "$probe_out"; then
  ok "A4 control: the corrected capture restores errexit, so A3 is measuring the capture"
else
  bad "A4 the corrected capture failed to restore errexit — the fixture harness is broken," \
      "which makes A3's 'off' result uninformative. Output: $probe_out"
fi

# --- A5: real script, SUCCESS path (needs a simulator; ubuntu CI cannot) ----
#
# The caller enters with errexit ON and pipefail OFF so that each half catches a
# different mutant. Measured against both: a no-op restore keeps pipefail ON
# (sim-dest.sh sets it for itself) and fails the pipefail half; the pre-#1503
# snapshot-only restore comes back errexit OFF and fails the errexit half. Enter
# with pipefail already ON — as this arm originally did — and the pipefail half
# passes whether or not the restore ran at all.
if command -v xcrun > /dev/null 2>&1; then
  cat > "$TMP/a5.sh" <<A5
export PASTURA_SKIP_SIM_WAIT=1
set -eu
set +o pipefail
source '$SIMDEST' > /dev/null
case "\$-" in *e*) echo 'A5_ERREXIT_ON' ;; *) echo 'A5_ERREXIT_OFF' ;; esac
pf="\$(set -o | { grep '^pipefail' || [ \$? -eq 1 ]; })"
case "\$pf" in *on*) echo 'A5_PIPEFAIL_ON' ;; *) echo 'A5_PIPEFAIL_OFF' ;; esac
A5
  run_probe "$TMP/a5.sh"
  if has 'A5_ERREXIT_ON' "$probe_out" && has 'A5_PIPEFAIL_OFF' "$probe_out"; then
    ok "A5 the success path reproduces the caller's options (errexit on, pipefail off)"
  else
    bad "A5 the success path did not reproduce the caller's options. This is the path every" \
        "local xcodebuild run takes. Output: $probe_out"
  fi
else
  printf '  SKIP: A5 (success path) needs xcrun — not present on this runner\n'
fi

# --- A6: the restore helper and its own two variables are cleaned up --------
#
# Scoped to what #1503 introduced, NOT to "sim-dest.sh leaks nothing". It does
# leak: the early-return path measured here leaves `_simdest_errfile`,
# `_simdest_result` and `SIMULATOR_NAMES` set, because only the success path's
# `unset` lines clear them. Pre-existing and out of this fix's scope — named
# here so the arm cannot be read as certifying it away.
#
# Enumerate that residual with `${x+SET}` or a `set` name diff, never `${x:-}`:
# `_simdest_result` is set-but-EMPTY on this path, so a `:-` probe reports it
# absent and the list comes back one short (it did, the first time).
cat > "$TMP/a6.sh" <<A6
export PASTURA_SKIP_SIM_WAIT=1
export PASTURA_SIM_NAME='$NO_SUCH_SIM'
set +e
source '$SIMDEST'
for v in _simdest_old_opts _simdest_had_errexit; do
  eval "val=\\\${\$v:-}"
  if [ -n "\$val" ]; then echo "A6_LEAKED_\$v"; fi
done
if type _simdest_restore_opts > /dev/null 2>&1; then echo 'A6_LEAKED_restore_fn'; fi
echo 'A6_DONE'
A6
run_probe "$TMP/a6.sh"
if has 'A6_DONE' "$probe_out" && ! has 'A6_LEAKED' "$probe_out"; then
  ok "A6 the restore helper and its two state variables are unset before returning"
else
  bad "A6 the restore helper or one of its two state variables survived into the caller's" \
      "shell. Output: $probe_out"
fi

if [ "$fail" -ne 0 ]; then
  printf '\nsimdest-errexit-test.sh: FAILED\n' >&2
  exit 1
fi
printf '\nsimdest-errexit-test.sh: all arms passed\n'
