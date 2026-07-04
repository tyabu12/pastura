import Foundation
import Testing
import os

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
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
    mock.throwSuspendedOnNextGenerate()
    mock.throwSuspendedOnNextGenerate()
    mock.throwSuspendedOnNextGenerate()

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
    mock.throwSuspendedOnNextGenerate()
    mock.throwSuspendedOnNextGenerate()

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

  // #194 — the unfiltered LLM emission must travel with the parsed
  // TurnOutput so SimulationViewModel.persistTurnRecord can store it in
  // TurnRecord.rawOutput per the column's documented contract. Pre-#194
  // rawOutput silently received the parsed-and-re-encoded JSON; the
  // audit trail was load-bearingly broken before any A2 repair work
  // could safely land.
  @Test func resultCarriesRawTextThroughLLMCaller() async throws {
    let raw = #"{"statement": "hi", "inner_thought": "thinking"}"#
    let mock = MockLLMService(responses: [raw])
    try await mock.loadModel()

    let collector = EventCollector()
    let result = try await caller.call(
      llm: mock, system: "sys", user: "usr", agentName: "Alice",
      suspendController: SuspendController(),
      emitter: collector.emit
    )

    #expect(result.rawText == raw)
  }

  // MARK: - Sampler crash retry (#885)

  @Test func samplerCrashRetriesAndRecovers() async throws {
    // A caught sampler crash on the first attempt must NOT abort the run:
    // LLMCaller re-runs the inference and the second attempt succeeds.
    // Fails on revert — the pre-#885 catch rethrew the crash immediately.
    let mock = MockLLMService(responses: [#"{"statement": "recovered"}"#])
    try await mock.loadModel()
    mock.throwErrorOnNextGenerate(
      .samplerCrashCaught(
        description: "Unexpected empty grammar stack after accepting piece: この (8978)"))

    let collector = EventCollector()
    let result = try await caller.call(
      llm: mock, system: "sys", user: "usr", agentName: "Alice",
      suspendController: SuspendController(),
      emitter: collector.emit
    )

    #expect(result.statement == "recovered")
    // The crash attempt consumed no response; only the successful retry did.
    #expect(mock.generateCallCount == 1)
  }

  @Test func samplerCrashExhaustionCarriesWhatDetail() async throws {
    // Crash on all attempts (0...maxRetries) → the run fails, but the
    // final user-visible error must carry the caught `what()` detail.
    let what = "Unexpected empty grammar stack after accepting piece: この (8978)"
    let mock = MockLLMService(responses: [#"{"statement": "never reached"}"#])
    try await mock.loadModel()
    mock.throwErrorOnNextGenerate(.samplerCrashCaught(description: what), count: 3)

    let collector = EventCollector()
    do {
      _ = try await caller.call(
        llm: mock, system: "sys", user: "usr", agentName: "Alice",
        suspendController: SuspendController(),
        emitter: collector.emit)
      Issue.record("expected the run to fail after sampler-crash exhaustion")
    } catch let SimulationError.llmGenerationFailed(description) {
      #expect(description.contains(what))
      #expect(description.contains("Sampler crash caught"))
    }
    // The valid response was never consumed — all attempts crashed.
    #expect(mock.generateCallCount == 0)
  }

  @Test func nonSamplerErrorIsNotRetried() async throws {
    // `.invalidGrammar` (and any non-sampler backend throw) stays
    // fail-fast: LLMCaller must NOT retry it into the following valid
    // response. Guards the "only samplerCrashCaught is retryable"
    // contract, so cancellation / suspension can't be swallowed either.
    let mock = MockLLMService(responses: [#"{"statement": "should not be reached"}"#])
    try await mock.loadModel()
    mock.throwErrorOnNextGenerate(.invalidGrammar(description: "boom"))

    let collector = EventCollector()
    await #expect(throws: SimulationError.self) {
      try await caller.call(
        llm: mock, system: "sys", user: "usr", agentName: "Alice",
        suspendController: SuspendController(),
        emitter: collector.emit)
    }
    // No retry → the valid response was never consumed.
    #expect(mock.generateCallCount == 0)
  }
}
