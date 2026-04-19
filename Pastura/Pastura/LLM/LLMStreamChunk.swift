import Foundation

/// A single incremental slice of output from ``LLMService/generateStream(system:user:)``.
///
/// Streams are delivered as a sequence of chunks; concatenating every
/// chunk's ``delta`` reconstructs the complete response text. Exactly one
/// chunk per stream has ``isFinal`` set to `true` — it is always the last
/// chunk the consumer observes.
///
/// Only three fields are exposed. Backend-specific details (token IDs,
/// timing, sampling stats) are deliberately excluded so a future migration
/// from llama.cpp to LiteRT-LM (ADR-002 §8) does not force a protocol
/// change. See ADR-002 §10 (streaming extension) for the rationale.
///
/// - Note: ``completionTokens`` is populated **only** on the final chunk
///   and only when the backend can cheaply report it. `nil` means
///   "unknown throughput" and callers should exclude the inference from
///   token-per-second averages rather than substituting zero.
nonisolated public struct LLMStreamChunk: Sendable, Equatable {
  /// Incremental text delivered by this chunk. May be empty (for example,
  /// a backend may emit a final chunk solely to report
  /// ``completionTokens``). Callers that append chunks linearly handle
  /// empty deltas transparently.
  public let delta: String

  /// `true` on the single terminal chunk of a stream, `false` on every
  /// preceding chunk. Once a consumer sees `isFinal == true`, no further
  /// chunks arrive in the same stream.
  public let isFinal: Bool

  /// Number of generated tokens for the whole stream. Populated only on
  /// the final chunk, and only for backends that track this cheaply
  /// (today: ``LlamaCppService`` via its sampler loop). `nil` everywhere
  /// else, including on all non-final chunks.
  public let completionTokens: Int?

  public init(delta: String, isFinal: Bool, completionTokens: Int?) {
    self.delta = delta
    self.isFinal = isFinal
    self.completionTokens = completionTokens
  }
}
