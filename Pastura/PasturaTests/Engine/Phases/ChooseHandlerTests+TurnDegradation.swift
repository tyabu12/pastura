import Testing

@testable import Pastura

/// ADR-021 D1/D2 turn-degradation coverage for `ChooseHandler`, split into a
/// sibling file per `.claude/rules/testing.md` § "Splitting a Suite Across
/// Files". `TurnFailureGate` internals are covered by `TurnFailureGateTests`;
/// these tests pin the HANDLER's degrade-by-omission behavior:
///
/// - **round-robin**: a skipped call drops the *whole pairing* (a pairing with
///   one real and one absent action would flow into `PrisonersDilemmaLogic`'s
///   `?? "cooperate"` default — fabrication by another name). The successful
///   partner's `.agentOutput` and `lastOutputs` still stand (legitimately
///   consumed by `EventReactivePayoffLogic`).
/// - **individual**: a skipped turn writes nothing and clears the agent's stale
///   `lastOutputs`.
///
/// **Not covered (structurally unreachable via `throwErrorOnNextGenerate`).**
/// The round-robin clear-only-if-not-succeeded guard (ADR-021 D2: don't erase a
/// member's valid output from the *other* pairing it participates in) has one
/// distinguishing case — an agent that *succeeds then skips* across its two
/// adjacency pairs. Position-based error injection fills the queue from the
/// front, and an agent's first round-robin appearance always precedes its
/// second, so only *skip-then-success* is reachable (covered below: the skipped
/// member keeps a valid output from its later call). The D4 breaker (3
/// consecutive skips) further prevents an agent skipping *both* its calls. The
/// guard is retained for production correctness (`EventReactivePayoffLogic`
/// scoring) and code-review-gated, not unit-asserted on the unreachable arm.
extension ChooseHandlerTests {
  @Test func roundRobinSkipDropsWholePairing() async throws {
    // 3 agents → pairs (Alice,Bob), (Bob,Charlie), (Charlie,Alice); call order
    // Alice,Bob,Bob,Charlie,Charlie,Alice. Error on call #1 (Alice as persona1
    // of pair (Alice,Bob)) → that pairing is dropped. Alice's later call (#6, in
    // pair (Charlie,Alice)) still succeeds, so she keeps a valid lastOutputs.
    let mock = MockLLMService(responses: [
      #"{"action": "cooperate"}"#,  // call#2 Bob   (pair0 persona2)
      #"{"action": "cooperate"}"#,  // call#3 Bob   (pair1 persona1)
      #"{"action": "betray"}"#,  // call#4 Charlie (pair1 persona2)
      #"{"action": "cooperate"}"#,  // call#5 Charlie (pair2 persona1)
      #"{"action": "betray"}"#  // call#6 Alice (pair2 persona2)
    ])
    try await mock.loadModel()
    mock.throwErrorOnNextGenerate(.generationFailed(description: "transient blip"), count: 1)

    let scenario = makeTestScenario(
      phases: [
        Phase(
          type: .choose, prompt: "Choose!", outputSchema: ["action": "string"],
          options: ["cooperate", "betray"], pairing: .roundRobin)
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    // Exactly one turn skipped (Alice's first call), typed to .choose.
    let skipped = collector.events.compactMap { event -> (String, PhaseType)? in
      if case .turnSkipped(let agent, let phaseType, _) = event { return (agent, phaseType) }
      return nil
    }
    #expect(skipped.count == 1)
    #expect(skipped.first?.0 == "Alice")
    #expect(skipped.first?.1 == .choose)

    // The (Alice,Bob) pairing is dropped; the other two survive.
    let pairings = collector.events.compactMap { event -> (String, String)? in
      if case .pairingResult(let agent1, _, let agent2, _) = event { return (agent1, agent2) }
      return nil
    }
    #expect(pairings.count == 2)
    #expect(!pairings.contains { $0 == ("Alice", "Bob") })
    #expect(state.pairings.count == 2)

    // The successful partner (Bob, call#2) still emitted output and kept it.
    #expect(state.lastOutputs["Bob"]?.action == "cooperate")
    // Alice's later successful call (#6) leaves her a valid output — the skip
    // did not permanently erase it.
    #expect(state.lastOutputs["Alice"]?.action == "betray")
  }

  @Test func individualSkipWritesNothingAndClears() async throws {
    // Individual mode (no pairing): Alice's call fails → she writes nothing and
    // her stale lastOutputs is cleared; Bob and Charlie choose normally.
    let mock = MockLLMService(responses: [
      #"{"action": "cooperate"}"#,  // Bob
      #"{"action": "betray"}"#  // Charlie
    ])
    try await mock.loadModel()
    mock.throwErrorOnNextGenerate(.generationFailed(description: "transient blip"), count: 1)

    let scenario = makeTestScenario(
      phases: [
        Phase(
          type: .choose, prompt: "Choose!", outputSchema: ["action": "string"],
          options: ["cooperate", "betray"])
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    state.lastOutputs["Alice"] = TurnOutput(fields: ["action": "stale"])
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let agentOutputs = collector.events.compactMap { event -> String? in
      if case .agentOutput(let agent, _, _) = event { return agent }
      return nil
    }
    #expect(agentOutputs == ["Bob", "Charlie"])

    let skipped = collector.events.compactMap { event -> String? in
      if case .turnSkipped(let agent, _, _) = event { return agent }
      return nil
    }
    #expect(skipped == ["Alice"])

    #expect(state.lastOutputs["Alice"] == nil)
    #expect(state.lastOutputs["Bob"]?.action == "cooperate")
  }
}
