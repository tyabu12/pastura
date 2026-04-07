import Testing

@testable import Pastura

struct EliminateHandlerTests {
  let handler = EliminateHandler()

  @Test func eliminatesMostVotedAgent() async throws {
    let mock = MockLLMService(responses: [])
    let scenario = makeTestScenario(phases: [Phase(type: .eliminate)])
    var state = SimulationState.initial(for: scenario)
    state.voteResults = ["Alice": 2, "Bob": 1]
    let collector = EventCollector()

    try await handler.execute(
      scenario: scenario, phase: scenario.phases[0], state: &state,
      llm: mock, emitter: collector.emit
    )

    #expect(state.eliminated["Alice"] == true)
    #expect(state.eliminated["Bob"] != true)
  }

  @Test func emitsEliminationEvent() async throws {
    let mock = MockLLMService(responses: [])
    let scenario = makeTestScenario(phases: [Phase(type: .eliminate)])
    var state = SimulationState.initial(for: scenario)
    state.voteResults = ["Bob": 3]
    let collector = EventCollector()

    try await handler.execute(
      scenario: scenario, phase: scenario.phases[0], state: &state,
      llm: mock, emitter: collector.emit
    )

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

    try await handler.execute(
      scenario: scenario, phase: scenario.phases[0], state: &state,
      llm: mock, emitter: collector.emit
    )

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

    try await handler.execute(
      scenario: scenario, phase: scenario.phases[0], state: &state,
      llm: mock, emitter: collector.emit
    )

    // One agent should be eliminated (deterministic: sorted by name)
    let eliminatedCount = state.eliminated.values.filter { $0 }.count
    #expect(eliminatedCount == 1)
  }
}
