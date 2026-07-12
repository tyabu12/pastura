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

    // Find the most-voted agent. Deterministic tie-break: (count desc, name
    // desc) — the canonical order shared with ConditionEvaluator's
    // `vote_winner` derivation, so an `eliminate` phase and a `conditional`
    // reading `vote_winner` in the same round never disagree on a tie (#1056).
    guard
      let mostVoted = state.voteResults
        .sorted(by: { ($0.value, $0.key) > ($1.value, $1.key) })
        .first
    else { return }

    state.eliminated[mostVoted.key] = true
    context.emitter(.elimination(agent: mostVoted.key, voteCount: mostVoted.value))
  }
}
