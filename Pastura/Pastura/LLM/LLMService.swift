import Foundation

/// Abstraction over LLM inference backends.
///
/// Implementations include ``LlamaCppService`` (on-device via llama.cpp),
/// ``OllamaService`` (development), and ``MockLLMService`` (testing).
/// The Engine layer depends on this protocol, never on concrete implementations.
nonisolated public protocol LLMService: Sendable {
  /// Load the model into memory. Call before ``generate(system:user:)``.
  ///
  /// - Throws: ``LLMError/loadFailed(description:)`` if the model cannot be loaded.
  func loadModel() async throws

  /// Unload the model from memory to free resources.
  ///
  /// Safe to call even if no model is currently loaded.
  func unloadModel() async throws

  /// Whether a model is currently loaded and ready for inference.
  var isModelLoaded: Bool { get }

  /// Generate a completion from the given system and user prompts.
  ///
  /// - Parameters:
  ///   - system: The system prompt defining the agent's persona and rules.
  ///   - user: The user prompt with context and instructions for this turn.
  /// - Returns: The raw text response from the LLM.
  /// - Throws: ``LLMError/notLoaded`` if model is not loaded,
  ///           ``LLMError/generationFailed(description:)`` on inference failure.
  func generate(system: String, user: String) async throws -> String

  /// Generate a completion and return it with optional token-count metrics.
  ///
  /// Backends that can cheaply report how many tokens they generated should
  /// override this to populate ``GenerationResult/completionTokens``. The
  /// default implementation wraps ``generate(system:user:)`` and returns
  /// `nil` tokens — callers treat nil as "unknown throughput" and exclude
  /// such events from rolling averages.
  ///
  /// - Parameters:
  ///   - system: The system prompt defining the agent's persona and rules.
  ///   - user: The user prompt with context and instructions for this turn.
  /// - Returns: A ``GenerationResult`` with the text and optional token count.
  /// - Throws: Same error domain as ``generate(system:user:)``.
  func generateWithMetrics(system: String, user: String) async throws -> GenerationResult

  /// Human-readable label for the currently-loaded model (e.g.
  /// `"Gemma 4 E2B (Q4_K_M)"`, `"gemma4:e2b"`, `"mock"`). Intended for
  /// display / export metadata — **not** a stable parse key.
  var modelIdentifier: String { get }

  /// Human-readable label for the backend runtime driving inference (e.g.
  /// `"llama.cpp"`, `"Ollama"`, `"mock"`). Intended for display / export
  /// metadata — **not** a stable parse key.
  var backendIdentifier: String { get }
}

extension LLMService {
  /// Default implementation wraps ``generate(system:user:)`` and reports
  /// no token count. Backends that have cheap access to the generation
  /// token count override this.
  public func generateWithMetrics(
    system: String, user: String
  ) async throws -> GenerationResult {
    let text = try await generate(system: system, user: user)
    return GenerationResult(text: text, completionTokens: nil)
  }
}
