import Foundation
import NaturalLanguage

/// Apple `NLLanguageRecognizer`-backed implementation of ``LanguageDetector``.
///
/// Lives in App/ because `import NaturalLanguage` is forbidden in Engine /
/// LLM / Models / Data layers per ADR-010 D8. The dependency direction is
/// App → LLM (protocol) → Engine (consumes via `(any LanguageDetector)?`),
/// so the natural-language framework never leaks across the dependency-rule
/// boundary.
///
/// Implementation notes:
///
/// - Each `detect(text:)` call constructs a fresh `NLLanguageRecognizer`.
///   Reusing a single recognizer would require calling `reset()` between
///   calls (state otherwise accumulates across `processString` invocations)
///   and would introduce thread-safety concerns; per-call allocation is
///   negligible vs. the cost of the LLM inference whose output we are
///   classifying.
///
/// - Confidence threshold: top-hypothesis confidence must be ≥ 0.5 for the
///   result to be returned. Below threshold, the detector returns `nil` so
///   ``LLMCaller`` skips the adherence check rather than misclassifying a
///   short / ambiguous output as a language mismatch (initial value; the
///   benchmark harness in Step E PR2 item 6 records skip-rate to revisit
///   in a follow-up if needed).
///
/// - The recognizer's `languageHints` and `languageConstraints` are
///   intentionally left at defaults — pinning to `[.japanese, .english]`
///   would skew confidence on cross-language drift cases (the very cases
///   the adherence check exists to catch).
nonisolated public final class NLLanguageDetector: LanguageDetector {
  private static let confidenceThreshold: Double = 0.5

  /// Creates a detector with the default confidence threshold (0.5).
  public init() {}

  public func detect(text: String) -> String? {
    guard !text.isEmpty else { return nil }
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
    guard
      let (language, confidence) = hypotheses.first,
      confidence >= Self.confidenceThreshold
    else {
      return nil
    }
    return language.rawValue
  }
}
