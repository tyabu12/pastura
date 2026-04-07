import Foundation

/// Abstraction over LLM inference backends.
///
/// Implementations include ``OllamaService`` (development),
/// ``MockLLMService`` (testing), and a future LiteRT-LM service (production).
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
}
