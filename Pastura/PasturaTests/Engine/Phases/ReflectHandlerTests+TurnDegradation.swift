import Testing

@testable import Pastura

/// ADR-021 D1/D2 turn-degradation coverage for `ReflectHandler`, split into a
/// sibling file per `.claude/rules/testing.md` § "Splitting a Suite Across
/// Files". A skipped reflect turn writes no `notes_<name>` — consistent with the
/// existing non-empty guard, so a prior round's memo is preserved (private
/// memory persists, ADR-021 D2). Reflect never touches `lastOutputs`, so there
/// is nothing to clear.
extension ReflectHandlerTests {
  @Test func transientFailureSkipsAndPreservesPriorNote() async throws {
    // Alice's call throws a transient error; her prior-round memo must survive
    // (no overwrite), and Bob still updates his note.
    let mock = MockLLMService(responses: [
      #"{"note": "Bob's fresh memo"}"#
    ])
    try await mock.loadModel()
    mock.throwErrorOnNextGenerate(.generationFailed(description: "transient blip"), count: 1)

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [Phase(type: .reflect, prompt: "Reflect", outputSchema: ["note": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 2
    state.variables["notes_Alice"] = "Alice's prior memo"
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    // Prior memo preserved on skip; Bob's fresh note written.
    #expect(state.variables["notes_Alice"] == "Alice's prior memo")
    #expect(state.variables["notes_Bob"] == "Bob's fresh memo")

    // No `.agentOutput` for the skipped agent; exactly one `.turnSkipped`.
    let agentOutputs = collector.events.compactMap { event -> String? in
      if case .agentOutput(let agent, _, _) = event { return agent }
      return nil
    }
    #expect(agentOutputs == ["Bob"])

    let skipped = collector.events.compactMap { event -> (String, PhaseType)? in
      if case .turnSkipped(let agent, let phaseType, _) = event { return (agent, phaseType) }
      return nil
    }
    #expect(skipped.count == 1)
    #expect(skipped.first?.0 == "Alice")
    #expect(skipped.first?.1 == .reflect)
  }
}
