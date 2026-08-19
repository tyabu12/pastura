#!/usr/bin/env bash
# gallery-precommit-gate.sh — Pre-commit gate for the gallery drift
# check. Runs `check-gallery-entry.sh --all` only when the staged diff
# touches a .yaml/.json under docs/gallery/ — <id>.yaml, gallery.json, or
# highlights/<id>.json (ADR-029).
#
# README.md and shared-scenario-reports.md edits in the same directory are
# intentionally NOT triggers — they are not the published manifest and
# the check has nothing to validate against them.
#
# Why a separate script instead of inlining in .claude/settings.json:
# the gate's grep regex uses characters (alternation, escapes) that
# tangle with JSON-string escaping rules. A standalone script keeps
# settings.json readable and makes the gate testable.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# Relaxed per this header's own pre-authorization: ADR-029 added the
# docs/gallery/highlights/ subdirectory, so the previous flat-directory regex
# would have silently skipped a highlight-only commit. Any .yaml/.json under
# docs/gallery/ now triggers; check-gallery-entry.sh ignores irrelevant
# siblings. Non-manifest siblings (README.md,
# shared-scenario-reports.md) stay untriggered — they are not .yaml/.json.
# Capture, don't `| grep -q`: under `pipefail` an early match makes the
# still-writing producer SIGPIPE and the gate skips despite matching (#1498).
# Dropping `-q` is what fixes it, NOT the `STAGED=` capture — re-adding `-q`
# below reinstates the defect on `printf` instead of on `git`. Rationale and
# the `|| [ $? -eq 1 ]` contract: `.claude/rules/ci-workflows.md` § "Rule 3".
STAGED="$(git -c core.quotepath=false diff --cached --name-only)"
MATCHED="$(printf '%s\n' "$STAGED" | { grep -E '^docs/gallery/.*\.(yaml|json)$' || [ $? -eq 1 ]; })"
if [ -z "$MATCHED" ]; then
  exit 0
fi

bash scripts/check-gallery-entry.sh --all
