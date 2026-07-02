#!/usr/bin/env bash
#
# scripts/tests/scenario-refine-test.sh — CI shim that runs the scenario-refine
# skill's helper self-test (#891).
#
# The skill's own harness lives at
# `.claude/skills/scenario-refine/tests/run_tests.sh`, which the CI "Shell gate
# tests" job does NOT pick up — that job globs only `scripts/tests/*-test.sh`.
# Without this shim the harness (inventory selection: rotation / category
# resolution / ja-en tiering, and audit-journal appending against fixtures)
# runs nowhere automatically. This file matches the glob and delegates, giving
# the harness a CI home.
#
# The harness needs python3 (on the ubuntu-latest runner); it `cd`s to its own
# dir, so it is invocation-location independent.
#
# The skill-harness-wiring completeness gate enforces that this shim exists and
# delegates — see scripts/tests/skill-harness-wiring-test.sh.
#
# Run manually: bash scripts/tests/scenario-refine-test.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
bash "$REPO_ROOT/.claude/skills/scenario-refine/tests/run_tests.sh"
