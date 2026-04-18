import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct ScoreCalcLogicTests {
  @Test func rawValues() {
    #expect(ScoreCalcLogic.prisonersDilemma.rawValue == "prisoners_dilemma")
    #expect(ScoreCalcLogic.voteTally.rawValue == "vote_tally")
    #expect(ScoreCalcLogic.wordwolfJudge.rawValue == "wordwolf_judge")
  }

  @Test func allCasesCount() {
    #expect(ScoreCalcLogic.allCases.count == 3)
  }

  @Test func roundTripCodable() throws {
    let original = ScoreCalcLogic.prisonersDilemma
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(ScoreCalcLogic.self, from: data)
    #expect(decoded == original)
  }
}
