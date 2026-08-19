#!/usr/bin/env bash
# blocklist-precommit-gate.sh — Pre-commit gate for the ContentBlocklist
# drift check. Runs `build-blocklist.sh --check` only when the staged diff
# touches docs/blocklist/source.json or
# Pastura/Pastura/Resources/ContentBlocklist.json.
#
# Why a separate script instead of inlining in .claude/settings.json:
# the gate's grep regex uses characters (single quotes, brackets) that
# tangle with JSON-string escaping rules. A standalone script keeps
# settings.json readable and makes the gate testable.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# Capture, don't `| grep -q`: under `pipefail` an early match makes the
# still-writing producer SIGPIPE and the gate skips despite matching (#1498).
# Dropping `-q` is what fixes it, NOT the `STAGED=` capture — re-adding `-q`
# below reinstates the defect on `printf` instead of on `git`. Rationale and
# the `|| [ $? -eq 1 ]` contract: `.claude/rules/ci-workflows.md` § "Rule 3".
STAGED="$(git diff --cached --name-only)"
MATCHED="$(printf '%s\n' "$STAGED" | { grep -E '^(docs/blocklist/source[.]json|Pastura/Pastura/Resources/ContentBlocklist[.]json)$' || [ $? -eq 1 ]; })"
if [ -z "$MATCHED" ]; then
  exit 0
fi

bash scripts/build-blocklist.sh --check
