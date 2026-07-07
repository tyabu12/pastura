import Testing

@testable import Pastura

/// ADR-021 D1/D2 turn-degradation coverage for `SpeakEachHandler`, split
/// into a sibling file per `.claude/rules/testing.md` § "Splitting a Suite
/// Across Files". The shared-gate circuit breaker (D4) is gate-level and
/// already covered once, on `SpeakAllHandler`
/// (`SpeakAllHandlerTests+TurnDegradation.swift`) — not repeated here.
extension SpeakEachHandlerTests {
  @Test func transientFailureSkipsTurnAndOthersStillSpeak() async throws {
    // Alice's call throws a transient (turn-degradable) error; Bob and
    // Charlie still get to speak in the same sub-round.
    let mock = MockLLMService(responses: [
      #"{"statement": "hello from Bob"}"#,
      #"{"statement": "hello from Charlie"}"#
    ])
    try await mock.loadModel()
    mock.throwErrorOnNextGenerate(.generationFailed(description: "transient blip"), count: 1)

    let scenario = makeTestScenario(
      phases: [
        Phase(type: .speakEach, prompt: "Talk", outputSchema: ["statement": "string"])
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    // Stale prior-round output — must be cleared on skip (ADR-021 D2).
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
    #expect(skipped.first?.1 == .speakEach)

    #expect(state.lastOutputs["Alice"] == nil)
    #expect(state.lastOutputs["Bob"]?.statement == "hello from Bob")
    #expect(state.lastOutputs["Charlie"]?.statement == "hello from Charlie")
  }

  @Test func systemicErrorPropagatesTypedWithoutSkip() async throws {
    // ADR-021 D3: a systemic error (invalidGrammar) must abort the run in
    // one throw, typed, without being converted into a skip.
    let mock = MockLLMService(responses: [])
    try await mock.loadModel()
    mock.throwErrorOnNextGenerate(.invalidGrammar(description: "grammar bug"), count: 1)

    let scenario = makeTestScenario(
      phases: [
        Phase(type: .speakEach, prompt: "Talk", outputSchema: ["statement": "string"])
      ]
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
