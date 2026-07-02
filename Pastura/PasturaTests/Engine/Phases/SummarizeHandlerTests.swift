import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct SummarizeHandlerTests {
  let handler = SummarizeHandler()

  @Test func expandsTemplateWithVariables() async throws {
    let mock = MockLLMService(responses: [])
    let scenario = makeTestScenario(
      phases: [Phase(type: .summarize, template: "Round {current_round} done")]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 3
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.count == 1)
    #expect(summaries[0] == "Round 3 done")
  }

  @Test func expandsPairingTemplate() async throws {
    let mock = MockLLMService(responses: [])
    let scenario = makeTestScenario(
      phases: [
        Phase(type: .summarize, template: "{agent1}({action1}) vs {agent2}({action2})")
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    state.pairings = [
      Pairing(agent1: "Alice", agent2: "Bob", action1: "cooperate", action2: "betray")
    ]
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.count == 1)
    #expect(summaries[0] == "Alice(cooperate) vs Bob(betray)")
  }

  @Test func emitsSummaryEvent() async throws {
    let mock = MockLLMService(responses: [])
    let scenario = makeTestScenario(
      phases: [Phase(type: .summarize)]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.count == 1)
  }

  // MARK: - Simple path: derived variables

  @Test func expandsScoreboardInSimplePath() async throws {
    let mock = MockLLMService(responses: [])
    let scenario = makeTestScenario(
      phases: [Phase(type: .summarize, template: "Score: {scoreboard}")]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    state.scores = ["Alice": 2, "Bob": 1]
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.count == 1)
    #expect(summaries[0] == #"Score: {"Alice": 2, "Bob": 1}"#)
  }

  @Test func expandsVoteResultsInSimplePath() async throws {
    let mock = MockLLMService(responses: [])
    let scenario = makeTestScenario(
      phases: [Phase(type: .summarize, template: "Votes: {vote_results}")]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    state.variables["vote_results"] = #"{"Alice": 2}"#
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.count == 1)
    #expect(summaries[0] == #"Votes: {"Alice": 2}"#)
  }

  @Test func leavesVoteResultsLiteralWhenUnset() async throws {
    // Documents current behavior: when a preceding vote phase has not populated
    // state.variables["vote_results"], the placeholder remains literal.
    let mock = MockLLMService(responses: [])
    let scenario = makeTestScenario(
      phases: [Phase(type: .summarize, template: "Votes: {vote_results}")]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.count == 1)
    #expect(summaries[0] == "Votes: {vote_results}")
  }

  @Test func expandsConversationLogInSimplePath() async throws {
    let mock = MockLLMService(responses: [])
    let scenario = makeTestScenario(
      phases: [Phase(type: .summarize, template: "Log:\n{conversation_log}")]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    state.conversationLog = [
      ConversationEntry(agentName: "Alice", content: "hello", phaseType: .speakEach, round: 1)
    ]
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.count == 1)
    // formatConversationLog renders "  agentName: content"; the placeholder must
    // not survive literally (regression for #862).
    #expect(summaries[0] == "Log:\n  Alice: hello")
  }

  // MARK: - Pair path: derived variables

  @Test func expandsScoreboardInPairPath() async throws {
    let mock = MockLLMService(responses: [])
    let scenario = makeTestScenario(
      phases: [
        Phase(type: .summarize, template: "{agent1} vs {agent2} | board: {scoreboard}")
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    state.scores = ["Alice": 3, "Bob": 0]
    state.pairings = [
      Pairing(agent1: "Alice", agent2: "Bob", action1: "cooperate", action2: "betray")
    ]
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.count == 1)
    #expect(summaries[0] == #"Alice vs Bob | board: {"Alice": 3, "Bob": 0}"#)
  }

  @Test func pairingVarsTakePrecedenceOverStateVariables() async throws {
    // Pair-specific vars (agent1, action1, score1, …) must not be overridden by
    // user-defined state.variables of the same name.
    let mock = MockLLMService(responses: [])
    let scenario = makeTestScenario(
      phases: [Phase(type: .summarize, template: "{agent1}({action1})")]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    state.variables["agent1"] = "HIJACKED"
    state.variables["action1"] = "HIJACKED"
    state.pairings = [
      Pairing(agent1: "Alice", agent2: "Bob", action1: "cooperate", action2: "betray")
    ]
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.count == 1)
    #expect(summaries[0] == "Alice(cooperate)")
  }

  @Test func expandsConversationLogInPairPath() async throws {
    // Template carries both {agent1} and {conversation_log} with non-empty
    // pairings so the L21 gate routes into the per-pairing loop path (#862).
    let mock = MockLLMService(responses: [])
    let scenario = makeTestScenario(
      phases: [Phase(type: .summarize, template: "{agent1} log:\n{conversation_log}")]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    state.pairings = [
      Pairing(agent1: "Alice", agent2: "Bob", action1: "cooperate", action2: "betray")
    ]
    state.conversationLog = [
      ConversationEntry(agentName: "Bob", content: "hi", phaseType: .speakEach, round: 1)
    ]
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.count == 1)
    #expect(summaries[0] == "Alice log:\n  Bob: hi")
  }

  // MARK: - simulationLanguage override (ADR-010 Step E)

  @Test func summarizeHonorsSimulationLanguageOverride_jaToEn() async throws {
    // Scenario: ja authoring, en simulation override. template:nil forces fallback.
    // After {current_round} expansion, the summary must contain the English fallback.
    let mock = MockLLMService(responses: [])
    let scenario = ScenarioFixture.make(
      language: "ja",
      simulationLanguage: "en",
      phases: [Phase(type: .summarize, template: nil)]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 2
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.count == 1)
    #expect(summaries[0].contains("Round"))
    #expect(!summaries[0].contains("ラウンド"))
  }

  @Test func summarizeHonorsSimulationLanguageOverride_enToJa() async throws {
    // Reverse: en authoring, ja simulation override. Summary must contain Japanese.
    let mock = MockLLMService(responses: [])
    let scenario = ScenarioFixture.make(
      language: "en",
      simulationLanguage: "ja",
      phases: [Phase(type: .summarize, template: nil)]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 2
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.count == 1)
    #expect(summaries[0].contains("ラウンド"))
    #expect(!summaries[0].contains("Round"))
  }
}
