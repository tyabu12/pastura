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
/// - Important: Not safe for concurrent `generate()` calls. The Engine executes
///   inferences sequentially, so this is fine in practice; a runtime guard
///   (`precondition`) catches any regression.
/// - Note: `loadModel()`/`unloadModel()` cooperatively wait if a `generate()` is
///   in flight (see `awaitGenerateIdle`). Used to be a precondition crash, but
///   this fires on legitimate cleanup paths where llama.cpp's C API can't be
///   interrupted (memory warning, cancellation).
nonisolated public final class LlamaCppService: LLMService, @unchecked Sendable {
  // @unchecked Sendable: isModelLoaded flag protected by OSAllocatedUnfairLock.
  // C pointers use nonisolated(unsafe) — Engine calls generate() sequentially via
  // `for await` on a single AsyncStream, and loadModel()/unloadModel() bracket the
  // stream lifetime, guaranteeing no concurrent access to C pointers (ADR-002 §6).

  private let modelPath: String
  let logger = Logger(subsystem: "com.pastura", category: "LlamaCppService")

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
  // Runtime guard for the sequential access contract (ADR-002 §6).
  // Catches concurrent generate(). load/unload wait for it via awaitGenerateIdle
  // (in +Lifecycle.swift) instead of crashing on concurrent access.
  private let generatingGuard = OSAllocatedUnfairLock<Bool>(initialState: false)

  /// Whether a `generate()` call is currently in flight.
  /// Exposed so the +Lifecycle extension can poll without direct lock access.
  func isGenerating() -> Bool {
    generatingGuard.withLock { $0 }
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
  }

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

  public func generate(system: String, user: String) async throws -> String {
    try await runGeneration(system: system, user: user).text
  }

}

// MARK: - Generation (metrics-aware)

extension LlamaCppService {
  /// Token-count-aware counterpart to ``generate(system:user:)``. Shares the
  /// same inference path and returns the generated token count for tok/s
  /// throughput reporting.
  public func generateWithMetrics(
    system: String, user: String
  ) async throws -> GenerationResult {
    try await runGeneration(system: system, user: user)
  }

  /// Shared implementation for `generate` and `generateWithMetrics`.
  /// Counts tokens emitted by the sampler loop (excludes the trailing
  /// stop-sequence token when detected). Cooperative suspend check at each
  /// iteration boundary lets the App layer interrupt GPU work before iOS
  /// denies it (`scenePhase = .background`); reactive failure via
  /// `decodeFailureError` covers the narrow window where denial races the
  /// next iteration.
  fileprivate func runGeneration(  // swiftlint:disable:this function_body_length
    system: String, user: String
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

    guard isModelLoaded, let model = _model, let context = _context else {
      logger.error(
        "generate throwing .notLoaded: isModelLoaded=\(self.isModelLoaded), modelNil=\(self._model == nil), contextNil=\(self._context == nil)"
      )
      throw LLMError.notLoaded
    }

    // Runtime enforcement of sequential access contract (ADR-002 §6).
    // Concurrent generate() would cause use-after-free of C pointers.
    // IMPORTANT: This guard is intentionally placed after the isModelLoaded check above.
    // Calls that fail with .notLoaded must not touch the flag — otherwise the flag
    // stays true and the next sequential call would be falsely flagged as concurrent.
    let wasGenerating = generatingGuard.withLock { flag -> Bool in
      let was = flag
      flag = true
      return was
    }
    precondition(!wasGenerating, "Concurrent generate() detected — ADR-002 §6")
    defer { generatingGuard.withLock { $0 = false } }

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

    // Set up sampler chain
    let sampler = try createSampler()
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
  /// - Sequential access (ADR-002 §6) — `precondition` fires on concurrent entry.
  /// - Cooperative ``SuspendController`` check at each iteration boundary.
  /// - Task cancellation at iteration boundary.
  /// - Stop-sequence `<|im_end|>` never appears in emitted deltas.
  /// - Final chunk carries ``LLMStreamChunk/completionTokens`` — llama.cpp
  ///   is one of the few backends that can report this cheaply.
  ///
  /// - Important: Callers must fully drain (or cancel + await) the
  ///   returned `AsyncThrowingStream` before starting the next
  ///   `generate`/`generateStream` call. The `generatingGuard` clears
  ///   in a `defer` after `continuation.finish()`, so back-to-back calls
  ///   issued in the narrow window between the last yielded chunk and
  ///   the Task's exit will `precondition`-crash.
  public func generateStream(
    system: String, user: String
  ) -> AsyncThrowingStream<LLMStreamChunk, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          try await runStreamGeneration(
            system: system, user: user, continuation: continuation)
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
  fileprivate func runStreamGeneration(  // swiftlint:disable:this function_body_length cyclomatic_complexity
    system: String, user: String,
    continuation: AsyncThrowingStream<LLMStreamChunk, Error>.Continuation
  ) async throws {
    try await throttleIfOverheating()

    guard isModelLoaded, let model = _model, let context = _context else {
      throw LLMError.notLoaded
    }

    let wasGenerating = generatingGuard.withLock { flag -> Bool in
      let was = flag
      flag = true
      return was
    }
    precondition(!wasGenerating, "Concurrent generate() detected — ADR-002 §6")
    defer { generatingGuard.withLock { $0 = false } }

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

    let sampler = try createSampler()
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
