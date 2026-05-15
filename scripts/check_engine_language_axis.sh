#!/usr/bin/env bash
#
# check_engine_language_axis.sh — ADR-010 D5 / D8 Engine boundary guard.
#
# Engine output-language dispatch reads `scenario.engineLanguage`
# (= `simulationLanguage ?? language`), NOT `scenario.language` directly.
# Reading `scenario.language` at a dispatch callsite silently breaks the
# `simulation_language` override — the regression this script blocks.
#
# Allow-list (authoring-axis files — they intentionally read `.language`):
#   - ScenarioValidator.swift: validates the authoring `language` field
#   - ScenarioSerializer.swift: writes the authoring `language` to YAML
#
# Rule: under Pastura/Pastura/Engine/, every code reference to
# `scenario.language` outside the allow-list is a violation. Doc-comment
# lines (`///` prefix) are excluded — they describe the field at the
# Models layer in passing and are not dispatch sites.
#
# The check is intentionally line-oriented for grep portability; this
# also means a multi-line `pickLanguage(\n  scenario.language, ...)` is
# caught at the `scenario.language` line itself rather than at the call
# helper. Either match shape would trip the same regression.
#
# Exit codes: 0 clean, 1 violation, 2 misuse.
#
# Reference: docs/decisions/ADR-010.md § D5, D6 row 1, D7, D8.

set -euo pipefail

if [[ "${1-}" == "--help" || "${1-}" == "-h" ]]; then
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

ENGINE_DIR="Pastura/Pastura/Engine"
if [[ ! -d "$ENGINE_DIR" ]]; then
  echo "error: $ENGINE_DIR not found — run from the repo root." >&2
  exit 2
fi

# Match `scenario.language` with word boundaries so `scenario.languageCode`
# (hypothetical future field) does not trip the check.
PATTERN='\bscenario\.language\b'

# Allow-listed filenames (just the basename — grep's --exclude matches that).
EXCLUDES=(
  --exclude=ScenarioValidator.swift
  --exclude=ScenarioSerializer.swift
)

# Find every matching line, then filter out `///` doc-comment lines.
# `grep -E` output is `path:line:content`; we look for `:` then optional
# whitespace then `///` to skip those.
raw=$(grep -rEn "${EXCLUDES[@]}" "$PATTERN" "$ENGINE_DIR" 2>/dev/null || true)
violations=$(printf '%s\n' "$raw" | grep -vE ':[[:space:]]*///' || true)

# Trim a stray empty line so `-n "$violations"` is reliable.
violations=$(printf '%s' "$violations" | sed '/^$/d')

if [[ -n "$violations" ]]; then
  cat >&2 <<EOF
❌ ADR-010 D5 / D8 violation: Engine code reads scenario.language at a
   non-doc-comment position outside the authoring-axis allow-list.
   Use scenario.engineLanguage (or context.scenario.engineLanguage from
   inside a PhaseHandler) so the simulation_language override propagates
   per D6 row 1.

   See docs/decisions/ADR-010.md § D5, D7, D8 for the rule and rationale.

EOF
  echo "$violations" >&2
  cat >&2 <<EOF

If the new usage is authoring-axis (validating or serializing the
declared 'language' field, not selecting Engine output language), add
the file to the EXCLUDES array in this script with a comment explaining
why the authoring axis applies.
EOF
  exit 1
fi

echo "✓ Engine language-axis dispatch clean ($ENGINE_DIR; allow-list: ScenarioValidator, ScenarioSerializer)."
