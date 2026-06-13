#!/usr/bin/env bash
#
# scripts/tests/p8-precommit-gate-test.sh — regression test for
# scripts/p8-precommit-gate.sh (ADR-014 § Secrets).
#
# Builds throwaway git repositories under a tempdir so the real index is
# never touched. The reject case stages the key in a SUBDIRECTORY on
# purpose: a top-level-only matcher would pass this test only if it were
# (incorrectly) anchored to the repo root, so the subdir placement locks
# in the depth-agnostic `\.p8$` behaviour.
#
# Run manually (no CI wiring — there is no shell-test harness in the repo):
#   bash scripts/tests/p8-precommit-gate-test.sh

set -euo pipefail

GATE="$(git rev-parse --show-toplevel)/scripts/p8-precommit-gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0

# Case 1: a .p8 staged in a subdirectory must be rejected (exit non-zero).
repo_reject="$TMP/reject"
git init -q "$repo_reject"
(
  cd "$repo_reject"
  git config user.email test@example.com
  git config user.name test
  mkdir -p keys
  : > keys/AuthKey_ABC123.p8
  git add -f keys/AuthKey_ABC123.p8
  if bash "$GATE" >/dev/null 2>&1; then
    echo "FAIL: gate accepted a staged subdirectory .p8" >&2
    exit 1
  fi
) || fail=1

# Case 2: a clean staging set (no .p8) must pass (exit zero).
repo_accept="$TMP/accept"
git init -q "$repo_accept"
(
  cd "$repo_accept"
  git config user.email test@example.com
  git config user.name test
  : > README.md
  git add README.md
  if ! bash "$GATE" >/dev/null 2>&1; then
    echo "FAIL: gate rejected a clean staging set" >&2
    exit 1
  fi
) || fail=1

if [ "$fail" -eq 0 ]; then
  echo "p8-precommit-gate: all cases passed"
else
  echo "p8-precommit-gate: FAILURES" >&2
  exit 1
fi
