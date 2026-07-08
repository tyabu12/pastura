import Testing

@testable import Pastura

/// ADR-021 downstream-chain coverage: a fully-abstained `vote` phase must
/// compose cleanly with the already-defensive code phases below it, degrading by
/// omission all the way to a `conditional` `else` branch — not throwing, not
/// fabricating an elimination.
///
/// The chain is `vote → eliminate → conditional`, driven by calling each
/// handler's `execute` **directly in sequence** on a shared `SimulationState`
/// (no `SimulationRunner` / `AsyncStream`). That keeps the suite parallel-safe
/// under `.claude/rules/testing.md` § "Swift Testing Parallelism" — do NOT
/// reshape it to run through the runner without adding `.serialized`.
///
/// A **2-agent** scenario is deliberate: both ballots skip (2 consecutive skips,
/// one short of the D4 breaker's limit of 3), so `voteResults` ends empty
/// without the breaker aborting first. A 3-agent all-skip would trip the breaker
/// on the 3rd turn before an empty tally could form.
@Suite(.timeLimit(.minutes(1)))
struct TurnDegradationChainTests {
  /// `vote → eliminate → conditional`. The conditional compares the derived
  /// `vote_winner` identifier (most-voted name in `state.voteResults`, tie-broken
  /// like `EliminateHandler`) against a set `expected_winner` variable — the
  /// same identifier-vs-variable shape the shipped `word_wolf` preset uses
  /// (`vote_winner == wolf_name`). This is **contingent, not a tautology**: with
  /// real ballots `vote_winner` resolves to the actual winner and the `then`
  /// branch could run; only because both ballots abstained here does
  /// `vote_winner` resolve absent → comparison false → `else`. (`expected_winner`
  /// is set to a name that would plausibly win, so the `else` reflects the
  /// abstention, not a constant.)
  private func makeChainScenario() -> Scenario {
    makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [
        Phase(type: .vote, prompt: "Vote!", outputSchema: ["vote": "string"]),
        Phase(type: .eliminate),
        Phase(
          type: .conditional,
          condition: "vote_winner == expected_winner",
          thenPhases: [Phase(type: .summarize, template: "someone-eliminated")],
          elsePhases: [Phase(type: .summarize, template: "no-elimination")]
        )
      ]
    )
  }

  @Test func allBallotsSkippedRoutesConditionalToElse() async throws {
    let mock = MockLLMService(responses: [])
    try await mock.loadModel()
    // Both voters fail transiently → both abstain.
    mock.throwErrorOnNextGenerate(.generationFailed(description: "transient blip"), count: 2)

    let scenario = makeChainScenario()
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    // The name the conditional compares `vote_winner` against. Set (not a
    // string literal) so the comparison mirrors the shipped `word_wolf` shape.
    state.variables["expected_winner"] = "Alice"
    let collector = EventCollector()

    // Phase 0 — vote: both turns skip (must not throw; 2 < breaker limit 3).
    try await VoteHandler().execute(
      context: makePhaseContext(scenario: scenario, phaseIndex: 0, llm: mock, collector: collector),
      state: &state)

    let skipped = collector.events.filter {
      if case .turnSkipped = $0 { return true }
      return false
    }
    #expect(skipped.count == 2)
    #expect(state.voteResults.isEmpty)

    // Phase 1 — eliminate: no votes → no-op, nobody eliminated.
    try await EliminateHandler().execute(
      context: makePhaseContext(scenario: scenario, phaseIndex: 1, llm: mock, collector: collector),
      state: &state)

    let eliminations = collector.events.filter {
      if case .elimination = $0 { return true }
      return false
    }
    #expect(eliminations.isEmpty)
    // `eliminated` is pre-seeded with every agent at `false` by
    // `SimulationState.initial`; the invariant is that none flipped to `true`.
    #expect(!state.eliminated.values.contains(true))

    // Phase 2 — conditional: `vote_winner` absent (empty voteResults) →
    // `vote_winner == expected_winner` is false → else branch runs.
    try await ConditionalHandler().execute(
      context: makePhaseContext(scenario: scenario, phaseIndex: 2, llm: mock, collector: collector),
      state: &state)

    let conditionResults = collector.events.compactMap { event -> Bool? in
      if case .conditionalEvaluated(_, let result) = event { return result }
      return nil
    }
    #expect(conditionResults == [false])

    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.contains("no-elimination"))
    #expect(!summaries.contains("someone-eliminated"))
  }
}
