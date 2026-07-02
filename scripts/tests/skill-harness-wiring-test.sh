#!/usr/bin/env bash
#
# scripts/tests/skill-harness-wiring-test.sh — completeness gate (#891).
#
# Every skill-local self-test harness at `.claude/skills/<skill>/tests/run_tests.sh`
# MUST have a CI shim at `scripts/tests/<skill>-test.sh` that actually delegates
# to it. The CI "Shell gate tests" job runs `scripts/tests/*-test.sh` only, so a
# harness without a shim runs NOWHERE — silent zero coverage (the #888 / #891
# gap). This gate fails the Shell-gate job when any harness is un-wired, turning
# a silent miss into a red build.
#
# It checks the harness -> shim direction only, so genuine unit tests
# (gallery-scripts-test.sh, block-force-push-test.sh, and this gate itself) are
# never mistaken for shims. bash-3.2-clean (the local pre-push run uses macOS
# /bin/bash 3.2; CI is ubuntu bash 5).
#
# Run manually: bash scripts/tests/skill-harness-wiring-test.sh
set -euo pipefail

# scan <root>: for each skill harness under <root>, require a delegating shim.
# Prints one "gap:" line per problem to stderr; returns 1 if any gap, else 0.
# The delegation check anchors on a LIVE `bash ... run_tests.sh` invocation
# line, not a bare path mention — a shim that only names the harness in a header
# comment (with its real delegation commented-out) would otherwise pass here
# while silently exiting 0 under CI. `[ -e ] || continue` guards the glob's
# literal-string fallback when zero harnesses match.
scan() {
  local root="$1" rc=0 harness skill shim
  for harness in "$root"/.claude/skills/*/tests/run_tests.sh; do
    [ -e "$harness" ] || continue
    skill=$(basename "$(dirname "$(dirname "$harness")")")
    shim="$root/scripts/tests/${skill}-test.sh"
    if [ ! -f "$shim" ]; then
      echo "  gap: skill '$skill' harness has no CI shim at scripts/tests/${skill}-test.sh" >&2
      rc=1
      continue
    fi
    # The `bash` prefix is deliberate — every shim delegates via a plain
    # `bash …/run_tests.sh` line. A future author switching to `exec bash …`
    # or `"$BASH" …` would be flagged as a gap; keep the plain form or widen
    # this regex intentionally.
    if ! grep -Eq "^[[:space:]]*bash[^#]*${skill}/tests/run_tests\.sh" "$shim"; then
      echo "  gap: scripts/tests/${skill}-test.sh has no live 'bash …/${skill}/tests/run_tests.sh' delegation line" >&2
      rc=1
    fi
  done
  return "$rc"
}

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- self-test: the gate's own logic is the one thing nothing else covers ----
# Scaffold a throwaway tree and assert scan() fires exactly when it should.
SELFTEST=$(mktemp -d)
trap 'rm -rf "$SELFTEST"' EXIT
mkdir -p "$SELFTEST/.claude/skills/demo/tests" "$SELFTEST/scripts/tests"
: > "$SELFTEST/.claude/skills/demo/tests/run_tests.sh"

# (a) a correctly-wired shim with a live delegation line -> scan passes
printf '#!/usr/bin/env bash\nbash "$REPO/.claude/skills/demo/tests/run_tests.sh"\n' \
  > "$SELFTEST/scripts/tests/demo-test.sh"
scan "$SELFTEST" || fail "self-test (a): a live-delegating shim must pass"

# (b) delegation only in a comment -> scan must flag it
printf '#!/usr/bin/env bash\n# bash .claude/skills/demo/tests/run_tests.sh (documented, not run)\ntrue\n' \
  > "$SELFTEST/scripts/tests/demo-test.sh"
if scan "$SELFTEST" 2>/dev/null; then fail "self-test (b): a comment-only shim must be flagged"; fi

# (c) no shim at all -> scan must flag it
rm -f "$SELFTEST/scripts/tests/demo-test.sh"
if scan "$SELFTEST" 2>/dev/null; then fail "self-test (c): a missing shim must be flagged"; fi

rm -rf "$SELFTEST"
trap - EXIT

# --- real check: the live repo tree ------------------------------------------
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
scan "$REPO_ROOT" || fail "one or more skill harnesses are not wired into CI (add the shim(s) above)"

echo "ALL TESTS PASSED"
