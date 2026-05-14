import Foundation

/// Device-locale-derived language seed for new-data creation seams.
///
/// Per ADR-010 D2: returns `"ja"` when the device's effective Pastura
/// locale is Japanese, otherwise `"en"`. The "effective Pastura locale"
/// is the value Apple's resolver returns given Pastura's
/// `knownRegions = {en, ja}` and the device's `preferredLanguages` —
/// `Bundle.main.preferredLocalizations` already does the narrowing.
///
/// **Layer policy (D8 normative):** this type MUST NOT be referenced
/// from `Engine/`, `LLM/`, `Models/`, or `Data/`. The Engine reads
/// `scenario.language` only — never the device locale. Callsites live
/// in the App / Views layers: editor seed for newly-authored scenarios,
/// preset picker initial-variant selection, etc. The DoD 10 grep guard
/// (`PasturaTests/`) enforces this at test time.
///
/// **Scope (D2):** seeds *new-data creation* and *multi-variant selection*
/// — never fills missing fields in stored YAML. D1's mandatory rule
/// applies to YAML; absence there is a validation error, not a default.
enum LocaleResolver {
  /// Resolves the device-effective default scenario language.
  ///
  /// - Parameter preferredLocalizations: Override for unit tests. Production
  ///   callsites pass `Bundle.main.preferredLocalizations` (the default).
  /// - Returns: `"ja"` if the effective first localization is Japanese,
  ///   otherwise `"en"`. Empty list and unsupported codes fall back to
  ///   `"en"` — the App Store launch target.
  static func deviceDefault(
    preferredLocalizations: [String] = Bundle.main.preferredLocalizations
  ) -> String {
    switch preferredLocalizations.first {
    case "ja":
      return "ja"
    default:
      return "en"
    }
  }
}
