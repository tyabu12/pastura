#!/usr/bin/env bash
#
# scripts/navigation-map-precommit-gate.sh — Pre-commit gate for the
# navigation-map drift check (#652). Runs
# `python3 scripts/generate-navigation-map.py --self-test` then `--check`
# only when the staged diff touches a file that can change the generated
# map, mirroring how the blocklist / gallery / p8 sub-gates self-gate on
# their own inputs.
#
# Why a pre-commit copy when CI already has the drift job: a Route
# add/remove/rename, or moving a NavigationLink(value:) / router.push
# callsite to a new file, drifts the generated map and previously failed
# for the first time at CI — after the push — costing a round-trip
# (concretely PR #651's HomeScenarioRow.swift extraction). This gate moves
# that failure local. CI keeps its own copy (defense in depth).
#
# Trigger paths mirror the generator's real inputs
# (generate-navigation-map.py L72-79): ROUTER_FILE + the App/ scan dir
# (`Pastura/Pastura/App/**`), the Views/ scan dir
# (`Pastura/Pastura/Views/**`), the screenshot-tour table source, and the
# generator script itself. The OUTPUT_FILE (docs/design/navigation-map.md)
# is ALSO a trigger — beyond the literal #652 spec — so a hand-edit of the
# map that drifts it from source is caught locally too; a legitimate
# regeneration commit stages the map alongside its source change and still
# passes --check. Keep this trigger; do not "tidy" it away.
#
# bash 3.2 portable — ships to dev macOS via the pre-commit hook
# (`#!/usr/bin/env bash`). NO mapfile/readarray, declare -A, ${var^^}, or
# <<< here-strings. The CI shell-tests job runs on ubuntu (bash 5+) and
# does NOT catch a 3.2 regression — keep this 3.2-clean by hand.
# Tested by scripts/tests/navigation-map-precommit-gate-test.sh.
#
# First pre-commit sub-gate to shell out to python3 at commit time. The
# generator is pure stdlib (no pip deps), but python3 itself must be
# present — macOS ships it via the Xcode Command Line Tools.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# The Views/ and App/ globs use a RECURSIVE `.*\.swift$` — the generator
# scans those dirs with rglob, so a nested file (App/Sub/Foo.swift) is a
# real input. Do NOT copy the gallery gate's single-level `[^/]+` form;
# that directory is intentionally flat, this one is not.
TRIGGER='(^Pastura/Pastura/(Views|App)/.*\.swift$)|(^Pastura/PasturaUITests/ScreenshotTourTests\.swift$)|(^scripts/generate-navigation-map\.py$)|(^docs/design/navigation-map\.md$)'

# Capture, don't `| grep -q`: under `pipefail` an early match makes the
# still-writing `git` SIGPIPE and the gate skips despite matching (#1498).
# `|| [ $? -eq 1 ]` keeps exit 1 as "no match" and lets exit >=2 fail loudly.
STAGED="$(git diff --cached --name-only)"
MATCHED="$(printf '%s\n' "$STAGED" | { grep -E "$TRIGGER" || [ $? -eq 1 ]; })"
if [ -z "$MATCHED" ]; then
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo 'navigation-map gate: python3 not found — install the Xcode Command' >&2
  echo 'Line Tools (xcode-select --install). The drift guard needs python3.' >&2
  exit 1
fi

# Run --self-test unconditionally before --check, matching CI's ordering
# (.github/workflows/ci.yml navigation-map-drift job). --self-test
# validates the generator's own fixtures; --check regenerates the map in
# memory and diffs it against the committed file, failing on drift.
python3 scripts/generate-navigation-map.py --self-test
python3 scripts/generate-navigation-map.py --check
