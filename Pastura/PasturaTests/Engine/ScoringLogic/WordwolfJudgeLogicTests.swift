import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct WordwolfJudgeLogicTests {
  let logic = WordwolfJudgeLogic()

  @Test func majorityWinsWhenWolfMostVoted() {
    var state = SimulationState()
    state.voteResults = ["Wolf": 3, "Other": 1]
    state.variables["wolf_name"] = "Wolf"
    let collector = EventCollector()
    logic.calculate(state: &state, emitter: collector.emit)
    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.count == 1)
    #expect(summaries[0].contains("多数派の勝ち"))
  }

  @Test func wolfWinsWhenNotDetected() {
    var state = SimulationState()
    state.voteResults = ["Innocent": 3, "Wolf": 1]
    state.variables["wolf_name"] = "Wolf"
    let collector = EventCollector()
    logic.calculate(state: &state, emitter: collector.emit)
    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries[0].contains("ウルフの勝ち"))
  }

  @Test func handlesEmptyVoteResults() {
    var state = SimulationState()
    let collector = EventCollector()
    logic.calculate(state: &state, emitter: collector.emit)
    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries[0].contains("投票結果がありません"))
  }
}
