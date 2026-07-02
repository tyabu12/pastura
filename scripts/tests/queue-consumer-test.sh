#!/usr/bin/env bash
#
# scripts/tests/queue-consumer-test.sh — CI shim that runs the queue-consumer
# skill's helper self-test (#891).
#
# The skill's own harness lives at
# `.claude/skills/queue-consumer/tests/run_tests.sh`, which the CI "Shell gate
# tests" job does NOT pick up — that job globs only `scripts/tests/*-test.sh`.
# Without this shim the harness (append_digest.py fixtures + the main-checkout
# resolver via a throwaway git repo) runs nowhere automatically. This file
# matches the glob and delegates, giving the harness a CI home.
#
# The harness needs python3 + git (both on the ubuntu-latest runner); it uses
# inline `git -c user.email=... user.name=...` so no global git identity is
# required, and it `cd`s to its own dir, so it is invocation-location
# independent.
#
# The skill-harness-wiring completeness gate enforces that this shim exists and
# delegates — see scripts/tests/skill-harness-wiring-test.sh.
#
# Run manually: bash scripts/tests/queue-consumer-test.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
bash "$REPO_ROOT/.claude/skills/queue-consumer/tests/run_tests.sh"
