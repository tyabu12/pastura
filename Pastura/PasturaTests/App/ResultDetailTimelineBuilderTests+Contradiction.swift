import Foundation
import Testing

@testable import Pastura

// #916 contradiction-badge coverage for
// `ResultDetailTimelineBuilder.contradictionBadgedTurnIDs` — sibling-file
// extension per testing.md's type_body_length split rule (NOT a new
// @Suite; suites run in parallel and a twin would race the original).
extension ResultDetailTimelineBuilderTests {

  private var pdOptions: [String] { ["cooperate", "betray"] }

  private func declarationTurn(
    id: String, round: Int, seq: Int, agent: String, intent: String
  ) -> TurnRecord {
    var turn = makeTurn(id: id, round: round, seq: seq, phase: "speak_all", agent: agent)
    turn.parsedOutputJSON = """
      {"fields":{"statement":"s","declared_intent":"\(intent)","inner_thought":"t"}}
      """
    return turn
  }

  private func chooseTurn(
    round: Int, seq: Int, agent: String, action: String
  ) -> TurnRecord {
    var turn = makeTurn(round: round, seq: seq, phase: "choose", agent: agent)
    turn.parsedOutputJSON = """
      {"fields":{"action":"\(action)","inner_thought":"t"}}
      """
    return turn
  }

  @Test
  func badgesFullContradictionOnlyWithinTheSameRound() {
    let turns = [
      declarationTurn(id: "lie", round: 1, seq: 1, agent: "Alice", intent: "cooperate"),
      declarationTurn(id: "ok", round: 1, seq: 2, agent: "Bob", intent: "cooperate"),
      chooseTurn(round: 1, seq: 3, agent: "Alice", action: "betray"),
      chooseTurn(round: 1, seq: 4, agent: "Bob", action: "cooperate"),
      chooseTurn(round: 1, seq: 5, agent: "Alice", action: "betray"),
      chooseTurn(round: 1, seq: 6, agent: "Bob", action: "betray"),
      // Round 2: Alice declares cooperate but only round-2 actions count.
      declarationTurn(id: "r2", round: 2, seq: 7, agent: "Alice", intent: "cooperate"),
      chooseTurn(round: 2, seq: 8, agent: "Alice", action: "cooperate"),
      chooseTurn(round: 2, seq: 9, agent: "Alice", action: "cooperate")
    ]

    let badged = ResultDetailTimelineBuilder.contradictionBadgedTurnIDs(
      turns: turns, options: pdOptions)

    // Alice r1: 2/2 betray → badge. Bob r1: 1/2 → strategy, no badge.
    // Alice r2: consistent → no badge.
    #expect(badged == ["lie"])
  }

  @Test
  func lastDeclarationInTheRoundWins() {
    // Two declarations by the same agent in one round: only the later one
    // is the badge anchor — a first-wins refactor must fail this.
    let turns = [
      declarationTurn(id: "early", round: 1, seq: 1, agent: "Alice", intent: "betray"),
      declarationTurn(id: "late", round: 1, seq: 2, agent: "Alice", intent: "cooperate"),
      chooseTurn(round: 1, seq: 3, agent: "Alice", action: "betray"),
      chooseTurn(round: 1, seq: 4, agent: "Alice", action: "betray")
    ]

    let badged = ResultDetailTimelineBuilder.contradictionBadgedTurnIDs(
      turns: turns, options: pdOptions)

    #expect(badged == ["late"])
  }

  @Test
  func emptyOptionsProduceNoBadges() {
    let turns = [
      declarationTurn(id: "lie", round: 1, seq: 1, agent: "Alice", intent: "cooperate"),
      chooseTurn(round: 1, seq: 2, agent: "Alice", action: "betray")
    ]
    #expect(
      ResultDetailTimelineBuilder.contradictionBadgedTurnIDs(turns: turns, options: [])
        .isEmpty)
  }

  @Test
  func legacyTurnsWithoutDeclaredIntentProduceNoBadges() {
    // Pre-#916 runs: speak turns have no declared_intent key at all.
    let turns = [
      makeTurn(round: 1, seq: 1, phase: "speak_all", agent: "Alice"),
      chooseTurn(round: 1, seq: 2, agent: "Alice", action: "betray"),
      chooseTurn(round: 1, seq: 3, agent: "Alice", action: "betray")
    ]
    #expect(
      ResultDetailTimelineBuilder.contradictionBadgedTurnIDs(
        turns: turns, options: pdOptions
      ).isEmpty)
  }
}
