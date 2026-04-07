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
}
