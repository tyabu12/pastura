import Foundation

/// Abstraction over LLM inference backends.
///
/// Implementations include ``LlamaCppService`` (on-device via llama.cpp),
/// ``OllamaService`` (development), and ``MockLLMService`` (testing).
/// The Engine layer depends on this protocol, never on concrete implementations.
nonisolated public protocol LLMService: Sendable {
  /// Load the model into memory. Call before ``generate(system:user:schema:)``.
  ///
  /// - Throws: ``LLMError/loadFailed(description:)`` if the model cannot be loaded.
  func loadModel() async throws

  /// Unload the model from memory to free resources.
  ///
  /// Safe to call even if no model is currently loaded.
  func unloadModel() async throws

  /// Whether a model is currently loaded and ready for inference.
  var isModelLoaded: Bool { get }

  /// Generate a completion from the given system and user prompts, optionally
  /// constrained by an ``OutputSchema``.
  ///
  /// - Parameters:
  ///   - system: The system prompt defining the agent's persona and rules.
  ///   - user: The user prompt with context and instructions for this turn.
  ///   - schema: Optional output schema constraining the JSON shape.
  ///     Backends translate this to their native constrained-decoding
  ///     mechanism (llama.cpp: GBNF grammar, Ollama: `format:"json"`,
  ///     Mock: recorded for tests). `nil` falls back to unconstrained
  ///     generation — same behaviour as before PR#b for existing
  ///     callers.
  ///   - antiRepetitionSeeds: Prior text spans (e.g. the agent's own previous
  ///     statement) a backend may down-weight at sampling time to suppress
  ///     cross-turn repetition — see ``antiRepetitionSeeds`` discussion on
  ///     the seam below. Only ``LlamaCppService`` acts on it (via a DRY
  ///     sampler seeded content-only, #1105); all other backends ignore it.
  ///     `[]` (the convenience-overload default) reproduces prior behaviour.
  /// - Returns: The raw text response from the LLM.
  /// - Throws: ``LLMError/notLoaded`` if model is not loaded,
  ///           ``LLMError/generationFailed(description:)`` on inference failure,
  ///           ``LLMError/suspended`` if a ``SuspendController`` interrupted
  ///           the call (caller should await resume and retry).
  func generate(
    system: String, user: String, schema: OutputSchema?,
    antiRepetitionSeeds: [String]
  ) async throws -> String

  /// Generate a completion and return it with optional token-count metrics.
  ///
  /// Backends that can cheaply report how many tokens they generated should
  /// override this to populate ``GenerationResult/completionTokens``. The
  /// default implementation wraps ``generate(system:user:schema:)`` and returns
  /// `nil` tokens — callers treat nil as "unknown throughput" and exclude
  /// such events from rolling averages.
  ///
  /// - Parameters:
  ///   - system: The system prompt defining the agent's persona and rules.
  ///   - user: The user prompt with context and instructions for this turn.
  ///   - schema: Optional output schema — same semantics as on
  ///     ``generate(system:user:schema:antiRepetitionSeeds:)``.
  ///   - antiRepetitionSeeds: Same semantics as on
  ///     ``generate(system:user:schema:antiRepetitionSeeds:)``.
  /// - Returns: A ``GenerationResult`` with the text and optional token count.
  /// - Throws: Same error domain as ``generate(system:user:schema:antiRepetitionSeeds:)``.
  func generateWithMetrics(
    system: String, user: String, schema: OutputSchema?,
    antiRepetitionSeeds: [String]
  ) async throws -> GenerationResult

  /// Attach a ``SuspendController`` so an in-flight inference can be
  /// interrupted from outside the LLM layer.
  ///
  /// Default implementation is a no-op: backends that cannot honour suspend
  /// semantics (such as ``MockLLMService`` and ``OllamaService``) simply
  /// ignore the controller. ``LlamaCppService`` overrides this to wire the
  /// controller into its auto-regressive generate loop.
  ///
  /// - Important: Must be called before the first inference in a session.
  ///   Re-attaching during an in-flight generate is undefined behaviour.
  ///
  /// - Parameter controller: The controller this service should consult for
  ///   suspend signals. Pass `nil` to detach.
  func attachSuspendController(_ controller: SuspendController?) async

  /// Human-readable label for the currently-loaded model — implementations
  /// typically derive this from backend-specific metadata (e.g. a
  /// `ModelDescriptor.displayName` for on-device services, a backend tag
  /// like `"gemma4:e2b"` for remote services, or a test sentinel like
  /// `"mock"`). Intended for display / export metadata — **not** a stable
  /// parse key.
  var modelIdentifier: String { get }

  /// Human-readable label for the backend runtime driving inference (e.g.
  /// `"llama.cpp"`, `"Ollama"`, `"mock"`). Intended for display / export
  /// metadata — **not** a stable parse key.
  var backendIdentifier: String { get }

  /// Every turn-marker pair whose **plaintext** form could plausibly appear in
  /// this backend's decoded output, for consumers that must recognize a
  /// hallucinated turn boundary (``JSONResponseParser`` truncation, the
  /// `LLMCaller` chat-template leakage diagnostic).
  ///
  /// The set is the loaded model's own pair **unioned with**
  /// ``ChatTurnMarkers/chatML``, so a backend that cannot name its model
  /// (``OllamaService``, ``MockLLMService``) keeps the pre-#1422 ChatML-only
  /// behaviour via the default implementation, and a ChatML model does not
  /// grow a second, redundant entry.
  ///
  /// - Important: Declared **in the protocol body**, not only in an extension.
  ///   An extension-only declaration is statically dispatched through
  ///   `any LLMService`, so ``LlamaCppService``'s override would be silently
  ///   ignored at the `LLMCaller` call site — with no diagnostic, and with the
  ///   exact failure this requirement exists to remove.
  var knownTurnMarkers: [ChatTurnMarkers] { get }

  /// Generate a completion as a sequence of incremental chunks.
  ///
  /// Backends that can deliver tokens as they are sampled (currently
  /// ``LlamaCppService``) override this for true token-by-token streaming.
  /// The default implementation wraps ``generateWithMetrics(system:user:schema:)``
  /// and yields a single terminal chunk with the full response — so
  /// backends that lack streaming (``MockLLMService``, ``OllamaService``)
  /// still satisfy the contract without custom code.
  ///
  /// Exactly one chunk per stream has ``LLMStreamChunk/isFinal`` set to
  /// `true` and it is always the last chunk observed. ``LLMStreamChunk/completionTokens``
  /// is populated only on that final chunk, and only when the backend can
  /// cheaply report it.
  ///
  /// Cancellation: the returned stream terminates on iterator cancellation
  /// (normal `AsyncThrowingStream` semantics). The default wrap cancels
  /// the in-flight `generate` task on iterator cancellation, but note
  /// that ``LlamaCppService`` cannot interrupt its C-API generate from
  /// Swift Task cancellation (ADR-002 §6) — use
  /// ``attachSuspendController(_:)`` for cooperative mid-inference stops.
  ///
  /// - Parameters:
  ///   - system: The system prompt defining the agent's persona and rules.
  ///   - user: The user prompt with context and instructions for this turn.
  ///   - schema: Optional output schema — same semantics as on
  ///     ``generate(system:user:schema:antiRepetitionSeeds:)``.
  ///   - antiRepetitionSeeds: Same semantics as on
  ///     ``generate(system:user:schema:antiRepetitionSeeds:)``. This is the
  ///     path the Engine actually drives (``LLMCaller`` consumes the stream),
  ///     so it is where ``LlamaCppService``'s DRY seeding takes effect (#1105).
  /// - Returns: An `AsyncThrowingStream` of ``LLMStreamChunk`` values.
  /// - Throws: Errors from the underlying `generate` call propagate
  ///   through the stream via `finish(throwing:)` — same error domain as
  ///   ``generate(system:user:schema:antiRepetitionSeeds:)``.
  func generateStream(
    system: String, user: String, schema: OutputSchema?,
    antiRepetitionSeeds: [String]
  ) -> AsyncThrowingStream<LLMStreamChunk, Error>
}

extension LLMService {
  /// Default implementation wraps ``generate(system:user:schema:)`` and reports
  /// no token count. Backends that have cheap access to the generation
  /// token count override this.
  public func generateWithMetrics(
    system: String, user: String, schema: OutputSchema?,
    antiRepetitionSeeds: [String]
  ) async throws -> GenerationResult {
    let text = try await generate(
      system: system, user: user, schema: schema,
      antiRepetitionSeeds: antiRepetitionSeeds)
    return GenerationResult(text: text, completionTokens: nil)
  }

  /// Default no-op so existing implementations need no changes. Backends that
  /// support cooperative suspend (currently only ``LlamaCppService``) override
  /// this method.
  public func attachSuspendController(_ controller: SuspendController?) async {}

  /// Default: ChatML only — the pre-#1422 hardcoded behaviour, now stated as a
  /// value rather than baked into each consumer. Backends that know which
  /// model is loaded override this (currently only ``LlamaCppService``).
  ///
  /// Explicitly `nonisolated` for the same reason as `generateStream` below:
  /// under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` this default impl
  /// otherwise inherits MainActor and blocks every `nonisolated` conformer.
  /// Not defensive — measured by dropping the annotation, which fails the
  /// build with `conformance of 'MockLLMService' to protocol 'LLMService'
  /// crosses into main actor-isolated code` (and the same for `OllamaService`).
  nonisolated public var knownTurnMarkers: [ChatTurnMarkers] { [.chatML] }

  /// Default `generateStream` implementation: runs the existing
  /// `generateWithMetrics` and yields a single terminal chunk carrying
  /// the full response. Backends that can deliver real token-by-token
  /// output override this (see ``LlamaCppService``).
  ///
  /// Explicitly `nonisolated` because the project sets
  /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; without it the default
  /// impl inherits MainActor isolation and blocks the nonisolated
  /// ``LlamaCppService`` conformance.
  nonisolated public func generateStream(
    system: String, user: String, schema: OutputSchema?,
    antiRepetitionSeeds: [String]
  ) -> AsyncThrowingStream<LLMStreamChunk, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let result = try await generateWithMetrics(
            system: system, user: user, schema: schema,
            antiRepetitionSeeds: antiRepetitionSeeds)
          continuation.yield(
            LLMStreamChunk(
              delta: result.text,
              isFinal: true,
              completionTokens: result.completionTokens))
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      // Propagate iterator cancellation to the underlying generate call so
      // abandoned streams don't leak a running inference task. For
      // backends whose `generate` can't actually be interrupted by Task
      // cancellation (llama.cpp), this at least cancels the surrounding
      // Swift Task so the yield attempt is short-circuited.
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

// MARK: - Convenience overloads (schema-less, and seed-less)

/// The 4-arg forms above (`…schema:antiRepetitionSeeds:`) are the protocol
/// requirements. Two families of convenience overloads keep existing call
/// sites unchanged:
///
/// - **Seed-less 3-arg** (`…schema:`) forwards to the 4-arg requirement with
///   `antiRepetitionSeeds: []` — the anti-repetition seeding (#1105) is opt-in,
///   so every caller that doesn't pass seeds gets the prior behaviour. Swift
///   protocol requirements cannot declare a default argument, so this overload
///   supplies the `[]` default the requirement can't.
/// - **Schema-less 2-arg** (`system:user:`) forwards to the 3-arg form with
///   `schema: nil`, preserving the pre-#194-PR#b call shape
///   (`llm.generate(system:, user:)`).
///
/// This keeps Engine, replay, and test call sites unchanged while letting the
/// handler layer opt into schema constraints and anti-repetition seeds
/// incrementally.
extension LLMService {
  public func generate(
    system: String, user: String, schema: OutputSchema?
  ) async throws -> String {
    try await generate(
      system: system, user: user, schema: schema, antiRepetitionSeeds: [])
  }

  public func generateWithMetrics(
    system: String, user: String, schema: OutputSchema?
  ) async throws -> GenerationResult {
    try await generateWithMetrics(
      system: system, user: user, schema: schema, antiRepetitionSeeds: [])
  }

  nonisolated public func generateStream(
    system: String, user: String, schema: OutputSchema?
  ) -> AsyncThrowingStream<LLMStreamChunk, Error> {
    generateStream(
      system: system, user: user, schema: schema, antiRepetitionSeeds: [])
  }

  public func generate(
    system: String, user: String
  ) async throws -> String {
    try await generate(system: system, user: user, schema: nil)
  }

  public func generateWithMetrics(
    system: String, user: String
  ) async throws -> GenerationResult {
    try await generateWithMetrics(system: system, user: user, schema: nil)
  }

  nonisolated public func generateStream(
    system: String, user: String
  ) -> AsyncThrowingStream<LLMStreamChunk, Error> {
    generateStream(system: system, user: user, schema: nil)
  }
}
