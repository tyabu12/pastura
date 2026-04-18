import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct PrisonersDilemmaLogicTests {
  let logic = PrisonersDilemmaLogic()

  @Test func cooperateCooperate() {
    var state = makeState()
    state.pairings = [Pairing(agent1: "A", agent2: "B", action1: "cooperate", action2: "cooperate")]
    let collector = EventCollector()
    logic.calculate(state: &state, emitter: collector.emit)
    #expect(state.scores["A"] == 3)
    #expect(state.scores["B"] == 3)
  }

  @Test func cooperateBetray() {
    var state = makeState()
    state.pairings = [Pairing(agent1: "A", agent2: "B", action1: "cooperate", action2: "betray")]
    let collector = EventCollector()
    logic.calculate(state: &state, emitter: collector.emit)
    #expect(state.scores["A"] == 0)
    #expect(state.scores["B"] == 5)
  }

  @Test func betrayCooperate() {
    var state = makeState()
    state.pairings = [Pairing(agent1: "A", agent2: "B", action1: "betray", action2: "cooperate")]
    let collector = EventCollector()
    logic.calculate(state: &state, emitter: collector.emit)
    #expect(state.scores["A"] == 5)
    #expect(state.scores["B"] == 0)
  }

  @Test func betrayBetray() {
    var state = makeState()
    state.pairings = [Pairing(agent1: "A", agent2: "B", action1: "betray", action2: "betray")]
    let collector = EventCollector()
    logic.calculate(state: &state, emitter: collector.emit)
    #expect(state.scores["A"] == 1)
    #expect(state.scores["B"] == 1)
  }

  @Test func clearsStatePairingsAfterCalc() {
    var state = makeState()
    state.pairings = [Pairing(agent1: "A", agent2: "B", action1: "cooperate", action2: "cooperate")]
    let collector = EventCollector()
    logic.calculate(state: &state, emitter: collector.emit)
    #expect(state.pairings.isEmpty)
  }

  @Test func emitsScoreUpdateEvent() {
    var state = makeState()
    state.pairings = [Pairing(agent1: "A", agent2: "B", action1: "cooperate", action2: "cooperate")]
    let collector = EventCollector()
    logic.calculate(state: &state, emitter: collector.emit)
    let scoreEvents = collector.events.filter {
      if case .scoreUpdate = $0 { return true }
      return false
    }
    #expect(scoreEvents.count == 1)
  }

  private func makeState() -> SimulationState {
    SimulationState(scores: ["A": 0, "B": 0])
  }
}
