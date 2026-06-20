import Foundation
import Yams

/// Light-touch language extraction from a `ScenarioRecord`'s stored YAML.
///
/// A Yams-based reader for App-layer consumers that need the `language` of a
/// stored scenario when they only hold raw YAML and not a parsed `Scenario`.
/// Reads only the top-level `language` key via `Yams.load`.
///
/// As of #679 the Home / Past Results variant-collapse paths read the
/// denormalized ``ScenarioSummary/language`` column instead, so this type has
/// no production call-site on those paths; it remains the canonical reference
/// for the `"ja"`-fallback convention. Kept for any future raw-YAML consumer.
///
/// **Failure mode**: parse failures and missing `language` keys return
/// `"ja"` (Phase 1 convention) so the consumer's row stays visible
/// rather than silently disappearing. Stored YAML language is mandatory
/// per ADR-010 D1, so production records should always parse cleanly —
/// the fallback is defensive.
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
