import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
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

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

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

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let pairingEvents = collector.events.compactMap { event -> String? in
      if case .pairingResult(let agent1, let action1, let agent2, let action2) = event {
        return "\(agent1)(\(action1)) vs \(agent2)(\(action2))"
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

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

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

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

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

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(mock.generateCallCount == 2)
    // No pairings in individual mode
    #expect(state.pairings.isEmpty)
  }
}
