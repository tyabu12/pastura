import Foundation

/// Abstraction over language-of-text detection for LLM output adherence checks.
///
/// Implementations classify a raw text snippet (typically the natural-language
/// fields of a parsed ``TurnOutput``) and return an ISO 639-1 lowercase code
/// (`"ja"`, `"en"`, …) or `nil` when the input is too short / too ambiguous
/// to classify above the implementation's confidence threshold.
///
/// The concrete production implementation lives in the App/ layer
/// (``NLLanguageDetector``, backed by Apple's `NLLanguageRecognizer`). Per
/// ADR-010 D8, `import NaturalLanguage` is forbidden in Engine / LLM / Models /
/// Data layers — only this abstraction crosses the boundary. ``LLMCaller``
/// consumes the protocol existential (`(any LanguageDetector)?`) so the
/// Engine layer remains framework-pure.
///
/// Why `Sendable`: the detector is threaded through ``SimulationRunner``'s
/// `init(detector:)` into ``ExecutionContext`` and ``PhaseContext``, both of
/// which are `Sendable` and cross the Task boundary into the inference loop.
nonisolated public protocol LanguageDetector: Sendable {
  /// Detect the dominant natural language of `text`.
  ///
  /// - Parameter text: The text to classify. Callers should join the
  ///   natural-language fields of a parsed ``TurnOutput`` (excluding
  ///   enum-constrained / option-bound fields whose values are
  ///   author-supplied tokens) before passing.
  /// - Returns: An ISO 639-1 lowercase code (e.g., `"ja"`, `"en"`), or
  ///   `nil` when the classification confidence falls below the
  ///   implementation's threshold. ``LLMCaller`` treats `nil` as
  ///   "skip the adherence check" rather than "mismatch".
  func detect(text: String) -> String?
}

/// Shared tuning defaults for ``LanguageDetector`` implementations.
///
/// This is a cross-implementation **parity** constant: both the production
/// concrete (``NLLanguageDetector`` in App/) and the headless harness concrete
/// (`HarnessLanguageDetector` in `tools/harness/`) read the confidence
/// threshold from here, so the `language_mismatch` metric a harness run reports
/// stays a faithful proxy for production behaviour when this value is revisited
/// (rather than drifting between two separate literals).
///
/// It carries **no** `NaturalLanguage` dependency — a plain `Double` — so it is
/// legal in the LLM/ layer under ADR-010 D8 (the guarded layers stay free of
/// `import NaturalLanguage`; only the abstraction crosses the boundary). It
/// ports to `commonMain` alongside the protocol per ADR-023 §4.
nonisolated public enum LanguageDetectionDefaults {
  /// Minimum top-hypothesis confidence for a detection result to be trusted.
  ///
  /// Below this, a detector returns `nil` so ``LLMCaller`` skips the adherence
  /// check rather than misclassifying a short / ambiguous output as a language
  /// mismatch. Initial value (Step E PR2); the benchmark harness records
  /// skip-rate to revisit in a follow-up if needed.
  public static let confidenceThreshold: Double = 0.5
}
