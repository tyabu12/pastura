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
  /// Thrown by ``LLMService/generate(system:user:)`` when a ``SuspendController``
  /// signals a suspend (for example because `scenePhase` transitioned to
  /// `.background` and iOS is about to deny GPU work). Unlike other cases,
  /// this is not a fatal failure — the calling layer is expected to await
  /// ``SuspendController/awaitResume()`` and retry the same prompt without
  /// consuming retry budget.
  case suspended
}
