import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct PairwisePayoffLogicTests {
  let logic = PairwisePayoffLogic()

  /// A localized (Japanese-token) payoff table — the motivating case for
  /// ADR-027, unscorable by the pre-ADR hardcoded English `switch`.
  private let jaTable: [PayoffRule] = [
    PayoffRule(when: ["協力", "協力"], points: [3, 3]),
    PayoffRule(when: ["協力", "裏切り"], points: [0, 5]),
    PayoffRule(when: ["裏切り", "協力"], points: [5, 0]),
    PayoffRule(when: ["裏切り", "裏切り"], points: [1, 1])
  ]

  @Test func matchesRowAndAwardsPointsPositionally() {
    var state = makeState()
    state.pairings = [Pairing(agent1: "A", agent2: "B", action1: "協力", action2: "裏切り")]
    let collector = EventCollector()
    logic.calculate(state: &state, payoff: jaTable, emitter: collector.emit)
    #expect(state.scores["A"] == 0)
    #expect(state.scores["B"] == 5)
  }

  @Test func unmatchedActionPairScoresNothing() {
    var state = makeState()
    // Neither action appears in any row's `when`.
    state.pairings = [Pairing(agent1: "A", agent2: "B", action1: "abstain", action2: "abstain")]
    let collector = EventCollector()
    logic.calculate(state: &state, payoff: jaTable, emitter: collector.emit)
    #expect(state.scores["A"] == 0)
    #expect(state.scores["B"] == 0)
  }

  @Test func nilActionScoresNothing() {
    var state = makeState()
    // A half-real pairing (action2 nil) matches no row — no fabricated verdict.
    state.pairings = [Pairing(agent1: "A", agent2: "B", action1: "協力", action2: nil)]
    let collector = EventCollector()
    logic.calculate(state: &state, payoff: jaTable, emitter: collector.emit)
    #expect(state.scores["A"] == 0)
    #expect(state.scores["B"] == 0)
  }

  @Test func emptyTableScoresNothing() {
    var state = makeState()
    state.pairings = [Pairing(agent1: "A", agent2: "B", action1: "協力", action2: "協力")]
    let collector = EventCollector()
    logic.calculate(state: &state, payoff: [], emitter: collector.emit)
    #expect(state.scores["A"] == 0)
    #expect(state.scores["B"] == 0)
  }

  @Test func malformedRowArityIsSkippedDefensively() {
    var state = makeState()
    state.pairings = [Pairing(agent1: "A", agent2: "B", action1: "x", action2: "y")]
    // A row whose `points` is not two elements must not crash (index guard) —
    // it simply scores nothing. The loader rejects this arity, but the logic
    // guards defensively per ADR-027.
    let badTable = [PayoffRule(when: ["x", "y"], points: [7])]
    let collector = EventCollector()
    logic.calculate(state: &state, payoff: badTable, emitter: collector.emit)
    #expect(state.scores["A"] == 0)
    #expect(state.scores["B"] == 0)
  }

  @Test func firstMatchingRowWins() {
    var state = makeState()
    state.pairings = [Pairing(agent1: "A", agent2: "B", action1: "協力", action2: "協力")]
    let table = [
      PayoffRule(when: ["協力", "協力"], points: [3, 3]),
      PayoffRule(when: ["協力", "協力"], points: [9, 9])
    ]
    let collector = EventCollector()
    logic.calculate(state: &state, payoff: table, emitter: collector.emit)
    #expect(state.scores["A"] == 3)
    #expect(state.scores["B"] == 3)
  }

  @Test func clearsStatePairingsAfterCalc() {
    var state = makeState()
    state.pairings = [Pairing(agent1: "A", agent2: "B", action1: "協力", action2: "協力")]
    let collector = EventCollector()
    logic.calculate(state: &state, payoff: jaTable, emitter: collector.emit)
    #expect(state.pairings.isEmpty)
  }

  @Test func emitsScoreUpdateEvent() {
    var state = makeState()
    state.pairings = [Pairing(agent1: "A", agent2: "B", action1: "協力", action2: "協力")]
    let collector = EventCollector()
    logic.calculate(state: &state, payoff: jaTable, emitter: collector.emit)
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
