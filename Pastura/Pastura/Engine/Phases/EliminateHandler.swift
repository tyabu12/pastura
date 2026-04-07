import Foundation

/// Handles `eliminate` phases that remove the most-voted agent.
///
/// Finds the agent with the highest vote count in `state.voteResults`,
/// marks them as eliminated, and emits an elimination event.
nonisolated struct EliminateHandler: PhaseHandler {

  func execute(
    scenario: Scenario,
    phase: Phase,
    state: inout SimulationState,
    llm: LLMService,
    emitter: @Sendable (SimulationEvent) -> Void
  ) async throws {
    guard !state.voteResults.isEmpty else { return }

    // Find the most-voted agent (deterministic tie-breaking: sorted name)
    let mostVoted = state.voteResults
      .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
      .first!

    state.eliminated[mostVoted.key] = true
    emitter(.elimination(agent: mostVoted.key, voteCount: mostVoted.value))
  }
}
