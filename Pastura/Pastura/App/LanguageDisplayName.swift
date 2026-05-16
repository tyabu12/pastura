import Foundation

/// Locale-aware resolver for ISO 639-1 language codes used by ADR-010's
/// adherence surface.
///
/// Maps `"ja"` / `"en"` to localized display names so the
/// `.languageMismatch` toast and badge VoiceOver fragment read
/// "drifted to Japanese (expected English)" rather than the
/// user-hostile raw codes that the Engine plumbs through.
///
/// Returns the `"Unknown language"` fallback for any code outside the
/// bounded set — Phase 2's `engineLanguage` is restricted to `"ja"` /
/// `"en"` per ADR-010 D1, so the fallback should not surface in
/// production. Kept defensive for forward-compat with the third-language
/// extension path noted in ADR-010 §Out-of-Scope.
enum LanguageDisplayName {
  static func resolve(_ code: String) -> String {
    switch code {
    case "ja": return String(localized: "Japanese")
    case "en": return String(localized: "English")
    default: return String(localized: "Unknown language")
    }
  }
}
