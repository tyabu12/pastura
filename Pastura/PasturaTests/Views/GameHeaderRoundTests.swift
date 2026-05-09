import Testing

@testable import Pastura

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct GameHeaderRoundTests {

  // MARK: - Equatable semantics (synthesized)

  @Test func identicalPairsAreEqual() {
    let lhs = GameHeaderRound(current: 2, total: 5)
    let rhs = GameHeaderRound(current: 2, total: 5)
    #expect(lhs == rhs)
  }

  @Test func differingCurrentBreaksEquality() {
    #expect(GameHeaderRound(current: 1, total: 5) != GameHeaderRound(current: 2, total: 5))
  }

  @Test func differingTotalBreaksEquality() {
    #expect(GameHeaderRound(current: 2, total: 5) != GameHeaderRound(current: 2, total: 6))
  }

  // MARK: - Field accessibility

  @Test func currentAndTotalAreReadable() {
    // Pin the public field shape — `current` and `total` (singular pair),
    // not `currentRound` / `totalRounds` (the source caller's plural names).
    // The wrapper deliberately drops the "Round" suffix from each field
    // because the surrounding type already names the concept.
    let round = GameHeaderRound(current: 3, total: 7)
    #expect(round.current == 3)
    #expect(round.total == 7)
  }
}
