import Foundation

/// Handles `eliminate` phases that remove the most-voted agent.
///
/// Finds the agent with the highest vote count in `state.voteResults`,
/// marks them as eliminated, and emits an elimination event.
nonisolated struct EliminateHandler: PhaseHandler {

  func execute(
    context: PhaseContext,
    state: inout SimulationState
  ) async throws {
    guard !state.voteResults.isEmpty else { return }

    // Find the most-voted agent via the shared canonical tie-break (count
    // desc, name desc), so an `eliminate` phase and a `conditional` reading
    // `vote_winner` in the same round never disagree on a tie (#1056).
    guard let mostVoted = VoteTally.winner(state.voteResults) else { return }

    state.eliminated[mostVoted.key] = true
    context.emitter(.elimination(agent: mostVoted.key, voteCount: mostVoted.value))
  }
}
