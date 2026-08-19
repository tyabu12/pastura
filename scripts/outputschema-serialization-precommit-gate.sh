#!/usr/bin/env bash
#
# scripts/outputschema-serialization-precommit-gate.sh — Pre-commit gate for the
# OutputSchema production-serialization check (ADR-023 §12 condition 1). Runs
# `python3 scripts/check-outputschema-serialization-gate.py --self-test` then
# `--check` only when the staged diff touches a file the check reads, mirroring
# how the blocklist / gallery / navigation-map / scenario-format sub-gates
# self-gate on their own inputs.
#
# Why the check exists: ADR-023 §12 condition 1 leaves the Swift<->Kotlin
# OutputSchema JSON tag-form difference standing in production and reconciles it
# only in a parity test. That is safe ONLY while no production code JSON-encodes
# or JSON-decodes an OutputSchema. This gate keeps that premise executable.
#
# Trigger scope is DELIBERATELY WIDE: unlike the scenario-format gate (whose
# inputs are a handful of named files), this check's input is the whole
# production source tree — a new serialization site can appear in ANY production
# Swift/Kotlin file, including one that has nothing else to do with OutputSchema.
# So the trigger is every production source path the check scans, plus the check
# itself. A docs/web/CI-only commit skips it; any production source edit runs it.
# CI keeps its own unconditional copy (defense in depth).
#
# bash 3.2 portable — ships to dev macOS via the pre-commit hook. NO
# mapfile/readarray, declare -A, ${var^^}, or <<< here-strings.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# Matches the check's scan scope (SWIFT_GLOBS + KOTLIN_GLOBS) plus the script.
# Kotlin: any shared/ .kt — the sub-gate is conservative by over-triggering
# (a commonTest edit runs a check that ignores commonTest; harmless), which is
# safer than trying to reproduce the *Main source-set glob in a regex.
TRIGGER='(^Pastura/Pastura/.*\.swift$)|(^shared/.*\.kt$)|(^scripts/check-outputschema-serialization-gate\.py$)'

# Capture, don't `| grep -q`: under `pipefail` an early match makes the
# still-writing `git` SIGPIPE and the gate skips despite matching (#1498).
# `|| [ $? -eq 1 ]` keeps exit 1 as "no match" and lets exit >=2 fail loudly.
STAGED="$(git diff --cached --name-only)"
MATCHED="$(printf '%s\n' "$STAGED" | { grep -E "$TRIGGER" || [ $? -eq 1 ]; })"
if [ -z "$MATCHED" ]; then
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo 'outputschema serialization gate: python3 not found — install the Xcode' >&2
  echo 'Command Line Tools (xcode-select --install). The gate needs it.' >&2
  exit 1
fi

# --self-test validates the checker on synthetic fixtures (per-detector positive
# + negative controls); --check gates the real production tree. Same order as CI.
python3 scripts/check-outputschema-serialization-gate.py --self-test
python3 scripts/check-outputschema-serialization-gate.py --check
