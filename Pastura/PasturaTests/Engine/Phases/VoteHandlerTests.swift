import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct VoteHandlerTests {
  let handler = VoteHandler()

  @Test func collectsVotesFromAllAgents() async throws {
    let mock = MockLLMService(responses: [
      #"{"vote": "Bob", "reason": "suspicious"}"#,
      #"{"vote": "Alice", "reason": "quiet"}"#,
      #"{"vote": "Alice", "reason": "weird"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      phases: [
        Phase(
          type: .vote, prompt: "Vote!", outputSchema: ["vote": "string", "reason": "string"],
          excludeSelf: true)
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(state.voteResults["Alice"] == 2)
    #expect(state.voteResults["Bob"] == 1)
    #expect(mock.generateCallCount == 3)
  }

  @Test func emitsVoteResultsEvent() async throws {
    let mock = MockLLMService(responses: [
      #"{"vote": "Bob"}"#,
      #"{"vote": "Alice"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [Phase(type: .vote, prompt: "Vote!", outputSchema: ["vote": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let voteEvents = collector.events.compactMap { event -> ([String: String], [String: Int])? in
      if case .voteResults(let votes, let tallies) = event { return (votes, tallies) }
      return nil
    }
    #expect(voteEvents.count == 1)
    #expect(voteEvents[0].0["Alice"] == "Bob")
    #expect(voteEvents[0].0["Bob"] == "Alice")
  }

  @Test func skipsEliminatedAgents() async throws {
    let mock = MockLLMService(responses: [
      #"{"vote": "Charlie"}"#,
      #"{"vote": "Alice"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      phases: [Phase(type: .vote, prompt: "Vote!", outputSchema: ["vote": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    state.eliminated["Bob"] = true
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(mock.generateCallCount == 2)
  }

  @Test func populatesVoteResultsStateVariable() async throws {
    // Key must be "vote_results" (plural) to match the {vote_results} placeholder
    // documented in PhaseEditorSheet and used by the word_wolf preset.
    let mock = MockLLMService(responses: [
      #"{"vote": "Bob"}"#,
      #"{"vote": "Alice"}"#,
      #"{"vote": "Alice"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      phases: [Phase(type: .vote, prompt: "Vote!", outputSchema: ["vote": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(state.variables["vote_results"] == #"{"Alice": 2, "Bob": 1}"#)
    #expect(state.variables["vote_result"] == nil)
  }

  @Test func acceptsInvalidVoteTarget() async throws {
    let mock = MockLLMService(responses: [
      #"{"vote": "NonExistent"}"#,
      #"{"vote": "Alice"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [Phase(type: .vote, prompt: "Vote!", outputSchema: ["vote": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    // Invalid vote counted dynamically
    #expect(state.voteResults["NonExistent"] == 1)
    #expect(state.voteResults["Alice"] == 1)
  }

  // MARK: - simulationLanguage override (ADR-010 Step E)

  @Test func voteHonorsSimulationLanguageOverride_jaToEn() async throws {
    // Scenario: ja authoring, en simulation override. prompt:nil forces fallback.
    // The captured prompt must contain the English fallback, not the Japanese one.
    let mock = MockLLMService(responses: [
      #"{"vote": "Bob"}"#,
      #"{"vote": "Alice"}"#
    ])
    try await mock.loadModel()

    let scenario = ScenarioFixture.make(
      language: "ja",
      simulationLanguage: "en",
      personas: [
        Persona(name: "Alice", description: "A test persona"),
        Persona(name: "Bob", description: "A test persona")
      ],
      phases: [Phase(type: .vote, prompt: nil, outputSchema: ["vote": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let prompt = mock.capturedPrompts[0].user
    #expect(prompt.contains("Vote for the person"))
    #expect(!prompt.contains("最も怪しい"))
  }

  @Test func voteHonorsSimulationLanguageOverride_enToJa() async throws {
    // Reverse: en authoring, ja simulation override. Captured prompt must contain Japanese.
    let mock = MockLLMService(responses: [
      #"{"vote": "Bob"}"#,
      #"{"vote": "Alice"}"#
    ])
    try await mock.loadModel()

    let scenario = ScenarioFixture.make(
      language: "en",
      simulationLanguage: "ja",
      personas: [
        Persona(name: "Alice", description: "A test persona"),
        Persona(name: "Bob", description: "A test persona")
      ],
      phases: [Phase(type: .vote, prompt: nil, outputSchema: ["vote": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let prompt = mock.capturedPrompts[0].user
    #expect(prompt.contains("最も怪しい"))
    #expect(!prompt.contains("Vote for the person"))
  }
}
