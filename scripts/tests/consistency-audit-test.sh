#!/usr/bin/env bash
#
# scripts/tests/consistency-audit-test.sh — CI shim that runs the
# consistency-audit detector's self-test (#876).
#
# The skill's own harness lives at
# `.claude/skills/consistency-audit/tests/run_tests.sh`, which the CI
# "Shell gate tests" job does NOT pick up — that job globs only
# `scripts/tests/*-test.sh`. Without this shim the detector's fixtures run
# nowhere automatically, so every detector's must-NOT-fire set would have no
# regression guard. (Fixtures are enumerated in the harness itself rather than
# here, so the list cannot go stale from this end.)
#
# The harness asserts fixture behaviour only — never the live repo. `main` is
# not a zero-findings invariant since adr_navigation_missing landed, and even
# where a live assertion looks stable it would redden unrelated PRs: this job
# has no path filter, so an ordinary docs edit that shifts an ADR's line count
# would fail the consistency-audit gate.
# This file matches the glob and delegates, giving the harness a CI home.
#
# The harness needs python3 + jq (both present on the ubuntu-latest runner);
# it `cd`s to its own dir, so it is invocation-location independent.
#
# Run manually: bash scripts/tests/consistency-audit-test.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
bash "$REPO_ROOT/.claude/skills/consistency-audit/tests/run_tests.sh"
