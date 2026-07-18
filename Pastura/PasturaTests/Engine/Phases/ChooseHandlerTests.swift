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

  @Test func dropsPairingAndEmitsActionRejectedOnGenuineOffMenuAction() async throws {
    // ADR-021 § Amendment 2026-07-17 (#1151): an off-menu action no longer
    // falls back to `options[0]` (fabricating a cooperate) — the whole pairing
    // is dropped and `.actionRejected` is emitted carrying the raw value.
    // 2 agents → 2 adjacent pairs (Alice-Bob, Bob-Alice) → 4 LLM calls.
    let mock = MockLLMService(responses: [
      #"{"action": "invalid_action"}"#,  // Alice, pair 1 — off-menu
      #"{"action": "cooperate"}"#,  // Bob, pair 1
      #"{"action": "cooperate"}"#,  // Bob, pair 2
      #"{"action": "betray"}"#  // Alice, pair 2
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

    // Pair 1 dropped (Alice off-menu); only pair 2 survives — no fabricated
    // cooperate for Alice.
    #expect(state.pairings.count == 1)
    #expect(state.pairings[0].agent1 == "Bob")
    #expect(state.pairings[0].action2 == "betray")

    // Exactly one `.actionRejected`, for Alice, carrying the verbatim raw value.
    let rejections = collector.events.compactMap { event -> (String, String)? in
      if case .actionRejected(let agent, _, let raw) = event { return (agent, raw) }
      return nil
    }
    #expect(rejections.count == 1)
    #expect(rejections.first?.0 == "Alice")
    #expect(rejections.first?.1 == "invalid_action")
    // The dropped pairing emits no `.pairingResult` — only pair 2's.
    let pairingEvents = collector.events.filter {
      if case .pairingResult = $0 { return true }
      return false
    }
    #expect(pairingEvents.count == 1)
  }

  @Test func caseVariantActionScoresAsCanonicalOptionRatherThanDropping() async throws {
    // ADR-021 § Amendment 2026-07-17 regression: a case/whitespace variant
    // (`"Betray"`) must normalize onto the canonical `betray` and SCORE, not
    // drop — the normalization in `validateAction` step 1 is what makes this
    // pass. Reverting that fold would drop the pairing and fail here.
    // 2 agents → 2 pairs → 4 LLM calls.
    let mock = MockLLMService(responses: [
      #"{"action": "Betray"}"#,  // Alice, pair 1 — case variant
      #"{"action": "cooperate"}"#,  // Bob, pair 1
      #"{"action": "cooperate"}"#,  // Bob, pair 2
      #"{"action": "betray"}"#  // Alice, pair 2
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

    // Both pairings scored — nothing dropped.
    #expect(state.pairings.count == 2)
    // Pair 1: Alice's `"Betray"` canonicalized to the option string `betray`,
    // NOT stored as the raw `"Betray"` (load-bearing for exact-match consumers
    // like PairwisePayoffLogic / RelationshipUpdateHandler).
    #expect(state.pairings[0].agent1 == "Alice")
    #expect(state.pairings[0].action1 == "betray")
    // No rejection emitted.
    let rejected = collector.events.contains {
      if case .actionRejected = $0 { return true }
      return false
    }
    #expect(!rejected)
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

  // MARK: - simulationLanguage override (ADR-010 Step E)

  @Test func chooseHonorsSimulationLanguageOverride_jaToEn() async throws {
    // Scenario: ja authoring, en simulation override. prompt:nil forces fallback.
    // The captured prompt must contain the English fallback, not the Japanese one.
    let mock = MockLLMService(responses: [
      #"{"action": "cooperate"}"#,
      #"{"action": "betray"}"#
    ])
    try await mock.loadModel()

    let scenario = ScenarioFixture.make(
      language: "ja",
      simulationLanguage: "en",
      personas: [
        Persona(name: "Alice", description: "A test persona"),
        Persona(name: "Bob", description: "A test persona")
      ],
      phases: [
        Phase(
          type: .choose, prompt: nil,
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

    let prompt = mock.capturedPrompts[0].user
    #expect(prompt.contains("Make a choice"))
    #expect(!prompt.contains("選択してください"))
  }

  @Test func chooseHonorsSimulationLanguageOverride_enToJa() async throws {
    // Reverse: en authoring, ja simulation override. Captured prompt must contain Japanese.
    let mock = MockLLMService(responses: [
      #"{"action": "cooperate"}"#,
      #"{"action": "betray"}"#
    ])
    try await mock.loadModel()

    let scenario = ScenarioFixture.make(
      language: "en",
      simulationLanguage: "ja",
      personas: [
        Persona(name: "Alice", description: "A test persona"),
        Persona(name: "Bob", description: "A test persona")
      ],
      phases: [
        Phase(
          type: .choose, prompt: nil,
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

    let prompt = mock.capturedPrompts[0].user
    #expect(prompt.contains("選択してください"))
    #expect(!prompt.contains("Make a choice"))
  }
}
