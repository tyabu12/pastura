import Foundation

/// Selects the literal matching `scenario.language` for Engine-side
/// per-site translation (ADR-010 D7).
///
/// Two-arm shape per ADR-010 Fallback rule (line 514–528):
/// `scenario.language` is mandatory (`ScenarioLoader` rejects absence)
/// and validator-gated to `{"ja", "en"}`, so the `default` arm covers
/// `"ja"` without a third defensive arm. No `@unknown default` —
/// that attribute is enum-only (SE-0192) and inapplicable to `String`
/// switches.
///
/// **Layer note (D8 normative):** Engine reads `scenario.language` only,
/// never `Bundle.main.preferredLocalizations`. This helper is intentionally
/// independent of `String(localized:)`, which would resolve against device
/// locale and break the cross-language goal in Step E.
///
/// The `ja` / `en` parameter names match `scenario.language` values
/// verbatim so callsites read as a Translation Table row (`identifier_name`
/// rule excludes both per `.swiftlint.yml`).
nonisolated func pickLanguage(_ language: String, ja: String, en: String) -> String {
  switch language {
  case "en":
    return en
  default:
    return ja
  }
}
