#!/usr/bin/env bash
#
# scripts/tests/consistency-audit-test.sh — CI shim that runs the
# consistency-audit detector's self-test (#876).
#
# The skill's own harness lives at
# `.claude/skills/consistency-audit/tests/run_tests.sh`, which the CI
# "Shell gate tests" job does NOT pick up — that job globs only
# `scripts/tests/*-test.sh`. Without this shim the detector's fixtures
# (clean / drift / judgment / boundary / adr) run nowhere automatically,
# so the "zero findings on main" guarantee would have no regression guard.
# This file matches the glob and delegates, giving the harness a CI home.
#
# The harness needs python3 + jq (both present on the ubuntu-latest runner);
# it `cd`s to its own dir, so it is invocation-location independent.
#
# Run manually: bash scripts/tests/consistency-audit-test.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
bash "$REPO_ROOT/.claude/skills/consistency-audit/tests/run_tests.sh"
