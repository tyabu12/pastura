import Testing

@testable import Pastura

/// Unit tests for `EventReactivePayoffLogic` (#931).
///
/// The favored action is read from `state.variables[favoredVariable]`;
/// these tests write it directly rather than routing through
/// `EventInjectHandler`, keeping the scoring logic under isolated test.
@Suite(.timeLimit(.minutes(1)))
struct EventReactivePayoffLogicTests {
  let logic = EventReactivePayoffLogic()
  let favoredKey = "current_event__favors"

  private func output(action: String) -> TurnOutput {
    TurnOutput(fields: ["action": action])
  }

  // MARK: - Matched / unmatched action

  @Test func rewardsOnlyAgentsWhoMatchedFavoredAction() {
    var state = SimulationState(scores: ["Alice": 0, "Bob": 0])
    state.lastOutputs = [
      "Alice": output(action: "betray"),
      "Bob": output(action: "cooperate")
    ]
    state.variables[favoredKey] = "betray"
    let collector = EventCollector()

    logic.calculate(state: &state, favoredVariable: favoredKey, emitter: collector.emit)

    // Only the betray reader gains points; the cooperate agent gains 0.
    #expect(state.scores["Alice"] == EventReactivePayoffLogic.matchReward)
    #expect(state.scores["Bob"] == 0)
  }

  @Test func symmetricForCooperateFavored() {
    var state = SimulationState(scores: ["Alice": 0, "Bob": 0])
    state.lastOutputs = [
      "Alice": output(action: "betray"),
      "Bob": output(action: "cooperate")
    ]
    state.variables[favoredKey] = "cooperate"
    let collector = EventCollector()

    logic.calculate(state: &state, favoredVariable: favoredKey, emitter: collector.emit)

    #expect(state.scores["Alice"] == 0)
    #expect(state.scores["Bob"] == EventReactivePayoffLogic.matchReward)
  }

  @Test func rewardAddsToExistingScore() {
    var state = SimulationState(scores: ["Alice": 5])
    state.lastOutputs = ["Alice": output(action: "betray")]
    state.variables[favoredKey] = "betray"
    let collector = EventCollector()

    logic.calculate(state: &state, favoredVariable: favoredKey, emitter: collector.emit)

    #expect(state.scores["Alice"] == 5 + EventReactivePayoffLogic.matchReward)
  }

  // MARK: - No-op paths (missing / empty favored var, plain-string list)

  @Test func missingFavoredVariableIsNoOp() {
    var state = SimulationState(scores: ["Alice": 0, "Bob": 0])
    state.lastOutputs = [
      "Alice": output(action: "betray"),
      "Bob": output(action: "cooperate")
    ]
    // favoredKey absent → simulates a plain-string event list (no companion var).
    let collector = EventCollector()

    logic.calculate(state: &state, favoredVariable: favoredKey, emitter: collector.emit)

    #expect(state.scores["Alice"] == 0)
    #expect(state.scores["Bob"] == 0)
  }

  @Test func emptyFavoredVariableIsNoOp() {
    var state = SimulationState(scores: ["Alice": 0])
    state.lastOutputs = ["Alice": output(action: "betray")]
    // "" is what EventInjectHandler writes on a miss round — must not reward.
    state.variables[favoredKey] = ""
    let collector = EventCollector()

    logic.calculate(state: &state, favoredVariable: favoredKey, emitter: collector.emit)

    #expect(state.scores["Alice"] == 0)
  }

  @Test func alwaysEmitsScoreUpdate() {
    var state = SimulationState(scores: ["Alice": 0])
    state.lastOutputs = ["Alice": output(action: "betray")]
    // No favored var → inert, but a scoreUpdate must still be emitted so the
    // UI/persistence pipeline sees a well-formed code-phase result.
    let collector = EventCollector()

    logic.calculate(state: &state, favoredVariable: favoredKey, emitter: collector.emit)

    let scoreUpdates = collector.events.filter {
      if case .scoreUpdate = $0 { return true }
      return false
    }
    #expect(scoreUpdates.count == 1)
  }

  // MARK: - Agent gating

  @Test func ignoresOutputsWithoutASeededScore() {
    var state = SimulationState(scores: ["Alice": 0])
    state.lastOutputs = [
      "Alice": output(action: "betray"),
      // No score seeded for "Ghost" → gated out (not a live agent).
      "Ghost": output(action: "betray")
    ]
    state.variables[favoredKey] = "betray"
    let collector = EventCollector()

    logic.calculate(state: &state, favoredVariable: favoredKey, emitter: collector.emit)

    #expect(state.scores["Alice"] == EventReactivePayoffLogic.matchReward)
    #expect(state.scores["Ghost"] == nil)
  }
}
