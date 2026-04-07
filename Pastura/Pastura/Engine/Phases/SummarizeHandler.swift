import Foundation

/// Handles `summarize` phases that format round summary text.
///
/// Expands a template with state variables. If pairings exist and the template
/// contains `{agent1}`, expands per-pairing. Otherwise expands once.
nonisolated struct SummarizeHandler: PhaseHandler {
  private let promptBuilder = PromptBuilder()

  func execute(
    scenario: Scenario,
    phase: Phase,
    state: inout SimulationState,
    llm: LLMService,
    emitter: @Sendable (SimulationEvent) -> Void
  ) async throws {
    let template = phase.template ?? "ラウンド {current_round} 完了"

    if !state.pairings.isEmpty && template.contains("{agent1}") {
      // Expand template per pairing
      var lines: [String] = []
      for pairing in state.pairings {
        var variables: [String: String] = [
          "agent1": pairing.agent1,
          "action1": pairing.action1 ?? "?",
          "agent2": pairing.agent2,
          "action2": pairing.action2 ?? "?",
          "score1": "\(state.scores[pairing.agent1] ?? 0)",
          "score2": "\(state.scores[pairing.agent2] ?? 0)"
        ]
        // Merge state variables
        for (key, value) in state.variables {
          variables[key] = value
        }
        lines.append(promptBuilder.expandTemplate(template, variables: variables))
      }
      emitter(.summary(text: lines.joined(separator: "\n")))
    } else {
      // Simple expansion
      var variables = state.variables
      variables["current_round"] = "\(state.currentRound)"
      let text = promptBuilder.expandTemplate(template, variables: variables)
      emitter(.summary(text: text))
    }
  }
}
