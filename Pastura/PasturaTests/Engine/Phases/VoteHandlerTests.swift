import Testing

@testable import Pastura

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

    try await handler.execute(
      scenario: scenario, phase: scenario.phases[0], state: &state,
      llm: mock, emitter: collector.emit
    )

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

    try await handler.execute(
      scenario: scenario, phase: scenario.phases[0], state: &state,
      llm: mock, emitter: collector.emit
    )

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

    try await handler.execute(
      scenario: scenario, phase: scenario.phases[0], state: &state,
      llm: mock, emitter: collector.emit
    )

    #expect(mock.generateCallCount == 2)
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

    try await handler.execute(
      scenario: scenario, phase: scenario.phases[0], state: &state,
      llm: mock, emitter: collector.emit
    )

    // Invalid vote counted dynamically
    #expect(state.voteResults["NonExistent"] == 1)
    #expect(state.voteResults["Alice"] == 1)
  }
}
