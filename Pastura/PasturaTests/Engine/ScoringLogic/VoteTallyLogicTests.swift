import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct VoteTallyLogicTests {
  let logic = VoteTallyLogic()

  @Test func talliesVotesIntoScores() {
    var state = SimulationState(scores: ["A": 5, "B": 3])
    state.voteResults = ["A": 2, "B": 1]
    let collector = EventCollector()
    logic.calculate(state: &state, emitter: collector.emit)
    #expect(state.scores["A"] == 7)
    #expect(state.scores["B"] == 4)
  }

  @Test func handlesZeroVotes() {
    var state = SimulationState(scores: ["A": 5, "B": 3])
    state.voteResults = ["A": 0, "B": 0]
    let collector = EventCollector()
    logic.calculate(state: &state, emitter: collector.emit)
    #expect(state.scores["A"] == 5)
    #expect(state.scores["B"] == 3)
  }

  @Test func ignoresVotesForUnknownAgents() {
    var state = SimulationState(scores: ["A": 5])
    state.voteResults = ["Unknown": 3]
    let collector = EventCollector()
    logic.calculate(state: &state, emitter: collector.emit)
    #expect(state.scores["A"] == 5)
    // Unknown should not be added to scores
    #expect(state.scores["Unknown"] == nil)
  }
}
