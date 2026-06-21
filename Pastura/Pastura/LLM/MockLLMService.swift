import Foundation
import os

/// A deterministic LLM service that returns pre-defined responses in sequence.
///
/// Used in Engine tests to verify simulation logic without actual LLM inference.
/// Responses are consumed in FIFO order; requesting beyond the sequence throws.
nonisolated public final class MockLLMService: LLMService, @unchecked Sendable {
  // @unchecked Sendable: mutable state is protected by OSAllocatedUnfairLock.

  private struct State {
    var responses: [String]
    var callIndex: Int = 0
    var isModelLoaded: Bool = false
    var capturedPrompts: [(system: String, user: String)] = []
    /// Per-call schema values observed by ``generate(system:user:schema:)``
    /// and ``generateStream(system:user:schema:)``. Appended in call order
    /// so tests can assert the handler layer passes the right schema for
    /// each phase. `nil` entries record unconstrained calls.
    var capturedSchemas: [OutputSchema?] = []
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
  }

  /// State of the ``blockGenerateUntilSignal()`` gate. Stored continuation is
  /// non-nil only while a `generate` call is parked. Mirrors
  /// ``SuspendController``'s `idle`/`suspended`/`resumed` shape (incl. its
  /// proven cancel-before-store race fix); `.disabled` is the mode-off default
  /// so the gate is a pure no-op unless explicitly armed.
  private enum BlockGate: Sendable {
    case disabled
    case armed(CheckedContinuation<Void, Never>?)
    case released
  }

  private let state: OSAllocatedUnfairLock<State>

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
    system: String, user: String, schema: OutputSchema?
  ) async throws -> String {
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

  // MARK: - Signal-blocked generate (UI-test hold)

  /// Arm `generate` to park (before its not-loaded / suspend / response checks)
  /// until ``unblockGenerate()`` is called or the calling task is cancelled.
  ///
  /// Holds a run in-flight **independent of wall-clock** — replaces the former
  /// `generateDelay` timed sleep so a slow CI runner can never expire the hold
  /// mid-test (#719). The block lives INSIDE `generate` and is **not** released
  /// by a ``SuspendController`` resume, which is the whole point: it stays
  /// distinct from ``suspendOnControllerAttach()`` (a pre-generate *park* that
  /// the `.viewHide` resume gate would clear, letting the generate run on and
  /// exhaust an empty `responses` queue).
  ///
  /// Scope: gates ``generate(system:user:schema:)`` and therefore wrap-mode
  /// ``generateStream(system:user:schema:)``, but NOT explicit
  /// ``setStreamChunks(_:)`` streaming (that path never calls `generate`). The
  /// armed mode is a *configuration* that survives ``reset()`` (like
  /// `controller` / `suspendOnAttach`); ``unblockGenerate()`` releases it.
  public func blockGenerateUntilSignal() {
    state.withLock { $0.blockGate = .armed(nil) }
  }

  /// Release a `generate` parked by ``blockGenerateUntilSignal()`` and latch the
  /// release so a later park returns immediately.
  ///
  /// Idempotent and safe to call before any `generate` parks (the latch makes
  /// the unblock un-loseable). No-op when the gate is `.disabled`.
  public func unblockGenerate() {
    // Extract the parked continuation under the lock, resume OUTSIDE it (the
    // executor enqueue must not run while holding the lock). Mirrors
    // SuspendController.resume().
    let continuation: CheckedContinuation<Void, Never>? = state.withLock { mutableState in
      switch mutableState.blockGate {
      case .disabled, .released:
        return nil
      case .armed(let stored):
        mutableState.blockGate = .released
        return stored
      }
    }
    continuation?.resume()
  }

  /// Park the calling task on an armed block gate until ``unblockGenerate()`` or
  /// task cancellation; return immediately when the gate is `.disabled` /
  /// `.released`. Verbatim-mirrors ``SuspendController/awaitResume()``'s proven
  /// cancel-before-store race fix (#134) — `<Void, Never>` + post-await `checkCancellation()`.
  private func awaitBlockReleaseIfArmed() async throws {
    // Fast path: skip the continuation hop when the mode is off, so a default
    // MockLLMService behaves exactly as before.
    let isArmed = state.withLock { mutableState -> Bool in
      if case .disabled = mutableState.blockGate { return false }
      return true
    }
    guard isArmed else { return }
    await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let resumeNow = state.withLock { mutableState -> Bool in
          switch mutableState.blockGate {
          case .disabled, .released:
            // Already released (latched unblock) — return immediately.
            return true
          case .armed(let existing):
            precondition(
              existing == nil,
              "MockLLMService: multi-awaiter block not supported (1 generate = 1 waiter)"
            )
            mutableState.blockGate = .armed(continuation)
            return false
          }
        }
        if resumeNow {
          continuation.resume()
          return
        }
        // onCancel may have fired BEFORE the continuation was installed — it
        // then saw `.armed(nil)` and no-op'd, leaving the just-stored
        // continuation parked forever. Self-resume to close the race.
        if Task.isCancelled {
          extractParkedBlockContinuation()?.resume()
        }
      }
    } onCancel: {
      extractParkedBlockContinuation()?.resume()
    }
    // Distinguish cancellation from a normal unblock for the caller.
    try Task.checkCancellation()
  }

  /// Atomically extract the parked block continuation (if any), clearing it to
  /// `.armed(nil)` so cancel / unblock paths never resume it twice. Resume the
  /// returned value OUTSIDE any lock. Mirrors `extractStoredContinuation()`.
  private func extractParkedBlockContinuation() -> CheckedContinuation<Void, Never>? {
    state.withLock { mutableState in
      guard case .armed(let stored) = mutableState.blockGate, let cont = stored else {
        return nil
      }
      mutableState.blockGate = .armed(nil)
      return cont
    }
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
    system: String, user: String, schema: OutputSchema?
  ) -> AsyncThrowingStream<LLMStreamChunk, Error> {
    AsyncThrowingStream { continuation in
      let task = Task { [weak self] in
        guard let self else {
          continuation.finish()
          return
        }
        do {
          let deltas = try self.consumeStreamChunks(
            system: system, user: user, schema: schema)
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
              system: system, user: user, schema: schema)
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
    system: String, user: String, schema: OutputSchema?
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

  /// Reset the service to its initial state, rewinding the response sequence.
  public func reset() {
    state.withLock { locked in
      locked.callIndex = 0
      locked.streamCallIndex = 0
      locked.capturedPrompts = []
      locked.capturedSchemas = []
      locked.pendingSuspendCount = 0
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
}
