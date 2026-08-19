#!/usr/bin/env bash
#
# scripts/mossink-wash-membership-precommit-gate.sh — Pre-commit gate for the
# design-system §8 / `mossInkWashSites` membership check (#1467). Runs
# `python3 scripts/check-mossink-wash-membership.py --self-test` then
# `--check` only when the staged diff touches a file the check reads,
# mirroring how the other checker-backed sub-gates self-gate on their own
# inputs.
#
# Why the check exists: §8's closing sub-bullet quotes the fixture's row
# names and states outright that the fixture is the membership authority —
# but nothing enforced that the two stay in sync, and a row added to
# `mossInkWashSites` left the bullet stale with nothing to notice. Same
# failure class as ADR-028 § "Count-mirror sweep", one step weaker: that
# sweep's count-shaped command matches a digit or spelled-out count, not a
# name set, so it does not reach this mirror.
#
# Trigger scope is design-system.md §8, the mossInkWashSites fixture, and the
# checker itself — a docs/web/CI-only commit unrelated to any of the three
# skips it; CI keeps its own copy (defense in depth).
#
# bash 3.2 portable — ships to dev macOS via the pre-commit hook. NO
# mapfile/readarray, declare -A, ${var^^}, or <<< here-strings.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

TRIGGER='(^docs/design/design-system\.md$)|(^Pastura/PasturaTests/Views/DesignTokensTests\+MossInkAsWashLabel\.swift$)|(^scripts/check-mossink-wash-membership\.py$)'

# Capture, don't `| grep -q`: under `pipefail` an early match makes the
# still-writing `git` SIGPIPE and the gate skips despite matching (#1498).
# `|| [ $? -eq 1 ]` keeps exit 1 as "no match" and lets exit >=2 fail loudly.
STAGED="$(git diff --cached --name-only)"
MATCHED="$(printf '%s\n' "$STAGED" | { grep -E "$TRIGGER" || [ $? -eq 1 ]; })"
if [ -z "$MATCHED" ]; then
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo 'mossink-wash-membership gate: python3 not found — install the Xcode' >&2
  echo 'Command Line Tools (xcode-select --install). The gate needs it.' >&2
  exit 1
fi

# --self-test validates the extractor on synthetic fixtures (positive control
# + the wrapped-row / phantom-member traps); --check gates the real tree.
python3 scripts/check-mossink-wash-membership.py --self-test
python3 scripts/check-mossink-wash-membership.py --check
