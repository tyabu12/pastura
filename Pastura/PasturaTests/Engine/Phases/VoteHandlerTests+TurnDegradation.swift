import Testing

@testable import Pastura

/// ADR-021 D1/D2 turn-degradation coverage for `VoteHandler`, split into a
/// sibling file per `.claude/rules/testing.md` § "Splitting a Suite Across
/// Files". `TurnFailureGate` internals (classification, consecutive-count
/// bookkeeping) are covered by `TurnFailureGateTests`; these tests only pin the
/// HANDLER's integration with the gate: a skipped vote is an **abstention** —
/// no ballot recorded, no tally contribution — and the voter's stale
/// `lastOutputs` entry is cleared.
extension VoteHandlerTests {
  @Test func transientFailureAbstainsAndOthersStillVote() async throws {
    // Alice's call throws a transient (turn-degradable) error; Bob and Charlie
    // still vote. Alice's ballot is absent from both the votes map and the
    // tally (abstention — extends the #524 tally-drop precedent to "no ballot").
    let mock = MockLLMService(responses: [
      #"{"vote": "Alice"}"#,
      #"{"vote": "Alice"}"#
    ])
    try await mock.loadModel()
    mock.throwErrorOnNextGenerate(.generationFailed(description: "transient blip"), count: 1)

    let scenario = makeTestScenario(
      phases: [Phase(type: .vote, prompt: "Vote!", outputSchema: ["vote": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    // Stale prior-round output — must be cleared on skip (ADR-021 D2), not left
    // readable by later phases keyed on `lastOutputs`.
    state.lastOutputs["Alice"] = TurnOutput(fields: ["vote": "stale"])
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    // Only Bob and Charlie's ballots land; both voted "Alice".
    #expect(state.voteResults["Alice"] == 2)
    #expect(state.voteResults.count == 1)

    // No `.agentOutput` for the skipped voter; exactly one `.turnSkipped`.
    let agentOutputs = collector.events.compactMap { event -> String? in
      if case .agentOutput(let agent, _, _) = event { return agent }
      return nil
    }
    #expect(agentOutputs == ["Bob", "Charlie"])

    let skipped = collector.events.compactMap { event -> (String, PhaseType)? in
      if case .turnSkipped(let agent, let phaseType, _) = event { return (agent, phaseType) }
      return nil
    }
    #expect(skipped.count == 1)
    #expect(skipped.first?.0 == "Alice")
    #expect(skipped.first?.1 == .vote)

    // Abstention: no ballot for Alice in the emitted votes map, stale output cleared.
    let votes = collector.events.compactMap { event -> [String: String]? in
      if case .voteResults(let votes, _) = event { return votes }
      return nil
    }.first
    #expect(votes?["Alice"] == nil)
    #expect(votes?["Bob"] == "Alice")
    #expect(state.lastOutputs["Alice"] == nil)
    #expect(state.lastOutputs["Bob"]?.vote == "Alice")
  }
}
