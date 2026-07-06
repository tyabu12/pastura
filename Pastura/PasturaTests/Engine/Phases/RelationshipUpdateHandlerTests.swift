import Testing

@testable import Pastura

/// Covers ``RelationshipUpdateHandler`` — the zero-inference affinity-matrix
/// code phase (#910). Signals are seeded directly onto `SimulationState`
/// (`lastOutputs` for votes, `pairings` for choose actions) the way the
/// surrounding phases would, then the handler's deterministic deltas are
/// asserted via the emitted `.relationshipUpdate` matrix and the persisted
/// `state.variables`.
@Suite(.timeLimit(.minutes(1)))
struct RelationshipUpdateHandlerTests {
  let handler = RelationshipUpdateHandler()

  /// Extracts the matrix from the (single) `.relationshipUpdate` event.
  private func emittedMatrix(_ collector: EventCollector) -> [String: [String: Int]]? {
    for event in collector.events {
      if case .relationshipUpdate(let relationships) = event { return relationships }
    }
    return nil
  }

  private func makeSUT(
    agentNames: [String] = ["Alice", "Bob"],
    voteAgainst: Int? = nil,
    actionDeltas: [String: Int]? = nil
  ) -> (Scenario, SimulationState) {
    let scenario = makeTestScenario(
      agentNames: agentNames,
      phases: [
        Phase(type: .relationshipUpdate, voteAgainst: voteAgainst, actionDeltas: actionDeltas)
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    return (scenario, state)
  }

  @Test func appliesVoteAgainstDelta() async throws {
    var (scenario, state) = makeSUT(voteAgainst: -1)
    // Alice voted Bob, Bob voted Alice.
    state.lastOutputs["Alice"] = TurnOutput(fields: ["vote": "Bob"])
    state.lastOutputs["Bob"] = TurnOutput(fields: ["vote": "Alice"])
    let collector = EventCollector()
    let context = makePhaseContext(
      scenario: scenario, llm: MockLLMService(responses: []), collector: collector)

    try await handler.execute(context: context, state: &state)

    let matrix = try #require(emittedMatrix(collector))
    // Each target grows wary of the agent who voted against them.
    #expect(matrix["Bob"]?["Alice"] == -1)
    #expect(matrix["Alice"]?["Bob"] == -1)
  }

  @Test func ignoresSelfVoteAndHallucinatedTarget() async throws {
    var (scenario, state) = makeSUT(voteAgainst: -1)
    state.lastOutputs["Alice"] = TurnOutput(fields: ["vote": "Alice"])  // self-vote
    state.lastOutputs["Bob"] = TurnOutput(fields: ["vote": "Ghost"])  // not a persona
    let collector = EventCollector()
    let context = makePhaseContext(
      scenario: scenario, llm: MockLLMService(responses: []), collector: collector)

    try await handler.execute(context: context, state: &state)

    let matrix = try #require(emittedMatrix(collector))
    #expect(matrix.isEmpty)
  }

  @Test func appliesActionDeltasPerPartner() async throws {
    var (scenario, state) = makeSUT(actionDeltas: ["cooperate": 1, "betray": -2])
    state.pairings = [
      Pairing(agent1: "Alice", agent2: "Bob", action1: "cooperate", action2: "betray")
    ]
    let collector = EventCollector()
    let context = makePhaseContext(
      scenario: scenario, llm: MockLLMService(responses: []), collector: collector)

    try await handler.execute(context: context, state: &state)

    let matrix = try #require(emittedMatrix(collector))
    // Alice sees Bob's action (betray → -2); Bob sees Alice's (cooperate → +1).
    #expect(matrix["Alice"]?["Bob"] == -2)
    #expect(matrix["Bob"]?["Alice"] == 1)
  }

  @Test func accumulatesAcrossRounds() async throws {
    var (scenario, state) = makeSUT(voteAgainst: -1)
    state.lastOutputs["Alice"] = TurnOutput(fields: ["vote": "Bob"])
    let context1 = makePhaseContext(
      scenario: scenario, llm: MockLLMService(responses: []), collector: EventCollector())
    try await handler.execute(context: context1, state: &state)

    // Second round: same vote again. Raw matrix persisted in state.variables.
    let collector2 = EventCollector()
    let context2 = makePhaseContext(
      scenario: scenario, llm: MockLLMService(responses: []), collector: collector2)
    try await handler.execute(context: context2, state: &state)

    let matrix = try #require(emittedMatrix(collector2))
    #expect(matrix["Bob"]?["Alice"] == -2)
  }

  @Test func skipsEliminatedPerceiver() async throws {
    var (scenario, state) = makeSUT(agentNames: ["Alice", "Bob", "Charlie"], voteAgainst: -1)
    state.eliminated["Bob"] = true
    state.lastOutputs["Alice"] = TurnOutput(fields: ["vote": "Bob"])  // target eliminated → dropped
    state.lastOutputs["Charlie"] = TurnOutput(fields: ["vote": "Alice"])
    let collector = EventCollector()
    let context = makePhaseContext(
      scenario: scenario, llm: MockLLMService(responses: []), collector: collector)

    try await handler.execute(context: context, state: &state)

    let matrix = try #require(emittedMatrix(collector))
    #expect(matrix["Bob"] == nil)  // eliminated — no row
    #expect(matrix["Alice"]?["Charlie"] == -1)
  }

  @Test func writesProseSummaryWhenThresholdCrossed() async throws {
    var (scenario, state) = makeSUT(voteAgainst: -2)  // one round reaches |2|
    state.lastOutputs["Alice"] = TurnOutput(fields: ["vote": "Bob"])
    let collector = EventCollector()
    let context = makePhaseContext(
      scenario: scenario, llm: MockLLMService(responses: []), collector: collector)

    try await handler.execute(context: context, state: &state)

    let summary = try #require(state.variables["relationships_Bob"])
    #expect(summary.contains("Alice"))
    #expect(!summary.isEmpty)
    // Raw matrix persisted for cross-round accumulation.
    #expect(state.variables["relationships_raw_Bob"]?.contains("Alice") == true)
  }

  @Test func noSignalEmitsEmptyMatrixWithoutCrashing() async throws {
    var (scenario, state) = makeSUT(voteAgainst: -1)
    // No lastOutputs votes, no pairings — misordered/placeholder phase.
    let collector = EventCollector()
    let context = makePhaseContext(
      scenario: scenario, llm: MockLLMService(responses: []), collector: collector)

    try await handler.execute(context: context, state: &state)

    let matrix = try #require(emittedMatrix(collector))
    #expect(matrix.isEmpty)
  }

  @Test func appliesBothVoteAndActionSignalsInSamePhase() async throws {
    // Regression: a short-circuiting `||` over the two side-effecting apply
    // helpers dropped the action signal whenever a vote was also present. A
    // phase may declare both rules and both signals may be live at once.
    var (scenario, state) = makeSUT(
      voteAgainst: -1, actionDeltas: ["cooperate": 1, "betray": -2])
    state.lastOutputs["Alice"] = TurnOutput(fields: ["vote": "Bob"])
    state.lastOutputs["Bob"] = TurnOutput(fields: ["vote": "Alice"])
    state.pairings = [
      Pairing(agent1: "Alice", agent2: "Bob", action1: "cooperate", action2: "betray")
    ]
    let collector = EventCollector()
    let context = makePhaseContext(
      scenario: scenario, llm: MockLLMService(responses: []), collector: collector)

    try await handler.execute(context: context, state: &state)

    let matrix = try #require(emittedMatrix(collector))
    // Alice: vote (-1) + Bob's betray action (-2) = -3. A `||` short-circuit
    // would drop the action term and leave -1.
    #expect(matrix["Alice"]?["Bob"] == -3)
    // Bob: vote (-1) + Alice's cooperate action (+1) = 0.
    #expect(matrix["Bob"]?["Alice"] == 0)
  }

  @Test func prunesEliminatedAgentFromProseButKeepsRawHistory() async throws {
    var (scenario, state) = makeSUT(voteAgainst: -2)
    // Round 1: Bob votes Alice, so Alice grows wary of Bob (|2| crosses threshold).
    state.lastOutputs["Bob"] = TurnOutput(fields: ["vote": "Alice"])
    let context1 = makePhaseContext(
      scenario: scenario, llm: MockLLMService(responses: []), collector: EventCollector())
    try await handler.execute(context: context1, state: &state)
    #expect(state.variables["relationships_Alice"]?.contains("Bob") == true)

    // Bob is eliminated; re-run with no fresh signal.
    state.eliminated["Bob"] = true
    state.lastOutputs = [:]
    let context2 = makePhaseContext(
      scenario: scenario, llm: MockLLMService(responses: []), collector: EventCollector())
    try await handler.execute(context: context2, state: &state)

    // Prose no longer mentions the eliminated agent, but the raw matrix keeps
    // the accumulated history (for the event payload / Phase-3 viz).
    #expect(state.variables["relationships_Alice"] == "")
    #expect(state.variables["relationships_raw_Alice"]?.contains("Bob") == true)
  }
}
