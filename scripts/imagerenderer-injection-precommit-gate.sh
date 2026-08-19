#!/usr/bin/env bash
#
# scripts/imagerenderer-injection-precommit-gate.sh — Pre-commit gate for the
# fixed-appearance-export injection check (ADR-028 § "Revisit trigger" bullet 1).
# Runs `python3 scripts/check_imagerenderer_injection.py --self-test` then
# `--check` only when the staged diff touches a file the check reads, mirroring
# how the blocklist / gallery / navigation-map / outputschema sub-gates self-gate
# on their own inputs.
#
# Why the check exists: #1337 measured that a paired `Color.*` alias read inside
# an `ImageRenderer` export is NOT the hazard — it resolves against the injected
# `colorScheme`. An export that injects NOTHING is: it rasterizes light on any
# device, which is #1070. ADR-009 rules out the snapshot test that would observe
# it, and no other gate reaches it, so this is the only mechanical detector for
# the hazard that ADR names.
#
# Trigger scope is the app target's Swift sources — a new `ImageRenderer` can
# appear in any of them, not just near the existing one — plus the check itself.
# A docs/web/CI-only commit skips it; CI keeps its own copy (defense in depth).
#
# This gate is a tripwire on the NEXT export file, not a fit to the current one:
# today `HighlightCardImageRenderer.swift` is the only consumer and is the arm
# that must stay green. Verified by mutation, not by its success case — deleting
# that file's `.environment(\.colorScheme, …)` makes `--check` exit 1 and name
# the file.
#
# bash 3.2 portable — ships to dev macOS via the pre-commit hook. NO
# mapfile/readarray, declare -A, ${var^^}, or <<< here-strings.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

TRIGGER='(^Pastura/Pastura/.*\.swift$)|(^scripts/check_imagerenderer_injection\.py$)'

# Capture, don't `| grep -q` — `-q` exits early, the still-writing producer
# SIGPIPEs, and `pipefail` turns a MATCH into a skip (#1498).
# `.claude/rules/ci-workflows.md` § "Rule 3".
STAGED="$(git -c core.quotepath=false diff --cached --name-only)"
MATCHED="$(printf '%s\n' "$STAGED" | { grep -E "$TRIGGER" || [ $? -eq 1 ]; })"
if [ -z "$MATCHED" ]; then
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo 'imagerenderer-injection gate: python3 not found — install the Xcode' >&2
  echo 'Command Line Tools (xcode-select --install). The gate needs it.' >&2
  exit 1
fi

# --self-test validates the detector on synthetic fixtures (positive control +
# the UIGraphicsImageRenderer substring trap); --check gates the real tree.
python3 scripts/check_imagerenderer_injection.py --self-test
python3 scripts/check_imagerenderer_injection.py --check
