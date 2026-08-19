#!/usr/bin/env bash
#
# scripts/kmp-status-precommit-gate.sh — Pre-commit gate for the KMP migration
# status board's Wave B checklist drift check (#1231). Runs
# `python3 scripts/check-kmp-status.py --self-test` then `--check` only when the
# staged diff touches an input the check reads, mirroring how the blocklist /
# gallery / navigation-map / adr023-port-coverage sub-gates self-gate on their
# own inputs.
#
# Why a pre-commit copy when CI (ci.yml "Shell gate tests") already has the
# check: porting a handler (adding a `.kt` under the commonMain Phases dir)
# without flipping its board row, or ticking a row before the `.kt` lands, drifts
# the board — and previously that first failed at CI, after the push, costing a
# round-trip. This gate moves the failure local. CI keeps its own copy (defense
# in depth).
#
# Trigger paths mirror the check's real inputs (check-kmp-status.py): the board
# itself, the ADR-023 port ledger (its Phases rows are the canonical handler
# set), every ported handler `.kt` under the commonMain Phases dir (an add/delete
# shifts the ported set), and the checker script. The check reads the ported set
# via `git ls-files` (the index), so a staged add/delete is already reflected.
# The board is a trigger too so a hand-edit that drifts it from the tree is caught
# locally; a legitimate flip stages the board alongside its `.kt` and passes.
#
# bash 3.2 portable — ships to dev macOS via the pre-commit hook. NO
# mapfile/readarray, declare -A, ${var^^}, or <<< here-strings.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

TRIGGER='(^docs/kmp-migration-status\.md$)|(^shared/adr-023-port-ledger\.tsv$)|(^shared/engine/src/commonMain/kotlin/com/pastura/engine/Phases/.*\.kt$)|(^scripts/check-kmp-status\.py$)'

# Capture, don't `| grep -q`: under `pipefail` an early match makes the
# still-writing `git` SIGPIPE and the gate skips despite matching (#1498).
# `|| [ $? -eq 1 ]` keeps exit 1 as "no match" and lets exit >=2 fail loudly.
STAGED="$(git diff --cached --name-only)"
MATCHED="$(printf '%s\n' "$STAGED" | { grep -E "$TRIGGER" || [ $? -eq 1 ]; })"
if [ -z "$MATCHED" ]; then
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo 'kmp-status gate: python3 not found — install the Xcode Command Line' >&2
  echo 'Tools (xcode-select --install). The drift guard needs python3.' >&2
  exit 1
fi

# --self-test validates the checker on synthetic fixtures; --check gates the real
# board against the real ledger + tracked tree, matching CI order.
python3 scripts/check-kmp-status.py --self-test
python3 scripts/check-kmp-status.py --check
