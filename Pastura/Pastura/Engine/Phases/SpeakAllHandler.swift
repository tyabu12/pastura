import Foundation

/// Handles `speak_all` phases where all agents speak simultaneously.
///
/// Each non-eliminated agent generates output via LLM. Outputs are added
/// to the conversation log and stored in `lastOutputs` for subsequent phases.
nonisolated struct SpeakAllHandler: PhaseHandler {
  private let promptBuilder = PromptBuilder()
  private let llmCaller = LLMCaller()

  func execute(
    scenario: Scenario,
    phase: Phase,
    state: inout SimulationState,
    llm: LLMService,
    emitter: @Sendable (SimulationEvent) -> Void
  ) async throws {
    let promptTemplate = phase.prompt ?? "あなたの意見を述べてください。"

    for persona in scenario.personas {
      guard state.eliminated[persona.name] != true else { continue }

      let systemPrompt = promptBuilder.buildSystemPrompt(
        scenario: scenario, persona: persona, phase: phase, state: state
      )

      var variables = state.variables
      variables["scoreboard"] = formatScoreboard(state.scores)
      variables["conversation_log"] = promptBuilder.formatConversationLog(state.conversationLog)
      let userPrompt = promptBuilder.expandTemplate(promptTemplate, variables: variables)

      let output = try await llmCaller.call(
        llm: llm, system: systemPrompt, user: userPrompt,
        agentName: persona.name, emitter: emitter
      )

      emitter(.agentOutput(agent: persona.name, output: output, phaseType: phase.type))

      // Update state
      let mainField = promptBuilder.getMainField(phase: phase)
      let content = output.fields[mainField] ?? ""
      state.conversationLog.append(
        ConversationEntry(
          agentName: persona.name, content: content,
          phaseType: phase.type, round: state.currentRound
        )
      )
      state.lastOutputs[persona.name] = output
    }
  }

  private func formatScoreboard(_ scores: [String: Int]) -> String {
    let pairs = scores.sorted { $0.key < $1.key }
      .map { "\"\($0.key)\": \($0.value)" }
    return "{\(pairs.joined(separator: ", "))}"
  }
}
