import Foundation
import os

/// A deterministic LLM service that returns pre-defined responses in sequence.
///
/// Used in Engine tests to verify simulation logic without actual LLM inference.
/// Responses are consumed in FIFO order; requesting beyond the sequence throws.
nonisolated public final class MockLLMService: LLMService, @unchecked Sendable {
  // @unchecked Sendable: mutable state is protected by OSAllocatedUnfairLock.

  // `internal` (not `private`) so the block-gate sibling file
  // (`MockLLMService+BlockGate.swift`) can read `State.blockGate`. LLM-module
  // -internal only; no public surface change (#726).
  struct State {
    var responses: [String]
    var callIndex: Int = 0
    var isModelLoaded: Bool = false
    var capturedPrompts: [(system: String, user: String)] = []
    /// Per-call schema values observed by ``generate(system:user:schema:)``
    /// and ``generateStream(system:user:schema:)``. Appended in call order
    /// so tests can assert the handler layer passes the right schema for
    /// each phase. `nil` entries record unconstrained calls.
    var capturedSchemas: [OutputSchema?] = []
    /// Per-call `antiRepetitionSeeds` observed by
    /// ``generate(system:user:schema:antiRepetitionSeeds:)`` and
    /// ``generateStream(system:user:schema:antiRepetitionSeeds:)``, appended
    /// in call order. The mock does not act on seeds (no real sampler), but
    /// recording them lets Engine tests assert a handler threads the agent's
    /// prior statement into the DRY seam (#1105). An empty inner array records
    /// a seed-less call (first round / other handlers).
    var capturedAntiRepetitionSeeds: [[String]] = []
    /// Number of upcoming generate calls that should throw `.suspended` instead of
    /// returning a response. Decremented on each suspended throw.
    var pendingSuspendCount: Int = 0
    /// Suspend controller installed via ``attachSuspendController(_:)``.
    /// When set, generate() also honours the controller's suspend flag — this
    /// lets tests exercise the same code path as LlamaCppService.
    var controller: SuspendController?
    /// When `true`, ``attachSuspendController(_:)`` arms the controller's
    /// suspend immediately on attach (see ``suspendOnControllerAttach()``).
    var suspendOnAttach: Bool = false
    /// Per-inference delta sequences for ``generateStream(system:user:schema:)``.
    /// `nil` means "use the default wrap" (generate + single chunk).
    /// Independent from `responses` — streaming tests that need specific
    /// chunk boundaries configure this explicitly.
    var streamChunks: [[String]]?
    /// Number of successful `generateStream` completions. Tracked
    /// separately from `callIndex` (which counts `generate` calls) so
    /// tests that mix both paths can assert each count independently.
    var streamCallIndex: Int = 0
    /// Signal-blocked gate for the UI-test hold — see ``blockGenerateUntilSignal()``.
    var blockGate: BlockGate = .disabled
    /// FIFO of errors to throw on upcoming generate / generateStream calls,
    /// one per call, before the configured responses resume. Lets tests
    /// deterministically inject a retryable backend throw (e.g.
    /// ``LLMError/samplerCrashCaught(description:)``) on specific attempts.
    /// Independent from ``pendingSuspendCount`` (which is `.suspended`-only).
    var pendingGenerateErrors: [LLMError] = []
  }

  // `internal` (not `private`) so the block-gate sibling file
  // (`MockLLMService+BlockGate.swift`) can drive `state.withLock`. The
  // `BlockGate` enum and the gate methods live there (#726).
  let state: OSAllocatedUnfairLock<State>

  /// Initialize with an ordered sequence of raw JSON responses.
  ///
  /// - Parameter responses: The responses to return in order from
  ///   ``generate(system:user:)``.
  public init(responses: [String]) {
    self.state = OSAllocatedUnfairLock(initialState: State(responses: responses))
  }

  public func loadModel() async throws {
    state.withLock { $0.isModelLoaded = true }
  }

  public func unloadModel() async throws {
    state.withLock { $0.isModelLoaded = false }
  }

  public var isModelLoaded: Bool {
    state.withLock { $0.isModelLoaded }
  }

  public let modelIdentifier = "mock"
  public let backendIdentifier = "mock"

  public func generate(
    system: String, user: String, schema: OutputSchema?,
    antiRepetitionSeeds: [String]
  ) async throws -> String {
    // The mock replays scripted responses, so sampler-side repetition
    // suppression (#1105) has nothing to act on — but the seeds are recorded
    // (`capturedAntiRepetitionSeeds`) so Engine tests can assert the handler
    // threaded the right prior statement.
    // Park on the block gate OUTSIDE the lock (can't `await` inside a
    // synchronous `withLock`). Disabled by default — a pure no-op for existing
    // tests. When armed, the run is held in-flight until unblock or
    // cancellation, wall-clock-independent (#719).
    try await awaitBlockReleaseIfArmed()
    return try state.withLock { mutableState in
      guard mutableState.isModelLoaded else { throw LLMError.notLoaded }
      // Drain a pending suspend slot first — this lets tests deterministically
      // schedule N suspend throws before the next normal response is delivered.
      if mutableState.pendingSuspendCount > 0 {
        mutableState.pendingSuspendCount -= 1
        throw LLMError.suspended
      }
      // Honour an attached controller's live suspend flag, mirroring
      // LlamaCppService's cooperative check.
      if mutableState.controller?.isSuspendRequested() == true {
        throw LLMError.suspended
      }
      // Drain a scheduled backend error (e.g. a caught sampler crash) so
      // tests can inject a retryable throw on specific attempts.
      if !mutableState.pendingGenerateErrors.isEmpty {
        throw mutableState.pendingGenerateErrors.removeFirst()
      }
      guard mutableState.callIndex < mutableState.responses.count else {
        throw LLMError.generationFailed(
          description:
            "MockLLMService exhausted: \(mutableState.callIndex) calls made, only \(mutableState.responses.count) responses available"
        )
      }
      let response = mutableState.responses[mutableState.callIndex]
      mutableState.callIndex += 1
      mutableState.capturedPrompts.append((system: system, user: user))
      mutableState.capturedSchemas.append(schema)
      mutableState.capturedAntiRepetitionSeeds.append(antiRepetitionSeeds)
      return response
    }
  }

  public func attachSuspendController(_ controller: SuspendController?) async {
    let shouldArm = state.withLock { mutableState -> Bool in
      mutableState.controller = controller
      return controller != nil && mutableState.suspendOnAttach
    }
    // Arm OUTSIDE the lock (SuspendController has its own lock). This parks the
    // run at its FIRST generate with no scheduling window: run()/resume() attach
    // the controller in `prepareRunInfrastructure` before any generate is issued.
    if shouldArm, let controller { controller.requestSuspend() }
  }

  /// Make ``attachSuspendController(_:)`` arm the controller's suspend on attach,
  /// so a run parks GENUINELY at its first generate with no scheduling race.
  ///
  /// Unlike ``throwSuspendedOnNextGenerate()`` (which pre-schedules a throw but
  /// leaves the controller `.idle`, so `awaitResume()` returns immediately and
  /// the run never blocks), this puts the live controller in `.suspended` before
  /// the first generate — `awaitResume()` then genuinely parks until the run is
  /// resumed or torn down. Deterministic regardless of `.instant` speed (#707).
  public func suspendOnControllerAttach() {
    state.withLock { $0.suspendOnAttach = true }
  }

  // MARK: - Streaming

  /// Override the default protocol wrap so tests can exercise streaming
  /// consumers with explicit delta boundaries.
  ///
  /// Behaviour depends on whether ``setStreamChunks(_:)`` has been called:
  ///
  /// - **Streaming mode (stream chunks configured):** Each delta in the
  ///   configured sequence yields as a non-final chunk, followed by a
  ///   terminal chunk with empty delta and `nil` completion tokens. Obeys
  ///   the same suspend / not-loaded / exhausted semantics as
  ///   ``generate(system:user:schema:)``.
  /// - **Wrap mode (no stream chunks):** Invokes
  ///   ``generate(system:user:schema:)`` and yields the full response as
  ///   a single terminal chunk — same observable behaviour as the
  ///   protocol default wrap.
  public func generateStream(
    system: String, user: String, schema: OutputSchema?,
    antiRepetitionSeeds: [String]
  ) -> AsyncThrowingStream<LLMStreamChunk, Error> {
    // Seeds recorded, not acted upon — see the note on `generate(…)` above.
    AsyncThrowingStream { continuation in
      let task = Task { [weak self] in
        guard let self else {
          continuation.finish()
          return
        }
        do {
          let deltas = try self.consumeStreamChunks(
            system: system, user: user, schema: schema,
            antiRepetitionSeeds: antiRepetitionSeeds)
          if let deltas {
            for delta in deltas {
              try Task.checkCancellation()
              continuation.yield(
                LLMStreamChunk(
                  delta: delta, isFinal: false, completionTokens: nil))
            }
            continuation.yield(
              LLMStreamChunk(
                delta: "", isFinal: true, completionTokens: nil))
            continuation.finish()
          } else {
            let text = try await self.generate(
              system: system, user: user, schema: schema,
              antiRepetitionSeeds: antiRepetitionSeeds)
            continuation.yield(
              LLMStreamChunk(
                delta: text, isFinal: true, completionTokens: nil))
            continuation.finish()
          }
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Drain one inference's worth of stream chunks from the configured
  /// sequence, applying the same throw-semantics as
  /// ``generate(system:user:schema:)``. Returns `nil` when no stream
  /// chunks are configured — signalling that the caller should fall
  /// back to the wrap mode (call `generate`). Note: when falling back
  /// to wrap mode, `generate(system:user:schema:)` will record the
  /// schema — so the streaming-wrap path records exactly once, not
  /// twice.
  private func consumeStreamChunks(
    system: String, user: String, schema: OutputSchema?,
    antiRepetitionSeeds: [String]
  ) throws -> [String]? {
    try state.withLock { mutableState in
      guard mutableState.isModelLoaded else { throw LLMError.notLoaded }
      if mutableState.pendingSuspendCount > 0 {
        mutableState.pendingSuspendCount -= 1
        throw LLMError.suspended
      }
      if mutableState.controller?.isSuspendRequested() == true {
        throw LLMError.suspended
      }
      // Drain a scheduled backend error before any stream chunks — fires
      // in both wrap and explicit-chunk modes (LLMCaller uses the stream
      // path). Wrap mode throws here before `generate()` is reached, so a
      // single scheduled error is never double-consumed.
      if !mutableState.pendingGenerateErrors.isEmpty {
        throw mutableState.pendingGenerateErrors.removeFirst()
      }
      guard let chunks = mutableState.streamChunks else { return nil }
      guard mutableState.streamCallIndex < chunks.count else {
        throw LLMError.generationFailed(
          description:
            "MockLLMService streamChunks exhausted: \(mutableState.streamCallIndex) stream calls made, only \(chunks.count) configured"
        )
      }
      let deltas = chunks[mutableState.streamCallIndex]
      mutableState.streamCallIndex += 1
      mutableState.capturedPrompts.append((system: system, user: user))
      mutableState.capturedSchemas.append(schema)
      mutableState.capturedAntiRepetitionSeeds.append(antiRepetitionSeeds)
      return deltas
    }
  }

  // MARK: - Test Helpers

  /// The number of times ``generate(system:user:)`` has been called successfully.
  public var generateCallCount: Int {
    state.withLock { $0.callIndex }
  }

  /// The system and user prompts from each ``generate(system:user:schema:)`` call.
  public var capturedPrompts: [(system: String, user: String)] {
    state.withLock { $0.capturedPrompts }
  }

  /// The `schema` argument passed to each
  /// ``generate(system:user:schema:)`` and
  /// ``generateStream(system:user:schema:)`` call, in call order.
  /// `nil` entries are unconstrained calls.
  public var capturedSchemas: [OutputSchema?] {
    state.withLock { $0.capturedSchemas }
  }

  /// The `antiRepetitionSeeds` argument passed to each
  /// ``generate(system:user:schema:antiRepetitionSeeds:)`` and
  /// ``generateStream(system:user:schema:antiRepetitionSeeds:)`` call, in
  /// call order. An empty inner array is a seed-less call (#1105).
  public var capturedAntiRepetitionSeeds: [[String]] {
    state.withLock { $0.capturedAntiRepetitionSeeds }
  }

  /// Reset the service to its initial state, rewinding the response sequence.
  public func reset() {
    state.withLock { locked in
      locked.callIndex = 0
      locked.streamCallIndex = 0
      locked.capturedPrompts = []
      locked.capturedSchemas = []
      locked.capturedAntiRepetitionSeeds = []
      locked.pendingSuspendCount = 0
      locked.pendingGenerateErrors = []
    }
  }

  /// Configure the delta sequences used by ``generateStream(system:user:)``.
  /// Outer array index maps to the Nth `generateStream` call; inner array
  /// is the delta sequence emitted for that call (followed by a terminal
  /// empty-delta final chunk).
  ///
  /// Pass `nil` to revert to default-wrap behaviour (call `generate` and
  /// emit one terminal chunk with the full response).
  ///
  /// - Parameter chunks: Per-call delta sequences, or `nil` to clear.
  public func setStreamChunks(_ chunks: [[String]]?) {
    state.withLock { $0.streamChunks = chunks }
  }

  /// The number of times ``generateStream(system:user:)`` has been
  /// drained to completion while stream chunks were configured.
  /// `generateStream` calls that fell back to the wrap path are counted
  /// via ``generateCallCount`` instead.
  public var streamCallCount: Int {
    state.withLock { $0.streamCallIndex }
  }

  /// Schedule the next ``generate(system:user:)`` call to throw
  /// ``LLMError/suspended`` instead of returning a response.
  ///
  /// Each invocation queues exactly one suspend throw. After the suspend has
  /// been delivered, subsequent generate calls return the next response in
  /// the configured sequence (the response at the current `callIndex` is not
  /// consumed by the suspend throw).
  ///
  /// - Important: This does **NOT** park a run. The attached ``SuspendController``
  ///   stays `.idle`, so `LLMCaller.awaitResume()` returns immediately and the
  ///   generate retries and succeeds — the run keeps running. Use this only to
  ///   unit-test the suspend-retry loop (how a caller reacts to a `.suspended`
  ///   throw), NOT to hold a run mid-flight. For a genuine mid-flight park, use
  ///   ``suspendOnControllerAttach()`` (puts the controller in `.suspended` so
  ///   `awaitResume()` actually blocks).
  public func throwSuspendedOnNextGenerate() {
    state.withLock { $0.pendingSuspendCount += 1 }
  }

  /// Schedule `error` to be thrown on each of the next `count` generate /
  /// generateStream calls (FIFO), before the configured responses resume.
  ///
  /// Unlike ``throwSuspendedOnNextGenerate()`` (which is `.suspended`-only
  /// and absorbed transparently by the suspend-retry loop), this injects an
  /// arbitrary backend throw — e.g. a caught sampler crash
  /// (``LLMError/samplerCrashCaught(description:)``) that `LLMCaller` should
  /// route through its retry budget, or a fail-fast case whose non-retry
  /// the test wants to pin.
  ///
  /// - Parameters:
  ///   - error: The error to throw.
  ///   - count: How many upcoming calls should throw it (default 1).
  public func throwErrorOnNextGenerate(_ error: LLMError, count: Int = 1) {
    state.withLock { locked in
      for _ in 0..<max(0, count) { locked.pendingGenerateErrors.append(error) }
    }
  }
}
