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

if ! git diff --cached --name-only | grep -qE '^(docs/blocklist/source[.]json|Pastura/Pastura/Resources/ContentBlocklist[.]json)$'; then
  exit 0
fi

bash scripts/build-blocklist.sh --check
