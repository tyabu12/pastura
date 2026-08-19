#!/usr/bin/env bash
#
# scripts/prompt-literal-parity-precommit-gate.sh — Pre-commit gate for the
# Swift <-> Kotlin `pickLanguage` prompt-literal parity check (#1295). Runs
# `python3 scripts/check-prompt-literal-parity.py --self-test` then `--check`
# only when the staged diff touches an input the check reads, mirroring how the
# blocklist / gallery / navigation-map / port-coverage sub-gates self-gate on
# their own inputs.
#
# Why a pre-commit copy when CI (the shell-tests job) already runs the check:
# the failure this catches is a ONE-SIDED prompt edit, which is the ordinary
# shape of the work — #1294 edited both sides by hand and nothing would have
# caught a miss. Without this gate that first fails at CI, after the push.
# CI keeps its own copy (defense in depth).
#
# Trigger paths are BOTH sides plus the check's own data. Omitting the Kotlin
# side would make this gate inert on exactly the one-sided Kotlin edit it exists
# to catch — the Swift-only trigger looks plausible precisely because the Swift
# tree is where most edits land.
#
# Scope note: the trigger reads the INDEX (`git diff --cached`) but the checker
# reads the WORKTREE (`git ls-files` for the file list, then `read_text`). Same
# shape as the adr023-port-coverage and kmp-status gates. Consequence: a
# partially-staged edit (`git add -p`) is gated against uncommitted content, so a
# one-sided edit can commit locally if its counterpart sits unstaged in the tree.
# CI is the backstop — it checks out the commit — which is why this is documented
# rather than re-engineered away from the sibling gates' shape.
#
# bash 3.2 portable — ships to dev macOS via the pre-commit hook. NO
# mapfile/readarray, declare -A, ${var^^}, or <<< here-strings.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

TRIGGER='(^Pastura/Pastura/(Engine|LLM)/.*\.swift$)|(^shared/engine/src/commonMain/.*\.kt$)|(^shared/prompt-literal-parity-allowlist\.tsv$)|(^scripts/check-prompt-literal-parity\.py$)'

# Capture, don't `| grep -q`: under `pipefail` an early match makes the
# still-writing `git` SIGPIPE and the gate skips despite matching (#1498).
# `|| [ $? -eq 1 ]` keeps exit 1 as "no match" and lets exit >=2 fail loudly.
STAGED="$(git diff --cached --name-only)"
MATCHED="$(printf '%s\n' "$STAGED" | { grep -E "$TRIGGER" || [ $? -eq 1 ]; })"
if [ -z "$MATCHED" ]; then
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo 'prompt-literal parity gate: python3 not found — install the Xcode' >&2
  echo 'Command Line Tools (xcode-select --install). The parity gate needs it.' >&2
  exit 1
fi

# --self-test validates the extractor against fixtures copied from the real tree
# plus its negative controls; --check gates the real Swift/Kotlin pair. Same
# order as CI. The self-test is not optional here: the checker's own bugs are
# silent (a broken extractor emits a clean --check), so the controls are what
# distinguish "parity holds" from "nothing was extracted".
python3 scripts/check-prompt-literal-parity.py --self-test
python3 scripts/check-prompt-literal-parity.py --check
