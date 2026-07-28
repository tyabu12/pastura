import Foundation

/// Selects the literal matching the effective Engine language for
/// per-site translation (ADR-010 D7). Callers pass
/// `scenario.engineLanguage` (D5 / D6 row 1), which resolves
/// `simulationLanguage ?? language`.
///
/// Two-arm shape per ADR-010 Fallback rule (line 514–528):
/// `scenario.language` and `scenario.simulationLanguage` are both
/// validator-gated to `{"ja", "en"}` (the latter also accepts `nil`),
/// so the resolved string is effectively `{"ja", "en"}` and the
/// `default` arm covers `"ja"` without a third defensive arm. No
/// `@unknown default` — that attribute is enum-only (SE-0192) and
/// inapplicable to `String` switches.
///
/// **Layer note (D8 normative):** Engine reads `scenario.engineLanguage`
/// only, never `Bundle.main.preferredLocalizations`. This helper is
/// intentionally independent of any device-locale string lookup, which
/// would resolve against the device locale and break the cross-language
/// goal.
///
/// The `ja` / `en` parameter names match the resolved language values
/// verbatim so callsites read as a Translation Table row
/// (`identifier_name` rule excludes both per `.swiftlint.yml`).
///
/// **Every literal passed here has a twin in the ADR-023 Kotlin port**
/// (`shared/engine/src/commonMain/**`), which renders the same prompt so
/// the two engines stay behaviour-comparable. Editing one side only is a
/// silent half-change; `scripts/check-prompt-literal-parity.py` gates it
/// (pre-commit + CI). See `.claude/rules/engine.md` § "Prompt literals are
/// paired with the Kotlin port" for the allowlist procedure and for what
/// the gate cannot see.
nonisolated func pickLanguage(_ language: String, ja: String, en: String) -> String {
  switch language {
  case "en":
    return en
  default:
    return ja
  }
}
