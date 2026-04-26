import Foundation

/// Errors specific to the LLM inference layer.
///
/// Each case stores a `String` description rather than wrapping `Error` directly,
/// ensuring `Sendable` and `Equatable` conformance for safe cross-actor use.
nonisolated public enum LLMError: Error, Sendable, Equatable {
  /// The model failed to load from disk or network.
  case loadFailed(description: String)

  /// Text generation failed during inference.
  case generationFailed(description: String)

  /// An operation was attempted before the model was loaded.
  case notLoaded

  /// The LLM response could not be parsed as valid JSON.
  case invalidResponse(raw: String)

  /// The HTTP request to the LLM backend failed.
  case networkError(description: String)

  /// Inference was interrupted by an external suspend request and may be retried.
  ///
  /// Thrown by ``LLMService/generate(system:user:schema:)`` when a ``SuspendController``
  /// signals a suspend (for example because `scenePhase` transitioned to
  /// `.background` and iOS is about to deny GPU work). Unlike other cases,
  /// this is not a fatal failure — the calling layer is expected to await
  /// ``SuspendController/awaitResume()`` and retry the same prompt without
  /// consuming retry budget.
  case suspended

  /// The ``GBNFGrammarBuilder`` produced a grammar string that the
  /// backend's grammar parser rejected, or the builder itself threw a
  /// validation error (empty enumeration / duplicate field / invalid
  /// rule name). This is a caller-side / engineering bug, not a runtime
  /// LLM failure — `LLMCaller` treats it as fail-fast and **does not
  /// consume retry budget**, so a deterministic builder defect surfaces
  /// as a single clear error instead of 3× flaky-inference retries
  /// (#194 PR#b Item 4 / critic Axis 11).
  case invalidGrammar(description: String)
}

/// Provides human-readable descriptions so UI alert handlers can show
/// `error.localizedDescription` without mapping each case manually.
extension LLMError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .loadFailed(let description):
      return String(localized: "Model load failed: \(description)")
    case .generationFailed(let description):
      return String(localized: "Generation failed: \(description)")
    case .notLoaded:
      return String(localized: "Model not loaded")
    case .invalidResponse(let raw):
      let snippet = raw.count > 200 ? String(raw.prefix(200)) + "..." : raw
      return String(localized: "Invalid LLM response: \(snippet)")
    case .networkError(let description):
      return String(localized: "Network error: \(description)")
    case .suspended:
      return String(localized: "Inference was suspended and will retry")
    case .invalidGrammar(let description):
      return String(localized: "Invalid grammar for constrained decoding: \(description)")
    }
  }
}
