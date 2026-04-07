import Foundation

/// Vote tally scoring logic.
///
/// Adds each agent's vote count from `state.voteResults` to their cumulative score.
nonisolated struct VoteTallyLogic: Sendable {

  func calculate(
    state: inout SimulationState,
    emitter: @Sendable (SimulationEvent) -> Void
  ) {
    for (name, count) in state.voteResults where state.scores[name] != nil {
      state.scores[name, default: 0] += count
    }
    emitter(.scoreUpdate(scores: state.scores))
  }
}
