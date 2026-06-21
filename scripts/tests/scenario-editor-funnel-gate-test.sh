#!/usr/bin/env bash
#
# scripts/tests/scenario-editor-funnel-gate-test.sh — regression test for
# scripts/scenario-editor-funnel-gate.sh (#338 funnel tripwire).
#
# Builds throwaway git repositories under a tempdir so the real index is
# never touched. Each case writes a synthetic ScenarioEditorViewModel.swift
# with a known number of `buildScenario()` occurrences and asserts the
# gate's exit code. Locks in: exactly 3 -> pass; 2 or 4 -> fail; and the
# default-mode self-gate (skip when no VM file is staged).
#
# CI-wired: the `*-test.sh` naming convention makes this a gate under
# .github/workflows/ci.yml ("Run scripts/tests/*-test.sh"). Run manually:
#   bash scripts/tests/scenario-editor-funnel-gate-test.sh

set -euo pipefail

GATE="$(git rev-parse --show-toplevel)/scripts/scenario-editor-funnel-gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0

# Writes a ScenarioEditorViewModel.swift containing exactly $1 occurrences
# of the `buildScenario()` call-shape into the repo at the canonical path.
write_vm() {
  local repo="$1" n="$2" i
  mkdir -p "$repo/Pastura/Pastura/App"
  local f="$repo/Pastura/Pastura/App/ScenarioEditorViewModel.swift"
  : > "$f"
  i=0
  while [ "$i" -lt "$n" ]; do
    echo "    let scenario = buildScenario()" >> "$f"
    i=$((i + 1))
  done
}

init_repo() {
  local repo="$1"
  git init -q "$repo"
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name test
}

# Case 1: exactly 3 occurrences under --check must pass (exit 0).
repo="$TMP/three"
init_repo "$repo"
write_vm "$repo" 3
(
  cd "$repo"
  if ! bash "$GATE" --check >/dev/null 2>&1; then
    echo "FAIL: gate rejected the sanctioned 3-occurrence count" >&2
    exit 1
  fi
) || fail=1

# Case 2: 4 occurrences under --check must fail (new direct-read callsite).
repo="$TMP/four"
init_repo "$repo"
write_vm "$repo" 4
(
  cd "$repo"
  if bash "$GATE" --check >/dev/null 2>&1; then
    echo "FAIL: gate accepted a 4-occurrence count (drift trigger missed)" >&2
    exit 1
  fi
) || fail=1

# Case 3: 2 occurrences under --check must fail (a sanctioned callsite dropped).
repo="$TMP/two"
init_repo "$repo"
write_vm "$repo" 2
(
  cd "$repo"
  if bash "$GATE" --check >/dev/null 2>&1; then
    echo "FAIL: gate accepted a 2-occurrence count (drift trigger missed)" >&2
    exit 1
  fi
) || fail=1

# Case 4: default mode self-gates — a wrong count (4) must be SKIPPED when
# no VM file is staged (only an unrelated file is staged).
repo="$TMP/selfgate"
init_repo "$repo"
write_vm "$repo" 4
(
  cd "$repo"
  : > README.md
  git add README.md
  if ! bash "$GATE" >/dev/null 2>&1; then
    echo "FAIL: default mode did not self-gate (ran despite no VM file staged)" >&2
    exit 1
  fi
) || fail=1

if [ "$fail" -eq 0 ]; then
  echo "scenario-editor-funnel-gate: all cases passed"
else
  echo "scenario-editor-funnel-gate: FAILURES" >&2
  exit 1
fi
