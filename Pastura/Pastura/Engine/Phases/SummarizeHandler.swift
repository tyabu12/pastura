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
        // Precedence: state.variables first, derived vars overwrite (prototype parity).
        // Ensures pair-specific keys like {agent1} are never shadowed by a
        // user-defined state.variables["agent1"].
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
