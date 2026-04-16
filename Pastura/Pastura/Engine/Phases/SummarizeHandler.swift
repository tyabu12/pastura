import Foundation

/// Handles `summarize` phases that format round summary text.
///
/// Expands a template with state variables. If pairings exist and the template
/// contains `{agent1}`, expands per-pairing. Otherwise expands once.
nonisolated struct SummarizeHandler: PhaseHandler {
  private let promptBuilder = PromptBuilder()

  func execute(
    context: PhaseContext,
    state: inout SimulationState
  ) async throws {
    let template = context.phase.template ?? "ラウンド {current_round} 完了"

    if !state.pairings.isEmpty && template.contains("{agent1}") {
      // Expand template per pairing
      var lines: [String] = []
      for pairing in state.pairings {
        // Superset of the prototype's pair path: we also merge state.variables so
        // shared placeholders like {scoreboard}, {current_round}, {vote_results}
        // resolve inside pair expansion. Pair-specific keys (agent1, action1, …)
        // are written *after* the merge so they can never be shadowed by a
        // user-defined state.variables entry with the same name.
        var variables = state.variables
        variables["agent1"] = pairing.agent1
        variables["action1"] = pairing.action1 ?? "?"
        variables["agent2"] = pairing.agent2
        variables["action2"] = pairing.action2 ?? "?"
        variables["score1"] = "\(state.scores[pairing.agent1] ?? 0)"
        variables["score2"] = "\(state.scores[pairing.agent2] ?? 0)"
        variables["scoreboard"] = promptBuilder.formatScoreboard(state.scores)
        variables["current_round"] = "\(state.currentRound)"
        lines.append(promptBuilder.expandTemplate(template, variables: variables))
      }
      context.emitter(.summary(text: lines.joined(separator: "\n")))
    } else {
      // Simple expansion
      var variables = state.variables
      variables["scoreboard"] = promptBuilder.formatScoreboard(state.scores)
      variables["current_round"] = "\(state.currentRound)"
      let text = promptBuilder.expandTemplate(template, variables: variables)
      context.emitter(.summary(text: text))
    }
  }
}
