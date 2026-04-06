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

  public func generate(system: String, user: String) async throws -> String {
    try state.withLock { s in
      guard s.isModelLoaded else { throw LLMError.notLoaded }
      guard s.callIndex < s.responses.count else {
        throw LLMError.generationFailed(
          description:
            "MockLLMService exhausted: \(s.callIndex) calls made, only \(s.responses.count) responses available"
        )
      }
      let response = s.responses[s.callIndex]
      s.callIndex += 1
      s.capturedPrompts.append((system: system, user: user))
      return response
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
    state.withLock { s in
      s.callIndex = 0
      s.capturedPrompts = []
    }
  }
}
