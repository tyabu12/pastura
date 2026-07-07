import Foundation
import Testing
import os

@testable import Pastura

// ADR-021 D3 failure-taxonomy tests, split from `LLMCallerTests.swift` as a
// sibling-file extension to stay under SwiftLint's `type_body_length` budget.
// Deliberately NOT a new `@Suite` — Swift Testing runs suites in parallel and
// `.serialized`/`.timeLimit` traits would not carry over (see
// `.claude/rules/testing.md` § "Splitting a Suite Across Files").
extension LLMCallerTests {
  @Test func notLoadedRethrowsTyped() async throws {
    // ADR-021 D3: `.notLoaded` is systemic (the backend lost its model
    // mid-run) — it must escape typed so the gate aborts the run instead
    // of degrading turn-by-turn into a zombie run.
    let mock = MockLLMService(responses: [#"{"statement": "should not be reached"}"#])
    try await mock.loadModel()
    mock.throwErrorOnNextGenerate(.notLoaded)

    let collector = EventCollector()
    await #expect(throws: LLMError.notLoaded) {
      try await caller.call(
        llm: mock, system: "sys", user: "usr", agentName: "Alice",
        suspendController: SuspendController(),
        emitter: collector.emit)
    }
    #expect(mock.generateCallCount == 0)
  }

  @Test func transientGenerationFailureStaysWrapped() async throws {
    // ADR-021 D3: transient stream/generation errors keep today's wrap —
    // SimulationError.llmGenerationFailed with a readable description —
    // which the gate classifies as turn-degradable.
    let mock = MockLLMService(responses: [#"{"statement": "should not be reached"}"#])
    try await mock.loadModel()
    mock.throwErrorOnNextGenerate(.generationFailed(description: "transient blip"))

    let collector = EventCollector()
    do {
      _ = try await caller.call(
        llm: mock, system: "sys", user: "usr", agentName: "Alice",
        suspendController: SuspendController(),
        emitter: collector.emit)
      Issue.record("expected the call to throw after a non-retryable stream failure")
    } catch let SimulationError.llmGenerationFailed(description) {
      #expect(description.contains("transient blip"))
    }
    #expect(mock.generateCallCount == 0)
  }
}
