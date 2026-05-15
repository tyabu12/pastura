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
/// intentionally independent of `String(localized:)`, which would
/// resolve against device locale and break the cross-language goal.
///
/// The `ja` / `en` parameter names match the resolved language values
/// verbatim so callsites read as a Translation Table row
/// (`identifier_name` rule excludes both per `.swiftlint.yml`).
nonisolated func pickLanguage(_ language: String, ja: String, en: String) -> String {
  switch language {
  case "en":
    return en
  default:
    return ja
  }
}
