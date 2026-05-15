#!/usr/bin/env bash
#
# check_naturallanguage_axis.sh — ADR-010 D8 dependency-rule guard.
#
# `import NaturalLanguage` (Apple's NL framework, host of `NLLanguageRecognizer`)
# is forbidden in Engine / LLM / Models / Data layers per ADR-010 D8 normative.
# Only App/ may import NaturalLanguage; lower-layer code interacts with
# detection via the `(any LanguageDetector)?` protocol existential in
# `Pastura/Pastura/LLM/LanguageDetector.swift`.
#
# The check broadens beyond the bare `^import NaturalLanguage$` line so that
# attribute-prefixed imports (`@preconcurrency import …`,
# `@_implementationOnly import …`) and submodule imports
# (`import NaturalLanguage.NLLanguageRecognizer`) are all caught. Comment-only
# lines (`// references NaturalLanguage in passing`) are filtered out so
# doc-comments that mention the framework as context don't trip the guard.
#
# Self-test (commented fixtures below) demonstrates which shapes the regex
# catches; the runtime check filters only Swift source under the four
# guarded directories.
#
# Exit codes: 0 clean, 1 violation, 2 misuse.
#
# Reference: docs/decisions/ADR-010.md § D8 (dependency-rule guarantee).

set -euo pipefail

if [[ "${1-}" == "--help" || "${1-}" == "-h" ]]; then
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

GUARDED_DIRS=(
  "Pastura/Pastura/Engine"
  "Pastura/Pastura/LLM"
  "Pastura/Pastura/Models"
  "Pastura/Pastura/Data"
)

for dir in "${GUARDED_DIRS[@]}"; do
  if [[ ! -d "$dir" ]]; then
    echo "error: $dir not found — run from the repo root." >&2
    exit 2
  fi
done

# Match all of:
#   import NaturalLanguage
#   @preconcurrency import NaturalLanguage
#   @_implementationOnly import NaturalLanguage
#   import NaturalLanguage.NLLanguageRecognizer
#
# Self-test fixtures (each line should match the PATTERN below; verified
# locally on macOS 26.4.1 / BSD grep -E during PR2 development):
#   import NaturalLanguage
#   @preconcurrency import NaturalLanguage
#   @_implementationOnly import NaturalLanguage
#   import NaturalLanguage.NLLanguageRecognizer
PATTERN='import[[:space:]]+(@[a-zA-Z_]+[[:space:]]+)?NaturalLanguage(\.[A-Za-z_]+)?\b'

# Find every matching line across all guarded directories, then filter out
# comment-only lines (`///` doc-comments and inline `//` notes). Lines where
# code precedes the comment do NOT match this filter and still trip the
# guard — matches `check_engine_language_axis.sh`'s line-discipline.
raw=""
for dir in "${GUARDED_DIRS[@]}"; do
  raw+="$(grep -rEn "$PATTERN" "$dir" 2>/dev/null || true)"$'\n'
done
violations=$(printf '%s' "$raw" | grep -vE ':[[:space:]]*//' || true)
violations=$(printf '%s' "$violations" | sed '/^$/d')

if [[ -n "$violations" ]]; then
  cat >&2 <<EOF
❌ ADR-010 D8 violation: NaturalLanguage import in a guarded layer.

   The natural-language framework must remain in App/ only. Engine /
   LLM / Models / Data consume language detection through the
   \`(any LanguageDetector)?\` protocol existential
   (\`Pastura/Pastura/LLM/LanguageDetector.swift\`); only the App-layer
   concrete \`NLLanguageDetector\` imports NaturalLanguage directly.

   See docs/decisions/ADR-010.md § D8 for the dependency-rule rationale.

EOF
  echo "$violations" >&2
  cat >&2 <<EOF

If the new usage is App-internal, file it under \`Pastura/Pastura/App/\`
rather than the guarded directories. If a future use case really
requires a lower-layer NaturalLanguage dependency, ADR-010 D8 needs an
explicit amendment before this guard is loosened.
EOF
  exit 1
fi

echo "✓ NaturalLanguage import boundary clean (Engine / LLM / Models / Data)."
