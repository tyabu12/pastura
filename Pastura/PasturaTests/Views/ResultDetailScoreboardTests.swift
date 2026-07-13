import Testing

@testable import Pastura

/// Pure gate logic for the past-results scoreboard affordance (ADR-009: extract
/// View logic to unit tests). Mirrors the live `SimulationView.hasRankableScores`
/// gate — a scoreboard shows only when at least one score is non-zero, so a
/// vote-only run renders no misleading all-zero board.
@Suite(.timeLimit(.minutes(1)))
struct ResultDetailScoreboardTests {

  @Test func rankableWhenAnyScoreIsNonZero() {
    let snapshot = ScoreboardSnapshot.rankable(
      scores: ["Alice": 3, "Bob": 0],
      eliminated: ["Bob": true])
    #expect(snapshot != nil)
    #expect(snapshot?.scores == ["Alice": 3, "Bob": 0])
    #expect(snapshot?.eliminated == ["Bob": true])
  }

  @Test func notRankableWhenAllScoresZero() {
    // Vote-only / consensus run: scores tracked but all zero — no scoreboard.
    let snapshot = ScoreboardSnapshot.rankable(
      scores: ["Alice": 0, "Bob": 0],
      eliminated: ["Alice": true])
    #expect(snapshot == nil)
  }

  @Test func notRankableWhenScoresEmpty() {
    let snapshot = ScoreboardSnapshot.rankable(scores: [:], eliminated: [:])
    #expect(snapshot == nil)
  }

  @Test func rankableOnANegativeScore() {
    // A non-zero negative score is still rankable (some scoring rules deduct).
    let snapshot = ScoreboardSnapshot.rankable(
      scores: ["Alice": -2, "Bob": 0], eliminated: [:])
    #expect(snapshot != nil)
  }
}
