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
  ///   - replacement: Replacement text for blocked content. Defaults to "***".
  init(blockedPatterns: [String] = ContentFilter.defaultPatterns, replacement: String = "***") {
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

  // MARK: - Default Patterns

  /// Minimum NG word list for App Store compliance.
  ///
  /// This is intentionally a small starter set. Expand as needed based on
  /// App Store review feedback and user reports.
  static let defaultPatterns: [String] = [
    // Violence
    "殺す", "殺害", "殺人",
    // Slurs / hate speech (Japanese)
    "死ね",
    // Profanity (English, common)
    "fuck", "shit", "asshole",
    // Discrimination
    "ガイジ", "キチガイ"
  ]
}
