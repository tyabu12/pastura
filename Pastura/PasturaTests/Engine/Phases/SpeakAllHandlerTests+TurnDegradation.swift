import Testing

@testable import Pastura

/// ADR-021 D1/D2 turn-degradation coverage for `SpeakAllHandler`, split into
/// a sibling file per `.claude/rules/testing.md` § "Splitting a Suite Across
/// Files" — `SpeakAllHandlerTests.swift` is already near the
/// `type_body_length` budget. `TurnFailureGate` internals (classification,
/// consecutive-count bookkeeping) are covered by `TurnFailureGateTests`;
/// these tests only pin the HANDLER's integration with the gate.
extension SpeakAllHandlerTests {
  @Test func transientFailureSkipsTurnAndOthersStillSpeak() async throws {
    // Alice's call throws a transient (turn-degradable) error; Bob and
    // Charlie still get to speak.
    let mock = MockLLMService(responses: [
      #"{"statement": "hello from Bob"}"#,
      #"{"statement": "hello from Charlie"}"#
    ])
    try await mock.loadModel()
    mock.throwErrorOnNextGenerate(.generationFailed(description: "transient blip"), count: 1)

    let scenario = makeTestScenario(
      phases: [Phase(type: .speakAll, prompt: "Speak!", outputSchema: ["statement": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    // Stale prior-round output — must be cleared on skip (ADR-021 D2), not
    // left readable by later phases.
    state.lastOutputs["Alice"] = TurnOutput(fields: ["statement": "stale"])
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let agentOutputs = collector.events.compactMap { event -> String? in
      if case .agentOutput(let agent, _, _) = event { return agent }
      return nil
    }
    #expect(agentOutputs == ["Bob", "Charlie"])

    // No conversationLog entry written for the skipped turn.
    #expect(state.conversationLog.map(\.agentName) == ["Bob", "Charlie"])

    let skipped = collector.events.compactMap { event -> (String, PhaseType)? in
      if case .turnSkipped(let agent, let phaseType, _) = event { return (agent, phaseType) }
      return nil
    }
    #expect(skipped.count == 1)
    #expect(skipped.first?.0 == "Alice")
    #expect(skipped.first?.1 == .speakAll)

    #expect(state.lastOutputs["Alice"] == nil)
    #expect(state.lastOutputs["Bob"]?.statement == "hello from Bob")
    #expect(state.lastOutputs["Charlie"]?.statement == "hello from Charlie")
  }

  @Test func thirdConsecutiveFailureTripsBreakerAndAbortsPhase() async throws {
    // ADR-021 D4: all three personas fail transiently on a shared gate —
    // skips 1 and 2 emit .turnSkipped, the 3rd trips the breaker instead.
    let mock = MockLLMService(responses: [])
    try await mock.loadModel()
    mock.throwErrorOnNextGenerate(.generationFailed(description: "dead backend"), count: 3)

    let scenario = makeTestScenario(
      phases: [Phase(type: .speakAll, prompt: "Speak!", outputSchema: ["statement": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)

    await #expect(throws: SimulationError.turnFailureLimitReached(consecutiveCount: 3)) {
      try await handler.execute(context: context, state: &state)
    }

    let skipped = collector.events.filter {
      if case .turnSkipped = $0 { return true }
      return false
    }
    #expect(skipped.count == 2)
  }

  @Test func systemicErrorPropagatesTypedWithoutSkip() async throws {
    // ADR-021 D3: a systemic error (invalidGrammar) must abort the run in
    // one throw, typed, without being converted into a skip.
    let mock = MockLLMService(responses: [])
    try await mock.loadModel()
    mock.throwErrorOnNextGenerate(.invalidGrammar(description: "grammar bug"), count: 1)

    let scenario = makeTestScenario(
      phases: [Phase(type: .speakAll, prompt: "Speak!", outputSchema: ["statement": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)

    await #expect(throws: LLMError.invalidGrammar(description: "grammar bug")) {
      try await handler.execute(context: context, state: &state)
    }

    let skipped = collector.events.filter {
      if case .turnSkipped = $0 { return true }
      return false
    }
    #expect(skipped.isEmpty)
  }
}
