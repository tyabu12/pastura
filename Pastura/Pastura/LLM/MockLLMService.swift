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
    /// Number of upcoming generate calls that should throw `.suspended` instead of
    /// returning a response. Decremented on each suspended throw.
    var pendingSuspendCount: Int = 0
    /// Suspend controller installed via ``attachSuspendController(_:)``.
    /// When set, generate() also honours the controller's suspend flag — this
    /// lets tests exercise the same code path as LlamaCppService.
    var controller: SuspendController?
    /// Per-inference delta sequences for ``generateStream(system:user:)``.
    /// `nil` means "use the default wrap" (generate + single chunk).
    /// Independent from `responses` — streaming tests that need specific
    /// chunk boundaries configure this explicitly.
    var streamChunks: [[String]]?
    /// Number of successful `generateStream` completions. Tracked
    /// separately from `callIndex` (which counts `generate` calls) so
    /// tests that mix both paths can assert each count independently.
    var streamCallIndex: Int = 0
  }

  private let state: OSAllocatedUnfairLock<State>

  /// Initialize with an ordered sequence of raw JSON responses.
  ///
  /// - Parameter responses: The responses to return in order from ``generate(system:user:)``.
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

  public func generate(system: String, user: String) async throws -> String {
    try state.withLock { mutableState in
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
      return response
    }
  }

  public func attachSuspendController(_ controller: SuspendController?) async {
    state.withLock { $0.controller = controller }
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
  ///   ``generate(system:user:)``.
  /// - **Wrap mode (no stream chunks):** Invokes ``generate(system:user:)``
  ///   and yields the full response as a single terminal chunk — same
  ///   observable behaviour as the protocol default wrap.
  public func generateStream(
    system: String, user: String
  ) -> AsyncThrowingStream<LLMStreamChunk, Error> {
    AsyncThrowingStream { continuation in
      let task = Task { [weak self] in
        guard let self else {
          continuation.finish()
          return
        }
        do {
          let deltas = try self.consumeStreamChunks(system: system, user: user)
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
            let text = try await self.generate(system: system, user: user)
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
  /// sequence, applying the same throw-semantics as ``generate(system:user:)``.
  /// Returns `nil` when no stream chunks are configured — signalling that
  /// the caller should fall back to the wrap mode (call `generate`).
  private func consumeStreamChunks(
    system: String, user: String
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
      return deltas
    }
  }

  // MARK: - Test Helpers

  /// The number of times ``generate(system:user:)`` has been called successfully.
  public var generateCallCount: Int {
    state.withLock { $0.callIndex }
  }

  /// The system and user prompts from each ``generate(system:user:)`` call.
  public var capturedPrompts: [(system: String, user: String)] {
    state.withLock { $0.capturedPrompts }
  }

  /// Reset the service to its initial state, rewinding the response sequence.
  public func reset() {
    state.withLock { locked in
      locked.callIndex = 0
      locked.streamCallIndex = 0
      locked.capturedPrompts = []
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
  /// - Note: For tests that want to exercise the live controller path instead
  ///   of pre-scheduling, attach a ``SuspendController`` via
  ///   ``attachSuspendController(_:)`` and toggle it directly.
  public func simulateSuspendOnNextGenerate() {
    state.withLock { $0.pendingSuspendCount += 1 }
  }
}
