import Foundation

/// Prisoner's dilemma scoring logic.
///
/// Payoff matrix:
/// - cooperate/cooperate = 3, 3
/// - cooperate/betray = 0, 5
/// - betray/cooperate = 5, 0
/// - betray/betray = 1, 1
///
/// Reads actions from `Pairing.action1/action2` and clears pairings after scoring.
nonisolated struct PrisonersDilemmaLogic: Sendable {

  func calculate(
    state: inout SimulationState,
    emitter: @Sendable (SimulationEvent) -> Void
  ) {
    for pairing in state.pairings {
      let act1 = pairing.action1 ?? "cooperate"
      let act2 = pairing.action2 ?? "cooperate"

      switch (act1, act2) {
      case ("cooperate", "cooperate"):
        state.scores[pairing.agent1, default: 0] += 3
        state.scores[pairing.agent2, default: 0] += 3
      case ("cooperate", "betray"):
        // agent1 gets 0, agent2 gets 5
        state.scores[pairing.agent2, default: 0] += 5
      case ("betray", "cooperate"):
        state.scores[pairing.agent1, default: 0] += 5
      // agent2 gets 0
      default:
        // betray/betray
        state.scores[pairing.agent1, default: 0] += 1
        state.scores[pairing.agent2, default: 0] += 1
      }
    }

    emitter(.scoreUpdate(scores: state.scores))
    state.pairings = []
  }
}
