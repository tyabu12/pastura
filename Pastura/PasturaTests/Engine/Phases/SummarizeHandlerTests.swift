import Testing

@testable import Pastura

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
    #expect(summaries[0] == "Votes: {vote_results}")
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
    #expect(summaries[0] == "Alice(cooperate)")
  }
}
