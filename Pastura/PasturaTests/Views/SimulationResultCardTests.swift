import Testing

@testable import Pastura

/// Pure-logic coverage for ``SimulationResultCard/Model`` — the final-ranking
/// card's display resolver shown at the tail of a completed simulation log
/// (issue #868).
///
/// Per ADR-009 / `.claude/rules/view-testing.md` rule 1, only the model's
/// derivation (framing classification, ordering, per-row value selection) is
/// unit-tested; the card's layout / motion / tap affordance is left to code
/// review + manual device QA (rule 4).
///
/// The classification is **survival-primary**: an `.eliminate` phase makes
/// "who is left standing" the headline even when scores are also present
/// (Werewolf), per the product decision on #868. `scores` is seeded with every
/// persona at `0` at run start, so "are there scores worth ranking" is decided
/// by *any non-zero* value (`hasScores`), never `!scores.isEmpty`.
@Suite(.timeLimit(.minutes(1)))
struct SimulationResultCardTests {
  // MARK: - Ranking (score-based)

  @Test("Score-based scenario ranks by score descending with 1-based ranks")
  func scoreRankingByScoreDesc() {
    let model = SimulationResultCard.Model(
      scores: ["Alice": 5, "Bob": 12, "Carol": 8],
      eliminated: [:],
      voteResults: [:],
      eliminationVotes: [:],
      phases: [Phase(type: .scoreCalc, logic: .voteTally)])
    #expect(model?.framing == .ranking)
    #expect(model?.entries.map(\.name) == ["Bob", "Carol", "Alice"])
    #expect(model?.entries.map(\.rank) == [1, 2, 3])
    #expect(model?.entries.first?.primaryValue == 12)
    #expect(model?.entries.allSatisfy { $0.valueKind == .points } == true)
  }

  @Test("A top-score tie orders deterministically by name so the winner is stable")
  func topScoreTieDeterministic() {
    let model = SimulationResultCard.Model(
      scores: ["Bob": 10, "Alice": 10, "Carol": 3],
      eliminated: [:],
      voteResults: [:],
      eliminationVotes: [:],
      phases: [Phase(type: .scoreCalc, logic: .voteTally)])
    // Bob > Alice lexically → Bob takes rank 1 regardless of dictionary order.
    // Name-descending is the canonical `RankingOrder` tie-break shared with the
    // engine's vote winner so the card can't contradict the eliminated agent (#1087).
    #expect(model?.entries.map(\.name) == ["Bob", "Alice", "Carol"])
    #expect(model?.entries.map(\.rank) == [1, 2, 3])
  }

  // MARK: - Survival (vote + eliminate)

  @Test("Vote+eliminate lists survivors first, then eliminated with their votes")
  func survivalSingleRound() {
    let model = SimulationResultCard.Model(
      scores: ["Alice": 0, "Bob": 0, "Carol": 0],
      eliminated: ["Carol": true],
      voteResults: ["Carol": 4],
      eliminationVotes: ["Carol": 4],
      phases: [Phase(type: .vote), Phase(type: .eliminate)])
    #expect(model?.framing == .survival)
    // Survivors (not eliminated) come first, eliminated last.
    #expect(model?.entries.map(\.isEliminated) == [false, false, true])
    #expect(model?.entries.allSatisfy { $0.rank == nil } == true)
    let carol = model?.entries.first { $0.name == "Carol" }
    #expect(carol?.primaryValue == 4)
    #expect(carol?.valueKind == .votes)
    // Survivors carry no vote number (last-round received votes are not
    // meaningful across rounds).
    let alice = model?.entries.first { $0.name == "Alice" }
    #expect(alice?.primaryValue == nil)
    // Qualify the enum case: a bare `.none` against an Optional binds to
    // `Optional.none` (nil), not `ValueKind.none`.
    #expect(alice?.valueKind == SimulationResultCard.ValueKind.none)
  }

  @Test("Multi-round survival shows each eliminated agent's own round count")
  func survivalMultiRound() {
    // Bob eliminated round 1 (2 votes), Dave round 2 (5 votes). Both counts
    // come from eliminationVotes, not a last-wins tally.
    let model = SimulationResultCard.Model(
      scores: ["Alice": 0, "Bob": 0, "Carol": 0, "Dave": 0],
      eliminated: ["Bob": true, "Dave": true],
      voteResults: ["Dave": 5],
      eliminationVotes: ["Bob": 2, "Dave": 5],
      phases: [Phase(type: .vote), Phase(type: .eliminate)])
    #expect(model?.framing == .survival)
    let bob = model?.entries.first { $0.name == "Bob" }
    let dave = model?.entries.first { $0.name == "Dave" }
    #expect(bob?.primaryValue == 2)
    #expect(dave?.primaryValue == 5)
    // Eliminated group ordered by votes desc: Dave (5) before Bob (2).
    let eliminatedNames = model?.entries.filter(\.isEliminated).map(\.name)
    #expect(eliminatedNames == ["Dave", "Bob"])
  }

  @Test("Werewolf (eliminate + scores) uses survival framing but shows scores")
  func werewolfSurvivalShowsScores() {
    let model = SimulationResultCard.Model(
      scores: ["Alice": 3, "Bob": 3, "Carol": 0],
      eliminated: ["Carol": true],
      voteResults: ["Carol": 3],
      eliminationVotes: ["Carol": 3],
      phases: [
        Phase(type: .vote), Phase(type: .eliminate),
        Phase(type: .scoreCalc, logic: .wordwolfJudge)
      ])
    #expect(model?.framing == .survival)
    // Scores are present → every row shows points, not votes (Werewolf keeps
    // the score visible even under survival framing).
    #expect(model?.entries.allSatisfy { $0.valueKind == .points } == true)
    let carol = model?.entries.first { $0.name == "Carol" }
    #expect(carol?.primaryValue == 0)
    #expect(carol?.isEliminated == true)
  }

  @Test("Score-driven elimination (no vote phase) still classifies as survival")
  func scoreDrivenElimination() {
    let model = SimulationResultCard.Model(
      scores: ["Alice": 8, "Bob": 2, "Carol": 5],
      eliminated: ["Bob": true],
      voteResults: [:],
      eliminationVotes: [:],
      phases: [Phase(type: .scoreCalc, logic: .voteTally), Phase(type: .eliminate)])
    #expect(model?.framing == .survival)
    // Scores present → points shown; deterministic order within groups.
    #expect(model?.entries.allSatisfy { $0.valueKind == .points } == true)
    #expect(model?.entries.map(\.isEliminated) == [false, false, true])
    // Survivors ordered by score desc: Alice (8) before Carol (5).
    let survivors = model?.entries.filter { !$0.isEliminated }.map(\.name)
    #expect(survivors == ["Alice", "Carol"])
  }

  @Test("An elimination not surfaced by a top-level phase still classifies as survival")
  func eliminationNestedUnderConditional() {
    // The eliminate phase can be nested inside a `.conditional` (depth-1 rule),
    // so `phaseTypes` — which scans only top-level phases — would miss it. The
    // ground-truth `eliminated` dict must still drive survival framing.
    let model = SimulationResultCard.Model(
      scores: ["Alice": 0, "Bob": 0, "Carol": 0],
      eliminated: ["Carol": true],
      voteResults: [:],
      eliminationVotes: ["Carol": 3],
      phases: [Phase(type: .conditional)])
    #expect(model?.framing == .survival)
    let carol = model?.entries.first { $0.name == "Carol" }
    #expect(carol?.isEliminated == true)
    #expect(carol?.primaryValue == 3)
  }

  // MARK: - Vote-only ranking (popularity vote, eliminates nobody)

  @Test("Vote-only scenario ranks by votes and is NOT mislabeled as survival")
  func voteOnlyRanking() {
    let model = SimulationResultCard.Model(
      scores: ["Alice": 0, "Bob": 0, "Carol": 0],
      eliminated: [:],
      voteResults: ["Alice": 3, "Bob": 1, "Carol": 2],
      eliminationVotes: [:],
      phases: [Phase(type: .vote)])
    #expect(model?.framing == .ranking)
    #expect(model?.entries.map(\.name) == ["Alice", "Carol", "Bob"])
    #expect(model?.entries.map(\.rank) == [1, 2, 3])
    #expect(model?.entries.allSatisfy { $0.valueKind == .votes } == true)
  }

  // MARK: - Pairing

  @Test("Round-robin choose classifies as pairing framing with points")
  func pairingRoundRobin() {
    let model = SimulationResultCard.Model(
      scores: ["Alice": 6, "Bob": 5],
      eliminated: [:],
      voteResults: [:],
      eliminationVotes: [:],
      phases: [
        Phase(type: .choose, pairing: .roundRobin),
        Phase(type: .scoreCalc, logic: .prisonersDilemma)
      ])
    #expect(model?.framing == .pairing)
    #expect(model?.entries.map(\.name) == ["Alice", "Bob"])
    #expect(model?.entries.allSatisfy { $0.valueKind == .points } == true)
  }

  // MARK: - Nil (no card)

  @Test("A summary-only run with no scores/votes/eliminations yields nil")
  func summaryOnlyYieldsNil() {
    let model = SimulationResultCard.Model(
      scores: ["Alice": 0, "Bob": 0],
      eliminated: [:],
      voteResults: [:],
      eliminationVotes: [:],
      phases: [Phase(type: .speakAll), Phase(type: .summarize)])
    #expect(model == nil)
  }

  @Test("A fully empty state yields nil")
  func emptyStateYieldsNil() {
    let model = SimulationResultCard.Model(
      scores: [:], eliminated: [:], voteResults: [:], eliminationVotes: [:], phases: [])
    #expect(model == nil)
  }
}
