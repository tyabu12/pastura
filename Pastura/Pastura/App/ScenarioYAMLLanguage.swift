import Foundation
import Yams

/// Light-touch language extraction from a `ScenarioRecord`'s stored YAML.
///
/// Used by App-layer consumers that need to know the `language` of a
/// stored scenario without invoking the full ``ScenarioLoader`` schema
/// gate. Reads only the top-level `language` key via `Yams.load`.
/// Current call-sites: ``HomeViewModel/presetsResolvedForLanguage(_:deviceLanguage:)``
/// (ADR-010 D6 preset variant collapsing) and ``ResultsViewModel``
/// (cross-language section-header selection, #392).
///
/// **Failure mode**: parse failures and missing `language` keys return
/// `"ja"` (Phase 1 convention) so the consumer's row stays visible
/// rather than silently disappearing. Stored YAML language is mandatory
/// per ADR-010 D1, so production records should always parse cleanly —
/// the fallback is defensive.
///
/// **Performance**: per-record Yams parse is O(yamlLength) but only the
/// top-level mapping is needed. Call-sites bound the call count
/// (≤ 8 preset rows on Home; ≤ 2-3 variants per canonical group in
/// Past Results) so caching is unnecessary.
nonisolated public enum ScenarioYAMLLanguage {
  /// Returns the YAML's top-level `language` value as a `String`,
  /// falling back to `"ja"` for any parse failure, missing key, or
  /// non-string value.
  public static func parse(_ yaml: String) -> String {
    guard
      let root = try? Yams.load(yaml: yaml) as? [String: Any],
      let language = root["language"] as? String
    else {
      return "ja"
    }
    return language
  }
}
