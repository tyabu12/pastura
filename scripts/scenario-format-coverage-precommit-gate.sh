#!/usr/bin/env bash
#
# scripts/scenario-format-coverage-precommit-gate.sh — Pre-commit gate for the
# scenario-format coverage check (#1120). Runs
# `python3 scripts/check-scenario-format-coverage.py --self-test` then `--check`
# only when the staged diff touches an input the check reads, mirroring how the
# blocklist / gallery / navigation-map sub-gates self-gate on their own inputs.
#
# Why a pre-commit copy when CI (scenario-format-coverage.yml) already has the
# check: adding a PhaseType / ScoreCalcLogic case, or editing a locale
# scenario-format.<locale>.md, can drop an enum rawValue out of the public
# format reference. Without this gate that first fails at CI — after the push —
# costing a round-trip. This moves the failure local; CI keeps its own copy
# (defense in depth).
#
# Trigger paths mirror the check's real inputs (check-scenario-format-coverage.py
# raw_values() + SPEC_MD): the two canonical enum files, both locale Markdown
# sources, and the checker script itself.
#
# bash 3.2 portable — ships to dev macOS via the pre-commit hook. NO
# mapfile/readarray, declare -A, ${var^^}, or <<< here-strings.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

TRIGGER='(^Pastura/Pastura/Models/PhaseType\.swift$)|(^Pastura/Pastura/Models/ScoreCalcLogic\.swift$)|(^web/src/content/scenario-format\.(en|ja)\.md$)|(^scripts/check-scenario-format-coverage\.py$)'

# Capture, don't `| grep -q`: under `pipefail` an early match makes the
# still-writing producer SIGPIPE and the gate skips despite matching (#1498).
# Dropping `-q` is what fixes it, NOT the `STAGED=` capture — re-adding `-q`
# below reinstates the defect on `printf` instead of on `git`. Rationale and
# the `|| [ $? -eq 1 ]` contract: `.claude/rules/ci-workflows.md` § "Rule 3".
STAGED="$(git diff --cached --name-only)"
MATCHED="$(printf '%s\n' "$STAGED" | { grep -E "$TRIGGER" || [ $? -eq 1 ]; })"
if [ -z "$MATCHED" ]; then
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo 'scenario-format coverage gate: python3 not found — install the Xcode' >&2
  echo 'Command Line Tools (xcode-select --install). The coverage gate needs it.' >&2
  exit 1
fi

# --self-test validates the checker on synthetic fixtures (positive + negative);
# --check gates the real enum files against the real Markdown, matching CI order.
python3 scripts/check-scenario-format-coverage.py --self-test
python3 scripts/check-scenario-format-coverage.py --check
