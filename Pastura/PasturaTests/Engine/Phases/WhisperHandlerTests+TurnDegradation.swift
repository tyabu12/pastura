import Testing

@testable import Pastura

/// ADR-021 D1/D2 turn-degradation coverage for `WhisperHandler`, split into a
/// sibling file per `.claude/rules/testing.md` § "Splitting a Suite Across
/// Files". A skipped whisper utterance **ends that pair's exchange early** (a
/// partner replying to a missing utterance would desync the exchange), and when
/// the *first* turn of a pair is skipped the resulting empty transcript leaves
/// the prior round's `whispers_<name>` intact rather than overwriting it with a
/// header-only channel (private memory persists, ADR-021 D2 — mirroring
/// `ReflectHandler`'s non-empty guard).
///
/// **Test-reachability note.** Position-based `throwErrorOnNextGenerate` fills
/// the error queue from the front, so the reachable skip lands on a pair's
/// *first* turn (empty transcript). A within-pair *partial-then-skip* (≥1
/// utterance already exchanged, then a later turn skips) is unreachable via this
/// injection, and its "write the partial transcript" arm is just the existing
/// overwrite semantics exercised by the non-degraded whisper tests. The
/// early-exit itself is proven here structurally: without it, a 0-response mock
/// would drive 3 consecutive skips and trip the D4 breaker.
extension WhisperHandlerTests {
  @Test func firstTurnSkipEndsExchangeEarlyAndPreservesPriorChannel() async throws {
    // 2 agents, 2 sub-rounds → a full pair would make 4 calls. Alice's opening
    // whisper fails transiently: the pair's exchange ends immediately (Bob is
    // never called), and because the transcript is empty the prior-round
    // whisper channels are preserved, not overwritten with a header-only body.
    let mock = MockLLMService(responses: [])
    try await mock.loadModel()
    mock.throwErrorOnNextGenerate(.generationFailed(description: "transient blip"), count: 1)

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [
        Phase(
          type: .whisper, prompt: "Whisper!",
          outputSchema: ["statement": "string"], subRounds: 2)
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    state.variables["whispers_Alice"] = "Alice's prior whisper"
    state.variables["whispers_Bob"] = "Bob's prior whisper"
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    // Must NOT throw: only one skip occurs (early exit), so the D4 breaker
    // (3 consecutive) never trips. Without early exit, the 0-response mock would
    // drive skip after skip and abort here.
    try await handler.execute(context: context, state: &state)

    // Exactly one turn skipped (Alice's opening whisper), typed to .whisper.
    let skipped = collector.events.compactMap { event -> (String, PhaseType)? in
      if case .turnSkipped(let agent, let phaseType, _) = event { return (agent, phaseType) }
      return nil
    }
    #expect(skipped.count == 1)
    #expect(skipped.first?.0 == "Alice")
    #expect(skipped.first?.1 == .whisper)

    // No whisper utterance emitted (Alice skipped; Bob never reached).
    let whisperOutputs = collector.events.filter { event in
      if case .agentOutput(_, _, let phaseType) = event { return phaseType == .whisper }
      return false
    }
    #expect(whisperOutputs.isEmpty)
    #expect(mock.generateCallCount == 0)

    // Empty transcript → prior channels preserved, not overwritten.
    #expect(state.variables["whispers_Alice"] == "Alice's prior whisper")
    #expect(state.variables["whispers_Bob"] == "Bob's prior whisper")
  }
}
