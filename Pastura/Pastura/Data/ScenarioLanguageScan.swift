import Foundation

/// Extracts the top-level `language:` value from a scenario YAML via a
/// **line scan**, deliberately NOT a full Yams parse.
///
/// The Data layer must depend on Models only (CLAUDE.md Dependency Rules), so
/// it cannot `import Yams`. This helper exists solely to denormalize ADR-010
/// D1's mandatory YAML `language` field into the `scenarios.language` column —
/// at the v8 migration backfill and as a repository save-time backstop — using
/// only `Foundation` string operations.
///
/// App-layer consumers that already hold a parsed `Scenario` should read
/// `Scenario.language` directly; ``ScenarioYAMLLanguage`` (App layer) remains
/// the Yams-based reader for the few callers that only have raw YAML.
nonisolated public enum ScenarioLanguageScan {
  /// Returns the value of the **column-0** `language:` key, or `nil` when no
  /// such key is present (the caller applies its own fallback).
  ///
  /// Anchored at column 0 so an indented (nested) `language:` inside a persona
  /// or `extraData` block is ignored, and matched on the **exact** key so the
  /// prefix-colliding top-level `simulation_language:` (ADR-010 D5) never
  /// satisfies it. Surrounding quotes on the value are stripped.
  public static func topLevelLanguage(in yaml: String) -> String? {
    for rawLine in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = String(rawLine)
      // Top-level keys start at column 0 — any leading whitespace means the
      // key is nested (a persona field, an extraData value, …).
      guard let first = line.first, !first.isWhitespace else { continue }
      guard let colonIndex = line.firstIndex(of: ":") else { continue }
      // Exact-key match: rejects `simulation_language:` and `languages:`.
      guard line[line.startIndex..<colonIndex] == "language" else { continue }
      let rawValue = line[line.index(after: colonIndex)...]
      // Drop a trailing YAML inline comment (a `#` preceded by whitespace) so
      // `language: en  # note` yields `en`, not `en  # note`.
      let withoutComment = rawValue.range(of: " #").map { rawValue[..<$0.lowerBound] } ?? rawValue
      let value =
        withoutComment
        .trimmingCharacters(in: .whitespaces)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
      return value.isEmpty ? nil : value
    }
    return nil
  }
}
