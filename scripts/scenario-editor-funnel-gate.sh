#!/usr/bin/env bash
#
# scripts/scenario-editor-funnel-gate.sh — Pre-commit + CI tripwire for
# the ScenarioEditor funnel invariant (#338, formerly a manual PR-review
# grep documented in .claude/rules/scenario-editor.md).
#
# `ScenarioEditorViewModel` holds a dual buffer (visual fields + yamlText);
# both reconcile only via the private `currentScenario()` funnel. A new
# callsite that reads visual state directly (via `buildScenario()`)
# bypasses the mode dispatch and re-introduces the #336 drift class. The
# count of `buildScenario()` occurrences is a cheap structural tripwire:
# today exactly 3 (1 private declaration + 2 sanctioned callsites in
# `switchToYAMLMode()` and `currentScenario()`).
#
# This count is a RE-EVALUATION TRIGGER, not a correctness proof — a count
# of 3 with a NEW direct visual-state read displacing a sanctioned one
# still violates the funnel. The Swift behavioral tripwire in
# `ScenarioEditorViewModelTests` is the backstop. The deferred
# source-of-truth redesign lives in #725 (supersedes #338).
#
# Modes:
#   (default)  self-gate — run the count check only when the staged diff
#              touches a ScenarioEditorViewModel*.swift file, mirroring how
#              the blocklist / gallery / p8 / navigation-map sub-gates
#              self-gate on their own inputs. Used by the git pre-commit hook.
#   --check    unconditional — always run the count check against the
#              current tree. Used by the CI scenario-editor-funnel-drift job
#              (no staging exists in CI).
#
# bash 3.2-clean (ships to dev macOS via the pre-commit hook): no mapfile,
# declare -A, ${var^^}, or <<< here-strings. Uses `grep` not `rg` so it
# carries no ripgrep dependency. Tested by
# scripts/tests/scenario-editor-funnel-gate-test.sh.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# Production ViewModel only — never the test glob (PasturaTests/), whose
# doc-comments mention `buildScenario()` in prose and would inflate the
# count. The `*` glob is split-resilience for a future
# `ScenarioEditorViewModel+Feature.swift` extraction; `buildScenario()` is
# `private` so any caller must live in a same-named sibling the glob covers.
VM_DIR="Pastura/Pastura/App"
VM_TRIGGER='^Pastura/Pastura/App/ScenarioEditorViewModel[^/]*\.swift$'

# Expected occurrences: 1 declaration + 2 sanctioned callsites. If the VM is
# ever split into ScenarioEditorViewModel+*.swift, this magic number must be
# revisited at split time.
EXPECTED=3

CHECK_ALL=0
if [ "${1:-}" = "--check" ]; then
  CHECK_ALL=1
fi

# Self-gate: in default (pre-commit) mode, skip unless a VM file is staged.
if [ "$CHECK_ALL" -eq 0 ]; then
  # Capture, don't `| grep -q`: under `pipefail` an early match makes the
  # still-writing producer SIGPIPE and the gate skips despite matching (#1498).
  # Dropping `-q` is what fixes it, NOT the `STAGED=` capture — re-adding `-q`
  # below reinstates the defect on `printf` instead of on `git`. Rationale and
  # the `|| [ $? -eq 1 ]` contract: `.claude/rules/ci-workflows.md` § "Rule 3".
  STAGED="$(git -c core.quotepath=false diff --cached --name-only)"
  MATCHED="$(printf '%s\n' "$STAGED" | { grep -E "$VM_TRIGGER" || [ $? -eq 1 ]; })"
  if [ -z "$MATCHED" ]; then
    exit 0
  fi
fi

# The count is read from the WORKING TREE (find + grep on-disk), not the
# staged blob — consistent with the gallery / navigation-map siblings. The
# CI --check job is the authoritative merge-time gate.
#
# Collect the production VM file(s). find keeps this robust if the glob is
# ever empty (rename) — we fail loudly rather than letting an unquoted glob
# expand to a literal and grep read stdin.
files="$(find "$VM_DIR" -maxdepth 1 -name 'ScenarioEditorViewModel*.swift' 2>/dev/null || true)"
if [ -z "$files" ]; then
  echo "scenario-editor funnel gate: no $VM_DIR/ScenarioEditorViewModel*.swift found." >&2
  echo "Was the file renamed? Update VM_DIR/VM_TRIGGER and revisit EXPECTED — see #725." >&2
  exit 1
fi

# Count call-shape occurrences. `-oF` matches the literal `buildScenario()`
# (parens included) and prints one line per occurrence; the `|| true` keeps
# a zero-match (grep exit 1) from tripping pipefail before we can compare.
count="$(grep -oF 'buildScenario()' $files 2>/dev/null | wc -l | tr -d ' ' || true)"

if [ "$count" -ne "$EXPECTED" ]; then
  echo "scenario-editor funnel gate: buildScenario() appears ${count}× in" >&2
  echo "  ${VM_DIR}/ScenarioEditorViewModel*.swift (expected ${EXPECTED}:" >&2
  echo "  1 private declaration + 2 sanctioned callsites in switchToYAMLMode()" >&2
  echo "  and currentScenario())." >&2
  echo "" >&2
  echo "This count is a RE-EVALUATION TRIGGER, not a correctness proof:" >&2
  echo "  > ${EXPECTED}: a new callsite reads visual state directly, bypassing the" >&2
  echo "    currentScenario() funnel (the #336 drift class). Route it through" >&2
  echo "    currentScenario(), OR treat this as the trigger to revisit the editor" >&2
  echo "    source-of-truth design — see #725." >&2
  echo "  < ${EXPECTED}: a sanctioned callsite was dropped — same re-evaluation gate." >&2
  echo "  A count of ${EXPECTED} with a NEW direct visual-state read still violates the" >&2
  echo "  funnel; the Swift behavioral tripwire (ScenarioEditorViewModelTests) is the" >&2
  echo "  backstop. If the VM was split into ScenarioEditorViewModel+*.swift, revisit" >&2
  echo "  the expected count." >&2
  echo "" >&2
  echo "See .claude/rules/scenario-editor.md." >&2
  exit 1
fi

exit 0
