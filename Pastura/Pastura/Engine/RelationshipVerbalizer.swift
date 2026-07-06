import Foundation

/// Renders a perceiver's raw affinity row (`other name → score`) as a short
/// natural-language summary for injection into that agent's prompt.
///
/// Gemma 4 E2B cannot read a numeric matrix, so the `relationship_update`
/// phase surfaces its affinities as prose ("You are wary of Ryuji") rather
/// than raw numbers. Only relationships whose magnitude reaches
/// ``mentionThreshold`` are mentioned, keeping the injected text bounded even
/// as scores accumulate across rounds. Language is chosen by the scenario's
/// engine language (ja / en), matching every other prompt-side string (#910).
nonisolated enum RelationshipVerbalizer {
  /// Minimum absolute affinity score for a relationship to be verbalized.
  /// Below this the feeling is too weak to mention; the gate also caps the
  /// prompt-length growth a fully-connected matrix would otherwise cause.
  static let mentionThreshold = 2

  /// Summarizes `affinities` (`other name → accumulated score`) as prose in
  /// `language`. Mentions only entries with `abs(score) >= mentionThreshold`,
  /// sorted by name for deterministic output, and returns `""` when nothing
  /// crosses the threshold (the caller then injects an empty section).
  static func summarize(_ affinities: [String: Int], language: String) -> String {
    let notable =
      affinities
      .filter { abs($0.value) >= mentionThreshold }
      .sorted { $0.key < $1.key }
    guard !notable.isEmpty else { return "" }
    let clauses = notable.map { clause(other: $0.key, score: $0.value, language: language) }
    // ja sentences already carry a terminal 。 so they need no separator;
    // en sentences are space-separated.
    return clauses.joined(separator: pickLanguage(language, ja: "", en: " "))
  }

  private static func clause(other: String, score: Int, language: String) -> String {
    // `summarize` has already filtered to `abs(score) >= mentionThreshold`; the
    // warmth/wariness split is a pure sign test, decoupled from the magnitude gate.
    if score > 0 {
      return String(
        format: pickLanguage(
          language, ja: "%@ には好感を持っている。", en: "You feel warmly toward %@."),
        other)
    }
    return String(
      format: pickLanguage(
        language, ja: "%@ を警戒している。", en: "You are wary of %@."),
      other)
  }
}
