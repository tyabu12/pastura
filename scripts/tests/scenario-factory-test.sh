#!/usr/bin/env bash
#
# scripts/tests/scenario-factory-test.sh — CI shim that runs the
# scenario-factory skill's helper self-test (#891).
#
# The skill's own harness lives at
# `.claude/skills/scenario-factory/tests/run_tests.sh`, which the CI "Shell
# gate tests" job does NOT pick up — that job globs only `scripts/tests/*-test.sh`.
# Without this shim the harness (run_scenario.sh --classify, format_transcript.py,
# append_digest.py, gallery_census.py against fixtures) runs nowhere
# automatically. This file matches the glob and delegates, giving the harness a
# CI home.
#
# The harness needs python3 + jq (both on the ubuntu-latest runner); it `cd`s to
# its own dir, so it is invocation-location independent.
#
# The skill-harness-wiring completeness gate enforces that this shim exists and
# delegates — see scripts/tests/skill-harness-wiring-test.sh.
#
# Run manually: bash scripts/tests/scenario-factory-test.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
bash "$REPO_ROOT/.claude/skills/scenario-factory/tests/run_tests.sh"
