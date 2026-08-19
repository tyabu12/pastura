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
# still-writing `git` SIGPIPE and the gate skips despite matching (#1498).
# `|| [ $? -eq 1 ]` keeps exit 1 as "no match" and lets exit >=2 fail loudly.
STAGED="$(git diff --cached --name-only)"
MATCHED="$(printf '%s\n' "$STAGED" | { grep -E '^(docs/blocklist/source[.]json|Pastura/Pastura/Resources/ContentBlocklist[.]json)$' || [ $? -eq 1 ]; })"
if [ -z "$MATCHED" ]; then
  exit 0
fi

bash scripts/build-blocklist.sh --check
