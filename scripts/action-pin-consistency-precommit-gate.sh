#!/usr/bin/env bash
#
# scripts/action-pin-consistency-precommit-gate.sh — Pre-commit gate for the
# GitHub Actions pin-consistency check (#1359). Runs
# `python3 scripts/check-action-pin-consistency.py --self-test` then `--check`
# only when the staged diff touches an input the check reads, mirroring how the
# blocklist / gallery / navigation-map sub-gates self-gate on their own inputs.
#
# Why a pre-commit copy when the CI action-pin-consistency job already has the
# check: the failure this defends is invisible at merge time. codeql.yml has no
# push / pull_request trigger, so a mixed init/analyze pair merges green and
# only surfaces on the next 18:05 UTC schedule — up to 24 hours of the repo not
# being scanned. Moving the failure local removes that window entirely for a
# hand-edit; CI keeps its own copy for the Dependabot path (defense in depth).
#
# Trigger paths mirror the check's real inputs (WORKFLOW_DIR glob + the checker
# script itself), including .yaml — GitHub accepts either suffix, and the
# checker scans both. Note .github/dependabot.yml is deliberately NOT a trigger:
# the check reads workflow files only, and grouping config cannot make the pins
# diverge on its own.
#
# The selection is on STAGED paths but --check reads the WORKING TREE, so a
# partial stage (git add -p) could stage a divergent pin while the worktree
# holds the fix, and this gate would pass. The sibling gates share that shape;
# CI re-runs the same check against the pushed tree, which is what closes it.
#
# bash 3.2 portable — ships to dev macOS via the pre-commit hook. NO
# mapfile/readarray, declare -A, ${var^^}, or <<< here-strings.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

TRIGGER='(^\.github/workflows/.*\.ya?ml$)|(^scripts/check-action-pin-consistency\.py$)'

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
  echo 'action-pin gate: python3 not found — install the Xcode Command Line' >&2
  echo 'Tools (xcode-select --install). The action-pin gate needs it.' >&2
  exit 1
fi

# --self-test validates the checker on synthetic fixtures (clean case plus a
# control per invariant); --check gates the real workflows, matching CI order.
python3 scripts/check-action-pin-consistency.py --self-test
python3 scripts/check-action-pin-consistency.py --check
