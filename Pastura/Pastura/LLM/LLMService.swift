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
  ///           ``LLMError/generationFailed(description:)`` on inference failure,
  ///           ``LLMError/suspended`` if a ``SuspendController`` interrupted
  ///           the call (caller should await resume and retry).
  func generate(system: String, user: String) async throws -> String

  /// Attach a ``SuspendController`` so an in-flight ``generate(system:user:)``
  /// can be interrupted from outside the LLM layer.
  ///
  /// Default implementation is a no-op: backends that cannot honour suspend
  /// semantics (such as ``MockLLMService`` and ``OllamaService``) simply
  /// ignore the controller. ``LlamaCppService`` overrides this to wire the
  /// controller into its auto-regressive generate loop.
  ///
  /// - Important: Must be called before the first ``generate(system:user:)``
  ///   in a session. Re-attaching during an in-flight generate is undefined
  ///   behaviour.
  ///
  /// - Parameter controller: The controller this service should consult for
  ///   suspend signals. Pass `nil` to detach.
  func attachSuspendController(_ controller: SuspendController?) async

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
  /// Default no-op so existing implementations need no changes. Backends that
  /// support cooperative suspend (currently only ``LlamaCppService``) override
  /// this method.
  public func attachSuspendController(_ controller: SuspendController?) async {}
}
