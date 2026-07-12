import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct EliminateHandlerTests {
  let handler = EliminateHandler()

  @Test func eliminatesMostVotedAgent() async throws {
    let mock = MockLLMService(responses: [])
    let scenario = makeTestScenario(phases: [Phase(type: .eliminate)])
    var state = SimulationState.initial(for: scenario)
    state.voteResults = ["Alice": 2, "Bob": 1]
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(state.eliminated["Alice"] == true)
    #expect(state.eliminated["Bob"] != true)
  }

  @Test func emitsEliminationEvent() async throws {
    let mock = MockLLMService(responses: [])
    let scenario = makeTestScenario(phases: [Phase(type: .eliminate)])
    var state = SimulationState.initial(for: scenario)
    state.voteResults = ["Bob": 3]
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let eliminations = collector.events.compactMap { event -> (String, Int)? in
      if case .elimination(let agent, let count) = event { return (agent, count) }
      return nil
    }
    #expect(eliminations.count == 1)
    #expect(eliminations[0].0 == "Bob")
    #expect(eliminations[0].1 == 3)
  }

  @Test func handlesEmptyVoteResults() async throws {
    let mock = MockLLMService(responses: [])
    let scenario = makeTestScenario(phases: [Phase(type: .eliminate)])
    var state = SimulationState.initial(for: scenario)
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    // No one eliminated, no events
    #expect(state.eliminated.values.allSatisfy { $0 == false })
    #expect(collector.events.isEmpty)
  }

  @Test func handlesTiedVotes() async throws {
    let mock = MockLLMService(responses: [])
    let scenario = makeTestScenario(phases: [Phase(type: .eliminate)])
    var state = SimulationState.initial(for: scenario)
    state.voteResults = ["Alice": 2, "Bob": 2]
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    // Canonical tie-break: (count desc, name desc) — Bob sorts before Alice,
    // matching ConditionEvaluator's `vote_winner` derivation (#1056).
    #expect(state.eliminated["Bob"] == true)
    #expect(state.eliminated["Alice"] != true)
    #expect(state.eliminated.values.filter { $0 }.count == 1)
  }

  /// The agent `EliminateHandler` removes on a tie must be the SAME agent
  /// `ConditionEvaluator` resolves `vote_winner` to — otherwise an
  /// `eliminate` phase and a `conditional` phase reading `vote_winner` in the
  /// same round silently disagree about who won (#1056).
  @Test func tieWinnerMatchesVoteWinner() async throws {
    let mock = MockLLMService(responses: [])
    let scenario = makeTestScenario(phases: [Phase(type: .eliminate)])
    var state = SimulationState.initial(for: scenario)
    state.voteResults = ["Alice": 2, "Bob": 2]
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    // EliminateHandler eliminates Bob (canonical tie-break).
    #expect(state.eliminated["Bob"] == true)

    // ConditionEvaluator resolves `vote_winner` to the same agent (Bob).
    let evaluator = ConditionEvaluator()
    #expect(
      try evaluator.evaluate("vote_winner == \"Bob\"", state: state, scenario: scenario).value)
    #expect(
      try !evaluator.evaluate("vote_winner == \"Alice\"", state: state, scenario: scenario).value)
  }
}
