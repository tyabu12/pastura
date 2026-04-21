import Foundation

/// Filters inappropriate content from agent outputs before display.
///
/// Applied in the App/ViewModel layer between Engine output and UI display.
/// Even in debug mode, displayed output is filtered (App Store compliance).
/// Raw (unfiltered) output is preserved in `TurnRecord.rawOutput`.
///
/// ContentFilter lives in App/ but is nonisolated + Sendable so it can be
/// used from both MainActor ViewModels and background tasks without friction.
nonisolated final class ContentFilter: Sendable {
  /// Words and phrases to filter. Case-insensitive matching.
  private let blockedPatterns: [String]

  /// The replacement string used when a blocked pattern is found.
  let replacement: String

  /// Creates a content filter with the given blocked patterns.
  ///
  /// - Parameters:
  ///   - blockedPatterns: Words/phrases to filter. Matched case-insensitively.
  ///     Defaults to the shared bundled blocklist (see ``ContentBlocklist``).
  ///   - replacement: Replacement text for blocked content. Defaults to "***".
  init(blockedPatterns: [String] = ContentBlocklist.defaultPatterns, replacement: String = "***") {
    self.blockedPatterns = blockedPatterns
    self.replacement = replacement
  }

  /// Filters a single string, replacing blocked patterns.
  func filter(_ text: String) -> String {
    var result = text
    for pattern in blockedPatterns {
      result = result.replacingOccurrences(
        of: pattern,
        with: replacement,
        options: [.caseInsensitive, .diacriticInsensitive]
      )
    }
    return result
  }

  /// Filters all displayable fields in a `TurnOutput`.
  ///
  /// Returns a new `TurnOutput` with filtered field values.
  func filter(_ output: TurnOutput) -> TurnOutput {
    let filtered = output.fields.mapValues { filter($0) }
    return TurnOutput(fields: filtered)
  }
}
