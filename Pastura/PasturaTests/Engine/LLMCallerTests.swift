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
      suspendController: SuspendController(),
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
      suspendController: SuspendController(),
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
      suspendController: SuspendController(),
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
        suspendController: SuspendController(),
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
      suspendController: SuspendController(),
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
        suspendController: SuspendController(),
        emitter: collector.emit
      )
    }
  }

  // MARK: - Suspend / resume

  @Test func suspendThrowDoesNotConsumeRetryBudget() async throws {
    // Three suspend throws then a valid response. Without the no-consume
    // contract, the parse-retry budget (2) would be exhausted and the call
    // would fail. With it, all suspends are absorbed transparently.
    let mock = MockLLMService(responses: [#"{"statement": "ok"}"#])
    try await mock.loadModel()
    mock.simulateSuspendOnNextGenerate()
    mock.simulateSuspendOnNextGenerate()
    mock.simulateSuspendOnNextGenerate()

    let collector = EventCollector()
    let result = try await caller.call(
      llm: mock, system: "s", user: "u", agentName: "Alice",
      suspendController: SuspendController(),
      emitter: collector.emit
    )

    #expect(result.statement == "ok")
    // generateCallCount counts responses consumed (not generate attempts).
    // Suspend throws don't consume a response slot, so the 3 suspends leave
    // the counter at exactly 1 from the final successful response.
    #expect(mock.generateCallCount == 1)
  }

  @Test func suspendCycleAwaitsControllerResume() async throws {
    // Real controller path: mock consults the controller's suspend flag.
    // While suspended, LLMCaller parks on awaitResume; once resumed externally
    // the same prompt is re-issued and succeeds.
    let mock = MockLLMService(responses: [#"{"statement": "ok"}"#])
    try await mock.loadModel()
    let controller = SuspendController()
    await mock.attachSuspendController(controller)
    controller.requestSuspend()

    let collector = EventCollector()
    let callTask = Task<TurnOutput, Error> {
      try await caller.call(
        llm: mock, system: "s", user: "u", agentName: "Alice",
        suspendController: controller,
        emitter: collector.emit
      )
    }

    // Give the call time to hit the suspend and park.
    try await Task.sleep(for: .milliseconds(50))
    controller.resume()

    let result = try await callTask.value
    #expect(result.statement == "ok")
    // One response consumed — the first generate threw .suspended without
    // consuming a slot, the second returned the response.
    #expect(mock.generateCallCount == 1)
  }

  @Test func inferenceEventsEmittedOncePerAttemptAcrossSuspends() async throws {
    // Suspend retries within a single parse-attempt must NOT emit additional
    // inferenceStarted/Completed pairs — UI would otherwise flicker the
    // "thinking" indicator for every BG/FG cycle.
    let mock = MockLLMService(responses: [#"{"statement": "hi"}"#])
    try await mock.loadModel()
    mock.simulateSuspendOnNextGenerate()
    mock.simulateSuspendOnNextGenerate()

    let collector = EventCollector()
    _ = try await caller.call(
      llm: mock, system: "s", user: "u", agentName: "Alice",
      suspendController: SuspendController(),
      emitter: collector.emit
    )

    let started = collector.events.filter {
      if case .inferenceStarted(let name) = $0 { return name == "Alice" }
      return false
    }
    let completed = collector.events.filter {
      if case .inferenceCompleted(let name, _, _) = $0 { return name == "Alice" }
      return false
    }
    #expect(started.count == 1, "expected exactly 1 inferenceStarted, got \(started.count)")
    #expect(completed.count == 1, "expected exactly 1 inferenceCompleted, got \(completed.count)")
  }

  // MARK: - Streaming (agentOutputStream emission)

  @Test func emitsAgentOutputStreamPerDeltaDuringStreaming() async throws {
    // Configure Mock to return each part of the JSON as a separate
    // chunk. LLMCaller must run each accumulated buffer through the
    // partial extractor and emit an agentOutputStream snapshot per
    // non-empty delta.
    let mock = MockLLMService(responses: [])
    mock.setStreamChunks([
      [
        #"{"statement":""#,
        #"hel"#,
        #"lo"#,
        #"","inner_thought":"thinking"}"#
      ]
    ])
    try await mock.loadModel()

    let collector = EventCollector()
    let result = try await caller.call(
      llm: mock, system: "s", user: "u", agentName: "Alice",
      suspendController: SuspendController(),
      emitter: collector.emit
    )

    #expect(result.statement == "hello")
    #expect(result.innerThought == "thinking")

    // At least one agentOutputStream event per non-empty delta.
    let streamEvents = collector.events.compactMap { event -> (String?, String?)? in
      if case .agentOutputStream(_, let primary, let thought) = event {
        return (primary, thought)
      }
      return nil
    }
    #expect(
      streamEvents.count >= 4,
      "expected 4 stream events (one per delta), got \(streamEvents.count)")

    // Primary progresses: nil → "" (opening quote) → "hel" → "hello" (or later).
    // The final snapshot emitted must have primary == "hello".
    let lastStream = streamEvents.last
    #expect(lastStream?.0 == "hello")
  }

  @Test func streamSnapshotsArrayIsMonotonicOnPrimary() async throws {
    let mock = MockLLMService(responses: [])
    mock.setStreamChunks([
      [
        #"{"statement":""#,
        "a", "b", "c",
        #"","inner_thought":"x"}"#
      ]
    ])
    try await mock.loadModel()

    let collector = EventCollector()
    _ = try await caller.call(
      llm: mock, system: "s", user: "u", agentName: "Alice",
      suspendController: SuspendController(),
      emitter: collector.emit
    )

    // Extract non-nil primary values in emission order — each must be a
    // prefix of the next.
    let primaries: [String] = collector.events.compactMap { event in
      if case .agentOutputStream(_, let primary, _) = event {
        return primary
      }
      return nil
    }
    var previous = ""
    for primary in primaries {
      #expect(
        primary.hasPrefix(previous) || previous.isEmpty,
        "primary shrank: was \(previous), now \(primary)")
      previous = primary
    }
  }

  @Test func streamRetryOnParseFailureStartsFreshStream() async throws {
    // First stream yields garbage (parse fails), second yields valid JSON.
    // After the retry, the second stream's snapshots should reset the
    // consumer view — new emissions overwrite.
    let mock = MockLLMService(responses: [])
    mock.setStreamChunks([
      ["not json at all"],
      [#"{"statement":"ok"}"#]
    ])
    try await mock.loadModel()

    let collector = EventCollector()
    let result = try await caller.call(
      llm: mock, system: "s", user: "u", agentName: "Alice",
      suspendController: SuspendController(),
      emitter: collector.emit
    )

    #expect(result.statement == "ok")
    // Two inference cycles — one failed parse retry.
    let starts = collector.events.filter {
      if case .inferenceStarted = $0 { return true }
      return false
    }
    #expect(starts.count == 2, "expected 2 inferenceStarted, got \(starts.count)")
    #expect(mock.streamCallCount == 2)
  }

  @Test func cancellationDuringAwaitResumeBailsOut() async throws {
    // If the owning Task is cancelled while the controller is suspended,
    // the call must throw promptly instead of looping forever.
    let mock = MockLLMService(responses: [#"{"statement": "ok"}"#])
    try await mock.loadModel()
    let controller = SuspendController()
    await mock.attachSuspendController(controller)
    controller.requestSuspend()

    let collector = EventCollector()
    let callTask = Task<TurnOutput, Error> {
      try await caller.call(
        llm: mock, system: "s", user: "u", agentName: "Alice",
        suspendController: controller,
        emitter: collector.emit
      )
    }

    try await Task.sleep(for: .milliseconds(50))
    callTask.cancel()
    // awaitResume returns on cancel; Task.checkCancellation throws → wrapped
    // as SimulationError.llmGenerationFailed by LLMCaller.
    await #expect(throws: SimulationError.self) {
      _ = try await callTask.value
    }
  }
}
