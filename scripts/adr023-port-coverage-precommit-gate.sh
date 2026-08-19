#!/usr/bin/env bash
#
# scripts/adr023-port-coverage-precommit-gate.sh — Pre-commit gate for the
# ADR-023 §4 port-disposition coverage check (#1191). Runs
# `python3 scripts/check-adr023-port-coverage.py --self-test` then `--check`
# only when the staged diff touches an input the check reads, mirroring how the
# blocklist / gallery / navigation-map / scenario-format sub-gates self-gate on
# their own inputs.
#
# Why a pre-commit copy when CI (adr023-port-coverage.yml) already has the check:
# adding, deleting, or renaming a Swift file under Engine/** or LLM/** changes
# the coverage set, and editing the ledger can leave a dangling entry. Without
# this gate that first fails at CI — after the push — costing a round-trip. This
# moves the failure local; CI keeps its own copy (defense in depth).
#
# Trigger paths mirror the check's real inputs: every Swift file under the two
# scope directories (an add/delete/rename shifts coverage), the ledger, and the
# checker script itself. The check reads the *index* (`git ls-files`), so a
# staged add/delete is already reflected when this runs.
#
# bash 3.2 portable — ships to dev macOS via the pre-commit hook. NO
# mapfile/readarray, declare -A, ${var^^}, or <<< here-strings.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

TRIGGER='(^Pastura/Pastura/(Engine|LLM)/.*\.swift$)|(^shared/adr-023-port-ledger\.tsv$)|(^scripts/check-adr023-port-coverage\.py$)'

# Capture, don't `| grep -q`: under `pipefail` an early match makes the
# still-writing producer SIGPIPE and the gate skips despite matching (#1498).
# Dropping `-q` is what fixes it, NOT the `STAGED=` capture — re-adding `-q`
# below reinstates the defect on `printf` instead of on `git`. Rationale and
# the `|| [ $? -eq 1 ]` contract: `.claude/rules/ci-workflows.md` § "Rule 3".
STAGED="$(git -c core.quotepath=false diff --cached --name-only)"
MATCHED="$(printf '%s\n' "$STAGED" | { grep -E "$TRIGGER" || [ $? -eq 1 ]; })"
if [ -z "$MATCHED" ]; then
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo 'adr-023 port-coverage gate: python3 not found — install the Xcode' >&2
  echo 'Command Line Tools (xcode-select --install). The coverage gate needs it.' >&2
  exit 1
fi

# --self-test validates the checker on synthetic fixtures (positive + both
# bidirectional directions + per-row rules); --check gates the real ledger
# against the real tracked tree, matching CI order.
python3 scripts/check-adr023-port-coverage.py --self-test
python3 scripts/check-adr023-port-coverage.py --check
