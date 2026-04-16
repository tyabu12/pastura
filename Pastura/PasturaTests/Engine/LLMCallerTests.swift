import Foundation
import Testing
import os

@testable import Pastura

struct LLMCallerTests {
  let caller = LLMCaller()

  @Test func parsesValidJSONOnFirstAttempt() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "hello", "inner_thought": "thinking"}"#
    ])
    try await mock.loadModel()

    let collector = EventCollector()
    let result = try await caller.call(
      llm: mock, system: "sys", user: "usr", agentName: "Alice",
      emitter: collector.emit
    )

    #expect(result.statement == "hello")
    #expect(mock.generateCallCount == 1)
  }

  @Test func retriesOnJSONParseFailure() async throws {
    let mock = MockLLMService(responses: [
      "not json at all",
      #"{"statement": "ok"}"#
    ])
    try await mock.loadModel()

    let collector = EventCollector()
    let result = try await caller.call(
      llm: mock, system: "sys", user: "usr", agentName: "Alice",
      emitter: collector.emit
    )

    #expect(result.statement == "ok")
    #expect(mock.generateCallCount == 2)
  }

  @Test func retriesOnEmptyField() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "...", "action": "cooperate"}"#,
      #"{"statement": "real answer", "action": "cooperate"}"#
    ])
    try await mock.loadModel()

    let collector = EventCollector()
    let result = try await caller.call(
      llm: mock, system: "sys", user: "usr", agentName: "Alice",
      emitter: collector.emit
    )

    #expect(result.statement == "real answer")
    #expect(mock.generateCallCount == 2)
  }

  @Test func throwsRetriesExhaustedAfterMaxRetries() async throws {
    let mock = MockLLMService(responses: [
      "bad1", "bad2", "bad3"
    ])
    try await mock.loadModel()

    let collector = EventCollector()
    await #expect(throws: SimulationError.self) {
      try await caller.call(
        llm: mock, system: "sys", user: "usr", agentName: "Alice",
        emitter: collector.emit
      )
    }
    #expect(mock.generateCallCount == 3)
  }

  @Test func emitsInferenceStartedAndCompleted() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "hello"}"#
    ])
    try await mock.loadModel()

    let collector = EventCollector()
    _ = try await caller.call(
      llm: mock, system: "sys", user: "usr", agentName: "Alice",
      emitter: collector.emit
    )

    let events = collector.events
    let startEvents = events.filter {
      if case .inferenceStarted(let name) = $0 { return name == "Alice" }
      return false
    }
    let completeEvents = events.filter {
      if case .inferenceCompleted(let name, _, _) = $0 { return name == "Alice" }
      return false
    }
    #expect(startEvents.count >= 1)
    #expect(completeEvents.count >= 1)
  }

  @Test func wrapsLLMErrorAsSimulationError() async throws {
    let mock = MockLLMService(responses: [])
    try await mock.loadModel()

    let collector = EventCollector()
    await #expect(throws: SimulationError.self) {
      try await caller.call(
        llm: mock, system: "sys", user: "usr", agentName: "Alice",
        emitter: collector.emit
      )
    }
  }
}
