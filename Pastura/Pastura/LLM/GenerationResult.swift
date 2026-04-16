import Foundation

/// The output of an LLM inference call, including optional completion-token
/// metrics for tok/s computations.
///
/// `completionTokens` is `Int?` because not every backend surfaces the token
/// count: Ollama's OpenAI-compatible endpoint populates `usage.completion_tokens`
/// only on some versions/models, and the protocol default implementation
/// (which wraps the legacy `generate(system:user:)`) has no way to recover it.
/// Consumers that compute throughput should treat `nil` as "unknown" — exclude
/// such events from rolling averages rather than substituting zero.
nonisolated public struct GenerationResult: Sendable, Equatable {
  /// The raw text returned by the model.
  public let text: String

  /// Number of tokens the model generated in its response, if the backend reports it.
  public let completionTokens: Int?

  public init(text: String, completionTokens: Int? = nil) {
    self.text = text
    self.completionTokens = completionTokens
  }
}
