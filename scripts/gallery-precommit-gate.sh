#!/usr/bin/env bash
# gallery-precommit-gate.sh — Pre-commit gate for the gallery drift
# check. Runs `check-gallery-entry.sh --all` only when the staged diff
# touches docs/gallery/<id>.yaml or docs/gallery/gallery.json.
#
# README.md and share-board-reports.md edits in the same directory are
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

if ! git diff --cached --name-only | grep -qE '^docs/gallery/([^/]+\.yaml|gallery\.json)$'; then
  exit 0
fi

bash scripts/check-gallery-entry.sh --all
