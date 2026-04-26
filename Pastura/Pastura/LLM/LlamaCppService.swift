// swiftlint:disable file_length
// Deliberately long: LlamaCppService owns sequential-access contract, chat
// template, sampler / prefill / suspend wiring, the non-streaming generate
// loop, AND the streaming variant. Streaming lives here (not in a +Stream
// extension) because it touches private _model / _context / generatingGuard
// that must stay private to enforce the sequential-access invariant
// (ADR-002 §6). Splitting into a separate file would require relaxing that
// access.
import Foundation
import LlamaSwift
import os

/// On-device LLM backend using llama.cpp with Metal GPU acceleration.
///
/// Loads a GGUF model file from disk and runs inference locally.
/// Designed for TestFlight production use with Gemma 4 E2B.
///
/// - Important: Sequential-access contract (ADR-002 §6) — concurrent calls
///   into `generate()` / `generateStream()` are serialized via an atomic
///   wait-and-claim primitive (`acquireGenerateGuard` in `+Lifecycle.swift`),
///   not crashed. The Engine still runs inferences sequentially in the
///   normal case; the contract is enforced cooperatively rather than via a
///   runtime trap. `loadModel()` / `unloadModel()` use the related
///   `awaitGenerateIdle` primitive (waits without claiming).
/// - Note: All four entry points handle the case where llama.cpp's C API
///   cannot be interrupted by Swift `Task` cancellation. The prior call
///   runs to its next iteration boundary before the next call's wait-and-
///   claim succeeds. Bounded by a 30-second deadline. (Issue #221.)
nonisolated public final class LlamaCppService: LLMService, @unchecked Sendable {
  // @unchecked Sendable: isModelLoaded flag protected by OSAllocatedUnfairLock.
  // C pointers use nonisolated(unsafe) — Engine calls generate() sequentially via
  // `for await` on a single AsyncStream, and loadModel()/unloadModel() bracket the
  // stream lifetime, guaranteeing no concurrent access to C pointers (ADR-002 §6).

  private let modelPath: String
  let logger = Logger(subsystem: "com.pastura", category: "LlamaCppService")

  #if DEBUG
    // Per-loop token-level checkpoint logger. Joins the shared
    // `category:StreamingDiag` channel (see `Engine/LLMCaller.swift`,
    // `App/SimulationViewModel.swift`) so the existing analyze script
    // and Console.app filter recipe pick it up. Routed through a
    // dedicated static logger rather than the file-level `logger`
    // because `LlamaCppService`'s normal log noise (load/unload,
    // template-apply, etc.) would otherwise drown the checkpoints.
    //
    // **DEBUG-only** because the `~5 entries / 100 tokens` rate is
    // useful for postmortem on the rare accept-time abort
    // (ADR-002 §12.9) but is gratuitous noise on release builds where
    // we have no field-side log-collection mechanism. Reproduce in
    // DEBUG when the abort is reported by a TestFlight crash report.
    static let streamingDiagLogger = Logger(
      subsystem: "com.pastura", category: "StreamingDiag")

    /// Periodic streaming-diag checkpoint emitter — see ADR-002 §12.9.
    /// Emits a `streamCheckpoint` line every 20 generated tokens with the
    /// most recent ~40-char decoded tail. Postmortem on the rare
    /// accept-time abort uses the most recent checkpoint before the
    /// crash to localize the JSON position (mid-string? after `}`?
    /// in `trailing`?) where EOG was sampled. Extracted as a helper to
    /// keep the inline check from pushing `runGeneration` /
    /// `runStreamGeneration` past swiftlint's cyclomatic_complexity cap.
    func emitStreamingCheckpointIfDue(
      mode: String, tokens: Int, tail: String
    ) {
      guard tokens > 0, tokens.isMultiple(of: 20) else { return }
      Self.streamingDiagLogger.debug(
        "streamCheckpoint mode=\(mode, privacy: .public) tokens=\(tokens) tail=\(tail, privacy: .public)"
      )
    }
  #endif

  // Sampling parameters (ADR-002 §6, matching OllamaService)
  static let temperature: Float = 0.8
  static let maxTokens: Int = 1_000
  static let topK: Int32 = 40
  static let topP: Float = 0.95
  static let repeatPenalty: Float = 1.1
  static let contextSize: UInt32 = 8_192
  static let batchSize: Int = 512
  // Per-instance stop sequence (was `static` pre-multi-model). String-based,
  // not token-ID, because Gemma 4 E2B tokenizes `<|im_end|>` into 6 subword
  // tokens — single-token ID matching is impossible for this model. Gemma
  // and Qwen 3 both use `<|im_end|>`; future models may differ (read from
  // descriptor at construction time).
  // TODO: Consider adding `<|im_start|>` if hallucinated turn starts are observed (#65)
  let stopSequence: String

  /// Optional suffix appended to the system prompt at chat-template assembly.
  /// Used for models that require prompt-level mode control (e.g., Qwen's
  /// `/no_think` to disable thinking mode). `nil` for models that need no
  /// suffix.
  let systemPromptSuffix: String?

  private let loadedState: OSAllocatedUnfairLock<Bool>
  // Synchronizing fence for the sequential-access contract (ADR-002 §6).
  // generate() / generateStream() acquire this via acquireGenerateGuard
  // (atomic wait-and-claim); load / unload wait via awaitGenerateIdle
  // (no claim — they have their own loadedState). Holding the claim is
  // the primary guarantee that pointer ownership stays with the current
  // call: pointer capture happens AFTER the claim, and unloadModel waits
  // behind the same flag — so no concurrent free can race the captured
  // _model / _context pointers. Concurrent generate() callers are
  // serialized via the wait-and-claim loop rather than crashed.
  private let generatingGuard = OSAllocatedUnfairLock<Bool>(initialState: false)

  /// Whether a `generate()` call is currently in flight.
  /// Exposed so the +Lifecycle extension can poll without direct lock access.
  func isGenerating() -> Bool {
    generatingGuard.withLock { $0 }
  }

  /// Atomic check-and-set: returns `true` iff this call transitioned the
  /// flag from clear to claimed. Used by `acquireGenerateGuard` in
  /// `+Lifecycle.swift` — exposed at file-internal scope because the
  /// `private` `generatingGuard` is invisible to cross-file extensions.
  func tryClaimGeneratingGuard() -> Bool {
    generatingGuard.withLock { flag in
      if flag { return false }
      flag = true
      return true
    }
  }

  /// Force-claim the guard regardless of current state. Used only by
  /// `acquireGenerateGuard`'s 30 s timeout path — see ADR-002 §12.6 for
  /// the safety trade-off (degrade safety over a permanent hang).
  func forceClaimGeneratingGuard() {
    generatingGuard.withLock { $0 = true }
  }

  #if DEBUG
    /// Test-only hook for exercising the `awaitGenerateIdle` wait path.
    /// Must never be called from production code — flipping this flag during
    /// a real `generate()` call breaks the sequential-access contract.
    func setGeneratingForTesting(_ value: Bool) {
      generatingGuard.withLock { $0 = value }
    }
  #endif
  // Sequential access only — protected by concurrency contract, not by lock
  nonisolated(unsafe) private var _model: OpaquePointer?
  nonisolated(unsafe) private var _context: OpaquePointer?
  // Suspend signal source. Read in the generate/prefill auto-regressive loops
  // at iteration boundaries to convert an external suspend request into a
  // prompt `LLMError.suspended` throw. Same sequential access contract as
  // `_model` / `_context` (ADR-002 §6) — `attachSuspendController` must not
  // race with an in-flight `generate()`.
  nonisolated(unsafe) var suspendController: SuspendController?

  /// Creates a llama.cpp service.
  ///
  /// All parameters are required — callers must provide explicit per-descriptor
  /// values (via `ModelDescriptor.stopSequence` / `.displayName` /
  /// `.systemPromptSuffix`). This avoids silently running Qwen with Gemma's
  /// defaults if a call-site forgets to thread the descriptor through.
  /// Test code can construct via a file-scope helper (see
  /// `LlamaCppServiceTests`) to centralize the Gemma-shaped test values.
  ///
  /// - Parameters:
  ///   - modelPath: Absolute path to the GGUF model file on disk (provided by
  ///     `ModelManager.modelFileURL(for:).path` at the call-site).
  ///   - stopSequence: Per-model stop sentinel (e.g., `<|im_end|>`).
  ///   - modelIdentifier: Human-readable label for exports / replay metadata.
  ///   - systemPromptSuffix: Optional suffix appended to the system prompt
  ///     at `applyChatTemplate` (e.g., `/no_think` for Qwen 3).
  public init(
    modelPath: String,
    stopSequence: String,
    modelIdentifier: String,
    systemPromptSuffix: String?
  ) {
    self.modelPath = modelPath
    self.stopSequence = stopSequence
    self.modelIdentifier = modelIdentifier
    self.systemPromptSuffix = systemPromptSuffix
    self.loadedState = OSAllocatedUnfairLock(initialState: false)
    // Install llama.cpp's C-runtime log capture once — routes grammar
    // parse errors ("invalid character", "expected ::=", etc.) into
    // Console.app under subsystem:com.pastura category:LlamaCppRuntime.
    // Idempotent at the C API level; safe to re-invoke per instance.
    _ = Self.logCaptureInstalled
  }

  /// One-shot log-capture hook installed via `llama_log_set`. Referenced
  /// from `init` so the first service construction triggers installation;
  /// subsequent references are a no-op.
  private static let logCaptureInstalled: Void = {
    llama_log_set(
      { level, text, _ in
        guard let text else { return }
        let message = String(cString: text).trimmingCharacters(
          in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        let logger = Logger(
          subsystem: "com.pastura", category: "LlamaCppRuntime")
        switch level {
        case GGML_LOG_LEVEL_ERROR:
          logger.error("\(message, privacy: .public)")
        case GGML_LOG_LEVEL_WARN:
          logger.warning("\(message, privacy: .public)")
        case GGML_LOG_LEVEL_DEBUG:
          logger.debug("\(message, privacy: .public)")
        default:
          logger.info("\(message, privacy: .public)")
        }
      }, nil)
  }()

  deinit {
    // Safety net: free C resources if still loaded.
    if loadedState.withLock({ $0 }) {
      if let ctx = _context { llama_free(ctx) }
      if let mdl = _model { llama_model_free(mdl) }
      llama_backend_free()
    }
  }

  // MARK: - LLMService

  /// Loads the GGUF model with full GPU acceleration.
  ///
  /// - Important: Idempotent — if a model is already loaded, it is unloaded
  ///   before the new load. Prevents a ~3GB buffer leak when concurrent
  ///   navigation / BG-task lifecycle races re-enter this method (issue #114).
  ///
  /// - Note: On double-call, the prior loaded model is freed before the new
  ///   load is attempted. If the new load fails, the service ends in a clean
  ///   not-loaded state — callers must not assume a prior successful load
  ///   survives a subsequent failed `loadModel()`.
  ///
  /// - Note: Any attached ``SuspendController`` is preserved across the
  ///   unload/load cycle via `defer`, matching ``reloadModel(gpuAcceleration:)``.
  public func loadModel() async throws {
    let preservedController = suspendController
    defer { suspendController = preservedController }
    try await unloadModel()
    try await loadModelInternal(gpuAcceleration: .full)
  }

  /// Unloads the current model (if any) and reloads with the specified GPU acceleration.
  ///
  /// Used to switch between full-GPU and CPU-only inference at runtime,
  /// primarily for background execution (iOS 26 BGContinuedProcessingTask) where
  /// GPU access may not be available.
  ///
  /// - Important: Must be called between `generate()` calls, not concurrently.
  ///   The sequential access contract (ADR-002 §6) is enforced by `generatingGuard`.
  ///   Callers (e.g., `BackgroundSimulationManager`) must pause the simulation and
  ///   wait for any in-flight inference to complete before calling this.
  ///
  /// - Note: Reload takes several seconds — the model file is re-read from disk
  ///   and buffers are re-allocated. Each `generate()` call clears the KV cache,
  ///   so no inference state is lost across reloads.
  ///
  /// - Note: Any attached ``SuspendController`` is preserved across the
  ///   unload/reload cycle, so the App layer can keep using the same
  ///   reference. This is enforced via `defer` so the preservation also
  ///   holds on failure paths (e.g., the new load throws).
  ///
  /// - Parameter gpuAcceleration: Desired GPU acceleration mode for the new load.
  public func reloadModel(gpuAcceleration: GPUAcceleration) async throws {
    let preservedController = suspendController
    defer { suspendController = preservedController }
    try await unloadModel()
    try await loadModelInternal(gpuAcceleration: gpuAcceleration)
  }

  private func loadModelInternal(gpuAcceleration: GPUAcceleration) async throws {
    await awaitGenerateIdle(caller: "loadModel")

    // llama_backend_init is internally ref-counted — safe to call multiple times
    llama_backend_init()

    var modelParams = llama_model_default_params()
    modelParams.n_gpu_layers = gpuAcceleration.nGpuLayers

    guard let model = llama_model_load_from_file(modelPath, modelParams) else {
      llama_backend_free()
      throw LLMError.loadFailed(description: "Failed to load model from \(modelPath)")
    }

    var ctxParams = llama_context_default_params()
    ctxParams.n_ctx = Self.contextSize
    ctxParams.n_batch = UInt32(Self.batchSize)

    guard let context = llama_init_from_model(model, ctxParams) else {
      llama_model_free(model)
      llama_backend_free()
      throw LLMError.loadFailed(description: "Failed to create inference context")
    }

    _model = model
    _context = context
    loadedState.withLock { $0 = true }
  }

  public func unloadModel() async throws {
    await awaitGenerateIdle(caller: "unloadModel")

    let wasLoaded = loadedState.withLock { loaded -> Bool in
      let was = loaded
      loaded = false
      return was
    }

    guard wasLoaded else { return }

    // Free C resources
    if let ctx = _context { llama_free(ctx) }
    if let mdl = _model { llama_model_free(mdl) }
    _context = nil
    _model = nil
    llama_backend_free()
  }

  public var isModelLoaded: Bool {
    loadedState.withLock { $0 }
  }

  public func attachSuspendController(_ controller: SuspendController?) async {
    // Per ADR-002 §6, callers must not invoke this concurrently with
    // `generate()`. Same sequential contract that protects `_model` /
    // `_context` lets us write without a lock.
    suspendController = controller
  }

  /// Injected at init from `ModelDescriptor.displayName`. Intended for
  /// display / export metadata (past-results viewer, Markdown export,
  /// YAML replay) — not a stable parse key.
  public let modelIdentifier: String
  public let backendIdentifier = "llama.cpp"

  /// Maps a non-zero `llama_decode` result to either ``LLMError/suspended``
  /// (when an external suspend was requested — usually because iOS denied
  /// background GPU work mid-decode) or ``LLMError/generationFailed(description:)``
  /// (genuine inference error).
  ///
  /// The mapping is intentionally code-agnostic: any non-zero result that
  /// coincides with `suspendController?.isSuspendRequested() == true` is
  /// treated as suspend. Hard-coding a specific Metal error number (e.g. -3)
  /// would be fragile across llama.cpp versions and iOS releases.
  ///
  /// For the suspend mapping the partial KV cache is wiped via
  /// `llama_memory_clear` so the retried `generate()` (issued by
  /// ``LLMCaller`` after `awaitResume`) starts from a clean state.
  func decodeFailureError(_ result: Int32) -> LLMError {
    let suspendRequested = suspendController?.isSuspendRequested() ?? false
    // Diagnostic signal for Metal decode failures: distinguishes
    // "Metal denied us mid-decode while we knew we were suspending" from
    // "Metal context invalidated by OS suspend without our suspend flag set".
    // Kept at debug level so it stays available for future investigation
    // without polluting production console output.
    logger.debug(
      "decodeFailureError: result=\(result), suspendRequested=\(suspendRequested)"
    )
    if suspendRequested {
      // Wipe partial decode state so retry doesn't inherit a corrupt KV cache.
      // Safe when context is nil (test paths) — we just skip the C call.
      if let context = _context {
        llama_memory_clear(llama_get_memory(context), true)
      }
      return .suspended
    }
    return .generationFailed(
      description: "llama_decode failed (error \(result))"
    )
  }

  // `schema` is accepted but unused in Item 2 — GBNF grammar wiring
  // lands with Item 4 (plumbed through `runGeneration` → `createSampler`).
  public func generate(
    system: String, user: String, schema: OutputSchema?
  ) async throws -> String {
    try await runGeneration(system: system, user: user, schema: schema).text
  }

}

// MARK: - Generation (metrics-aware)

extension LlamaCppService {
  /// Token-count-aware counterpart to ``generate(system:user:schema:)``. Shares the
  /// same inference path and returns the generated token count for tok/s
  /// throughput reporting.
  public func generateWithMetrics(
    system: String, user: String, schema: OutputSchema?
  ) async throws -> GenerationResult {
    try await runGeneration(system: system, user: user, schema: schema)
  }

  /// Shared implementation for `generate` and `generateWithMetrics`.
  /// Counts tokens emitted by the sampler loop (excludes the trailing
  /// stop-sequence token when detected). Cooperative suspend check at each
  /// iteration boundary lets the App layer interrupt GPU work before iOS
  /// denies it (`scenePhase = .background`); reactive failure via
  /// `decodeFailureError` covers the narrow window where denial races the
  /// next iteration.
  ///
  /// `schema` reaches here via `generate` / `generateWithMetrics`; it
  /// is unused in Item 2 but kept in the signature so Item 4 can wire
  /// `createSampler` without reshaping the call chain again.
  fileprivate func runGeneration(  // swiftlint:disable:this function_body_length
    system: String, user: String, schema: OutputSchema?
  ) async throws -> GenerationResult {
    // Debug trace of generate() preconditions — kept at debug level so
    // load/reload race investigations can re-enable it without code edits.
    logger.debug(
      "generate enter: isModelLoaded=\(self.isModelLoaded), modelNil=\(self._model == nil), contextNil=\(self._context == nil)"
    )
    try await throttleIfOverheating()
    logger.debug(
      "generate post-throttle: isModelLoaded=\(self.isModelLoaded), modelNil=\(self._model == nil), contextNil=\(self._context == nil)"
    )

    // Sequential-access contract (ADR-002 §6) — entry order is load-bearing:
    //   (1) throttle (above) — cancellation-honoring; may throw out cleanly.
    //       MUST stay above (2): a CancellationError thrown from Task.sleep
    //       after the claim would skip the defer-clear and strand the flag.
    //   (2) acquireGenerateGuard — atomic wait-and-claim. Polls
    //       `generatingGuard` and only returns once it has transitioned the
    //       flag from clear to claimed in a single `withLock`. Replaces the
    //       previous `awaitGenerateIdle + separate withLock + precondition`
    //       sequence, which lost the multi-waiter race when several callers
    //       (LLMCaller JSON parse retries fire back-to-back generateStream;
    //       unloadModel paths overlap on back-nav cleanup) all woke on the
    //       same flag-clear event.
    //   (3) defer-clear — runs on every exit (including .notLoaded throw),
    //       so subsequent callers can claim cleanly.
    //   (4) isModelLoaded check + _model/_context capture AFTER the claim:
    //       unloadModel also waits behind the same flag (via awaitGenerateIdle),
    //       so pointers cannot be freed between this capture and the inference
    //       loop below.
    // Issue #221 (initial fix + follow-up race elimination).
    await acquireGenerateGuard(caller: "generate")
    defer { generatingGuard.withLock { $0 = false } }

    guard isModelLoaded, let model = _model, let context = _context else {
      logger.error(
        "generate throwing .notLoaded: isModelLoaded=\(self.isModelLoaded), modelNil=\(self._model == nil), contextNil=\(self._context == nil)"
      )
      throw LLMError.notLoaded
    }

    let vocab = llama_model_get_vocab(model)

    // Apply chat template to format system+user into model-native format
    let formattedPrompt = try applyChatTemplate(system: system, user: user)

    // Tokenize the formatted prompt
    let tokens = try tokenize(vocab: vocab, text: formattedPrompt, addSpecial: true)

    let nCtx = Int(llama_n_ctx(context))
    guard tokens.count <= nCtx else {
      throw LLMError.generationFailed(
        description: "Prompt (\(tokens.count) tokens) exceeds context size (\(nCtx))"
      )
    }

    // Clear KV cache for independent inference (each generate() call is self-contained)
    llama_memory_clear(llama_get_memory(context), true)

    // Prefill: process prompt tokens
    try prefill(context: context, tokens: tokens)

    // Set up sampler chain. Grammar (if any) is built once per call
    // and fed to `createSampler`; it lives only for this generation.
    let grammarString = try schema.map { try GBNFGrammarBuilder().build(from: $0) }
    let sampler = try createSampler(grammarString: grammarString, vocab: vocab)
    defer { llama_sampler_free(sampler) }

    // Auto-regressive generation loop with string-based stop detection.
    // Tokens are decoded incrementally so we can detect <|im_end|> even when
    // the model's tokenizer splits it across multiple subword tokens.
    var outputText = ""
    var generatedTokens = 0

    #if DEBUG
      // Token-piece tracing for partial-extractor test corpus. Off unless
      // PASTURA_TRACE_LLM is set. Scoped to this generate() so each call
      // produces one fixture file; a failed inference emits nothing.
      let traceCollector: TraceCollector? =
        LlamaCppTraceCapture.isEnabled
        ? TraceCollector(system: system, user: user) : nil
    #endif

    for _ in 0..<Self.maxTokens {
      // Respect Task cancellation. llama.cpp's C calls don't check cancellation
      // themselves, so without this a cancelled simulation would run to maxTokens
      // before exiting — making model reload / app teardown slow.
      try Task.checkCancellation()

      // Cooperative suspend: convert an external `SuspendController.requestSuspend()`
      // into an LLMError.suspended throw at the next iteration boundary. Lets the
      // App layer interrupt GPU work before iOS denies it (scenePhase = .background).
      if suspendController?.isSuspendRequested() == true {
        throw LLMError.suspended
      }

      let newTokenId = llama_sampler_sample(sampler, context, -1)

      if llama_vocab_is_eog(vocab, newTokenId) { break }

      generatedTokens += 1
      outputText += decodePiece(vocab: vocab, token: newTokenId)

      #if DEBUG
        if let collector = traceCollector {
          collector.append(
            tokenId: Int(newTokenId),
            bytes: decodePieceRaw(vocab: vocab, token: newTokenId))
        }
        emitStreamingCheckpointIfDue(
          mode: "non-stream", tokens: generatedTokens,
          tail: String(outputText.suffix(40)))
      #endif

      if let range = outputText.range(of: stopSequence) {
        outputText = String(outputText[..<range.lowerBound])
        logger.debug("\(self.stopSequence) stop sequence detected — ending generation early")
        break
      }

      // Decode single token for next iteration
      var nextToken = newTokenId
      let batch = llama_batch_get_one(&nextToken, 1)
      let decodeResult = llama_decode(context, batch)
      guard decodeResult == 0 else {
        // Reactive suspend safety net: if scenePhase already moved to
        // .background and iOS denied this Metal command, surface the failure
        // as `.suspended` (recoverable) rather than `.generationFailed`
        // (fatal). Cooperative check above catches most cases first; this
        // is for the narrow window when the denial races the next iteration.
        throw decodeFailureError(decodeResult)
      }
    }

    guard !outputText.isEmpty else {
      throw LLMError.generationFailed(description: "Model generated no output tokens")
    }

    #if DEBUG
      if let collector = traceCollector {
        writeTrace(
          collector: collector,
          finalText: outputText,
          completionTokens: generatedTokens)
      }
    #endif

    return GenerationResult(text: outputText, completionTokens: generatedTokens)
  }
}

// MARK: - Streaming generation

extension LlamaCppService {
  /// True token-by-token streaming implementation for
  /// ``LLMService/generateStream(system:user:)``.
  ///
  /// Replaces the default protocol wrap (which yields a single chunk at
  /// completion) with real incremental output. Each decoded token piece
  /// either emits as a new delta or is held back briefly while we wait
  /// to see if it completes the stop sequence `<|im_end|>` or a
  /// multi-byte UTF-8 character.
  ///
  /// Contract preserved from ``generate(system:user:)``:
  /// - Sequential access (ADR-002 §6) — concurrent callers serialize via
  ///   the atomic wait-and-claim entry primitive (`acquireGenerateGuard`),
  ///   not via a runtime trap.
  /// - Cooperative ``SuspendController`` check at each iteration boundary.
  /// - Task cancellation at iteration boundary.
  /// - Stop-sequence `<|im_end|>` never appears in emitted deltas.
  /// - Final chunk carries ``LLMStreamChunk/completionTokens`` — llama.cpp
  ///   is one of the few backends that can report this cheaply.
  ///
  /// - Important: If a prior `generate` / `generateStream` is still in
  ///   flight when this is called, the entry waits up to 30 s for the
  ///   prior call's `generatingGuard` defer to clear before producing
  ///   any chunks. Stream consumer cancellation during that wait is
  ///   honored only after the wait completes — intentional; it preserves
  ///   the use-after-free guarantee on `_model` / `_context` (Issue #221).
  public func generateStream(
    system: String, user: String, schema: OutputSchema?
  ) -> AsyncThrowingStream<LLMStreamChunk, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          try await runStreamGeneration(
            system: system, user: user, schema: schema,
            continuation: continuation)
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Core streaming loop. Emits chunks via `continuation` and throws on
  /// cancel, suspend, or inference failure. Caller wraps via
  /// `finish(throwing:)` so errors propagate through the async sequence.
  ///
  /// `schema` reaches here via `generateStream`; it is unused in Item 2
  /// but kept in the signature so Item 4 can wire `createSampler`
  /// without reshaping the call chain again.
  fileprivate func runStreamGeneration(  // swiftlint:disable:this function_body_length cyclomatic_complexity
    system: String, user: String, schema: OutputSchema?,
    continuation: AsyncThrowingStream<LLMStreamChunk, Error>.Continuation
  ) async throws {
    try await throttleIfOverheating()

    // Sequential-access contract (ADR-002 §6) — same four-step entry order
    // as `runGeneration` (throttle → acquireGenerateGuard → defer →
    // load-check + capture). The throttle above MUST stay above the claim
    // so a CancellationError out of Task.sleep cannot strand the flag. See
    // the longer comment block in `runGeneration` for why the load check
    // is placed AFTER the guard claim (use-after-free prevention on
    // `_model` / `_context`). Issue #221.
    await acquireGenerateGuard(caller: "generateStream")
    defer { generatingGuard.withLock { $0 = false } }

    guard isModelLoaded, let model = _model, let context = _context else {
      throw LLMError.notLoaded
    }

    let vocab = llama_model_get_vocab(model)
    let formattedPrompt = try applyChatTemplate(system: system, user: user)
    let tokens = try tokenize(vocab: vocab, text: formattedPrompt, addSpecial: true)

    let nCtx = Int(llama_n_ctx(context))
    guard tokens.count <= nCtx else {
      throw LLMError.generationFailed(
        description: "Prompt (\(tokens.count) tokens) exceeds context size (\(nCtx))"
      )
    }

    llama_memory_clear(llama_get_memory(context), true)
    try prefill(context: context, tokens: tokens)

    // Grammar-constrained sampling: build once per stream invocation
    // (matching the non-streaming path in `runGeneration`). Missing
    // wire-up here would silently bypass grammar on the streaming
    // path — the regression scenario Critic Axis 3 flagged.
    let grammarString = try schema.map { try GBNFGrammarBuilder().build(from: $0) }
    let sampler = try createSampler(grammarString: grammarString, vocab: vocab)
    defer { llama_sampler_free(sampler) }

    // Byte-level accumulation so UTF-8 characters split across pieces
    // (common for CJK / emoji) never emit as partial replacement
    // characters. `decodedText` always holds the longest valid UTF-8
    // prefix of `outputBytes`.
    var outputBytes = Data()
    var decodedText = ""
    var emittedCharCount = 0
    var generatedTokens = 0

    #if DEBUG
      let traceCollector: TraceCollector? =
        LlamaCppTraceCapture.isEnabled
        ? TraceCollector(system: system, user: user) : nil
    #endif

    for _ in 0..<Self.maxTokens {
      try Task.checkCancellation()
      if suspendController?.isSuspendRequested() == true {
        throw LLMError.suspended
      }

      let newTokenId = llama_sampler_sample(sampler, context, -1)
      if llama_vocab_is_eog(vocab, newTokenId) { break }

      generatedTokens += 1
      let pieceBytes = decodePieceRaw(vocab: vocab, token: newTokenId)
      outputBytes.append(pieceBytes)

      #if DEBUG
        traceCollector?.append(tokenId: Int(newTokenId), bytes: pieceBytes)
      #endif

      if let refreshed = Self.longestValidUtf8Prefix(outputBytes) {
        decodedText = refreshed
      }

      #if DEBUG
        emitStreamingCheckpointIfDue(
          mode: "stream", tokens: generatedTokens,
          tail: String(decodedText.suffix(40)))
      #endif

      // Stop-sequence match: flush everything before it, terminate.
      if let range = decodedText.range(of: stopSequence) {
        let beforeStop = String(decodedText[..<range.lowerBound])
        Self.emitDelta(
          from: beforeStop, alreadyEmitted: emittedCharCount,
          through: beforeStop.count, continuation: continuation)
        emittedCharCount = beforeStop.count
        decodedText = beforeStop
        logger.debug("\(self.stopSequence) stop sequence detected — ending stream early")
        break
      }

      // Conservative emission: hold back any tail that could still
      // become the beginning of the stop sequence. `<` alone holds back
      // one char; `<|` holds back two; the next iteration either
      // completes the match (handled above) or disambiguates, at which
      // point holdback drops to zero and the queued chars flush.
      let holdback = stopSequenceHoldbackLength(in: decodedText)
      let safeCount = decodedText.count - holdback
      if safeCount > emittedCharCount {
        Self.emitDelta(
          from: decodedText, alreadyEmitted: emittedCharCount,
          through: safeCount, continuation: continuation)
        emittedCharCount = safeCount
      }

      var nextToken = newTokenId
      let batch = llama_batch_get_one(&nextToken, 1)
      let decodeResult = llama_decode(context, batch)
      guard decodeResult == 0 else {
        throw decodeFailureError(decodeResult)
      }
    }

    // Flush any characters still held back for stop-sequence matching.
    // Reached when the loop exits via EOG or maxTokens without ever
    // seeing the stop marker — the held-back tail is legitimate output.
    if emittedCharCount < decodedText.count {
      Self.emitDelta(
        from: decodedText, alreadyEmitted: emittedCharCount,
        through: decodedText.count, continuation: continuation)
      emittedCharCount = decodedText.count
    }

    guard !decodedText.isEmpty else {
      throw LLMError.generationFailed(
        description: "Model generated no output tokens")
    }

    #if DEBUG
      if let collector = traceCollector {
        writeTrace(
          collector: collector,
          finalText: decodedText,
          completionTokens: generatedTokens)
      }
    #endif

    // Terminal chunk: empty delta, carries the final token count.
    // Keeping the terminator separate from text-bearing chunks means
    // consumers can trust `isFinal` as a pure termination signal
    // without having to track deltas.
    continuation.yield(
      LLMStreamChunk(
        delta: "", isFinal: true, completionTokens: generatedTokens))
  }

  /// Emit a delta covering `decoded[alreadyEmitted..<through]` as a
  /// non-final chunk. No-op if the range is empty.
  fileprivate static func emitDelta(
    from decoded: String, alreadyEmitted: Int, through: Int,
    continuation: AsyncThrowingStream<LLMStreamChunk, Error>.Continuation
  ) {
    guard through > alreadyEmitted else { return }
    let start = decoded.index(decoded.startIndex, offsetBy: alreadyEmitted)
    let end = decoded.index(decoded.startIndex, offsetBy: through)
    let delta = String(decoded[start..<end])
    continuation.yield(
      LLMStreamChunk(delta: delta, isFinal: false, completionTokens: nil))
  }

  /// Longest UTF-8-decodable prefix of `bytes`. Trims up to 3 trailing
  /// bytes (the max continuation-byte length in UTF-8) to recover a
  /// valid decoding when a multi-byte character is split across pieces.
  /// Returns nil only if even the empty prefix fails — impossible for
  /// `Data` and therefore a bug signal.
  fileprivate static func longestValidUtf8Prefix(_ bytes: Data) -> String? {
    for trim in 0...min(3, bytes.count) {
      let slice = bytes.prefix(bytes.count - trim)
      if let text = String(data: slice, encoding: .utf8) {
        return text
      }
    }
    return nil
  }

  /// Length of the longest suffix of `decoded` that is also a strict
  /// prefix of ``stopSequence``. Those characters are held back from
  /// emission until the next token disambiguates whether we are
  /// actually starting `<|im_end|>`.
  ///
  /// Returns 0 when the tail shares nothing with the stop sequence — the
  /// common case, producing immediate emission and zero UX lag. Capped
  /// at `stopSequence.count - 1` because a full match is handled
  /// directly by the caller.
  fileprivate func stopSequenceHoldbackLength(in decoded: String) -> Int {
    let stop = stopSequence
    let maxLen = min(decoded.count, stop.count - 1)
    if maxLen == 0 { return 0 }
    for length in stride(from: maxLen, through: 1, by: -1) {
      let tailStart = decoded.index(decoded.endIndex, offsetBy: -length)
      if stop.hasPrefix(decoded[tailStart...]) {
        return length
      }
    }
    return 0
  }
}
