import Foundation
import Testing

@testable import Pastura

/// Exercises the default `generateStream` implementation on `LLMService`
/// (the protocol extension that wraps `generateWithMetrics`).
/// `LlamaCppService` overrides this with a real streaming implementation
/// (item 3); those tests live elsewhere. These tests assert the default
/// wrap behaves correctly so backends that don't override — `MockLLMService`
/// and `OllamaService` today — still satisfy the streaming contract.
@Suite(.timeLimit(.minutes(1)))
struct LLMServiceStreamTests {

  // MARK: - Chunk value semantics

  @Test func chunkEqualityHoldsOnSameFields() {
    let lhs = LLMStreamChunk(delta: "hi", isFinal: true, completionTokens: 2)
    let rhs = LLMStreamChunk(delta: "hi", isFinal: true, completionTokens: 2)
    #expect(lhs == rhs)
  }

  @Test func chunkEqualityFailsOnDifferentFields() {
    let base = LLMStreamChunk(delta: "hi", isFinal: true, completionTokens: 2)
    #expect(base != LLMStreamChunk(delta: "hi!", isFinal: true, completionTokens: 2))
    #expect(base != LLMStreamChunk(delta: "hi", isFinal: false, completionTokens: 2))
    #expect(base != LLMStreamChunk(delta: "hi", isFinal: true, completionTokens: 3))
  }

  // MARK: - Default wrap: success path

  @Test func defaultWrapYieldsSingleFinalChunkWithFullText() async throws {
    let mock = MockLLMService(responses: ["hello world"])
    try await mock.loadModel()

    var collected: [LLMStreamChunk] = []
    for try await chunk in mock.generateStream(system: "sys", user: "usr") {
      collected.append(chunk)
    }

    #expect(collected.count == 1)
    #expect(collected.first?.delta == "hello world")
    #expect(collected.first?.isFinal == true)
    // MockLLMService does not report token counts, so the default wrap
    // surfaces `nil` here — the contract is "populated only when the
    // backend can cheaply report it."
    #expect(collected.first?.completionTokens == nil)
  }

  @Test func defaultWrapCapturesSystemAndUserPrompts() async throws {
    let mock = MockLLMService(responses: ["ok"])
    try await mock.loadModel()

    for try await _ in mock.generateStream(system: "SYS", user: "USR") {}

    let prompts = mock.capturedPrompts
    #expect(prompts.count == 1)
    #expect(prompts.first?.system == "SYS")
    #expect(prompts.first?.user == "USR")
  }

  // MARK: - Default wrap: error propagation

  @Test func defaultWrapPropagatesErrorsFromGenerate() async throws {
    // No responses configured → MockLLMService throws when generate is called.
    let mock = MockLLMService(responses: [])
    try await mock.loadModel()

    await #expect(throws: (any Error).self) {
      for try await _ in mock.generateStream(system: "s", user: "u") {}
    }
  }

  @Test func defaultWrapSurfacesNotLoadedBeforeLoad() async throws {
    let mock = MockLLMService(responses: ["x"])
    // Intentionally skip loadModel() — generate should throw .notLoaded.

    await #expect(throws: (any Error).self) {
      for try await _ in mock.generateStream(system: "s", user: "u") {}
    }
  }

  // MARK: - MockLLMService streaming mode

  @Test func mockStreamingEmitsConfiguredDeltasThenFinal() async throws {
    let mock = MockLLMService(responses: [])
    mock.setStreamChunks([["hel", "lo ", "world"]])
    try await mock.loadModel()

    var deltas: [String] = []
    var finalCount = 0
    for try await chunk in mock.generateStream(system: "s", user: "u") {
      if chunk.isFinal {
        finalCount += 1
        #expect(chunk.delta.isEmpty)
        #expect(chunk.completionTokens == nil)
      } else {
        deltas.append(chunk.delta)
      }
    }

    #expect(deltas == ["hel", "lo ", "world"])
    #expect(finalCount == 1)
    #expect(mock.streamCallCount == 1)
  }

  @Test func mockStreamingCapturesPromptsLikeGenerate() async throws {
    let mock = MockLLMService(responses: [])
    mock.setStreamChunks([["a"], ["b"]])
    try await mock.loadModel()

    for try await _ in mock.generateStream(system: "SYS1", user: "USR1") {}
    for try await _ in mock.generateStream(system: "SYS2", user: "USR2") {}

    let prompts = mock.capturedPrompts
    #expect(prompts.count == 2)
    #expect(prompts[0].system == "SYS1")
    #expect(prompts[1].user == "USR2")
  }

  @Test func mockStreamingExhaustionThrows() async throws {
    let mock = MockLLMService(responses: [])
    mock.setStreamChunks([["only one call"]])
    try await mock.loadModel()

    for try await _ in mock.generateStream(system: "s", user: "u") {}

    await #expect(throws: (any Error).self) {
      for try await _ in mock.generateStream(system: "s", user: "u") {}
    }
  }

  @Test func mockStreamingHonorsPendingSuspend() async throws {
    let mock = MockLLMService(responses: [])
    mock.setStreamChunks([["x"]])
    try await mock.loadModel()
    mock.simulateSuspendOnNextGenerate()

    await #expect(throws: LLMError.suspended) {
      for try await _ in mock.generateStream(system: "s", user: "u") {}
    }

    // Suspend consumed — next call succeeds.
    var deltas: [String] = []
    for try await chunk in mock.generateStream(system: "s", user: "u")
    where !chunk.isFinal {
      deltas.append(chunk.delta)
    }
    #expect(deltas == ["x"])
  }
}
