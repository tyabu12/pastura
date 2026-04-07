import Testing

@testable import Pastura

struct ChooseHandlerTests {
  let handler = ChooseHandler()

  @Test func roundRobinCreatesPairsAndCallsLLM() async throws {
    // 3 agents → 3 adjacent pairs, 2 calls per pair = 6
    let mock = MockLLMService(responses: [
      #"{"action": "cooperate"}"#,
      #"{"action": "betray"}"#,
      #"{"action": "cooperate"}"#,
      #"{"action": "cooperate"}"#,
      #"{"action": "betray"}"#,
      #"{"action": "betray"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      phases: [
        Phase(
          type: .choose, prompt: "Choose!",
          outputSchema: ["action": "string"],
          options: ["cooperate", "betray"],
          pairing: .roundRobin
        )
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    try await handler.execute(
      scenario: scenario, phase: scenario.phases[0], state: &state,
      llm: mock, emitter: collector.emit
    )

    #expect(mock.generateCallCount == 6)
    #expect(state.pairings.count == 3)
  }

  @Test func emitsPairingResultForEachPair() async throws {
    let mock = MockLLMService(responses: [
      #"{"action": "cooperate"}"#,
      #"{"action": "betray"}"#,
      #"{"action": "cooperate"}"#,
      #"{"action": "cooperate"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [
        Phase(
          type: .choose, prompt: "Choose!",
          outputSchema: ["action": "string"],
          options: ["cooperate", "betray"],
          pairing: .roundRobin
        )
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    try await handler.execute(
      scenario: scenario, phase: scenario.phases[0], state: &state,
      llm: mock, emitter: collector.emit
    )

    let pairingEvents = collector.events.compactMap { event -> String? in
      if case .pairingResult(let a1, let act1, let a2, let act2) = event {
        return "\(a1)(\(act1)) vs \(a2)(\(act2))"
      }
      return nil
    }
    #expect(pairingEvents.count == 2)
  }

  @Test func fallsBackToFirstOptionOnInvalidChoice() async throws {
    // 2 agents → 2 adjacent pairs (Alice-Bob, Bob-Alice) → 4 LLM calls
    let mock = MockLLMService(responses: [
      #"{"action": "invalid_action"}"#,
      #"{"action": "cooperate"}"#,
      #"{"action": "cooperate"}"#,
      #"{"action": "betray"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [
        Phase(
          type: .choose, prompt: "Choose!",
          outputSchema: ["action": "string"],
          options: ["cooperate", "betray"],
          pairing: .roundRobin
        )
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    try await handler.execute(
      scenario: scenario, phase: scenario.phases[0], state: &state,
      llm: mock, emitter: collector.emit
    )

    // First pair: Alice-Bob. Alice chose "invalid_action" → falls back to "cooperate"
    #expect(state.pairings[0].action1 == "cooperate")
  }

  @Test func populatesPairingActions() async throws {
    // 2 agents → 2 adjacent pairs (Alice-Bob, Bob-Alice) → 4 LLM calls
    let mock = MockLLMService(responses: [
      #"{"action": "cooperate"}"#,
      #"{"action": "betray"}"#,
      #"{"action": "betray"}"#,
      #"{"action": "cooperate"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [
        Phase(
          type: .choose, prompt: "Choose!",
          outputSchema: ["action": "string"],
          options: ["cooperate", "betray"],
          pairing: .roundRobin
        )
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    try await handler.execute(
      scenario: scenario, phase: scenario.phases[0], state: &state,
      llm: mock, emitter: collector.emit
    )

    let pair = state.pairings[0]
    #expect(pair.agent1 == "Alice")
    #expect(pair.action1 == "cooperate")
    #expect(pair.agent2 == "Bob")
    #expect(pair.action2 == "betray")
  }

  @Test func individualChoiceCallsAllAgents() async throws {
    let mock = MockLLMService(responses: [
      #"{"action": "cooperate"}"#,
      #"{"action": "betray"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [
        Phase(
          type: .choose, prompt: "Choose!",
          outputSchema: ["action": "string"],
          options: ["cooperate", "betray"]
        )
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    try await handler.execute(
      scenario: scenario, phase: scenario.phases[0], state: &state,
      llm: mock, emitter: collector.emit
    )

    #expect(mock.generateCallCount == 2)
    // No pairings in individual mode
    #expect(state.pairings.isEmpty)
  }
}
