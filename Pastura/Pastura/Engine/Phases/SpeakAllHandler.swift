import Foundation

/// Handles `speak_all` phases where all agents speak simultaneously.
///
/// Each non-eliminated agent generates output via LLM. Outputs are added
/// to the conversation log and stored in `lastOutputs` for subsequent phases.
nonisolated struct SpeakAllHandler: PhaseHandler {
  private let promptBuilder = PromptBuilder()
  private let llmCaller = LLMCaller()

  func execute(
    context: PhaseContext,
    state: inout SimulationState
  ) async throws {
    let promptTemplate = context.phase.prompt ?? "あなたの意見を述べてください。"

    for persona in context.scenario.personas {
      guard state.eliminated[persona.name] != true else { continue }

      let systemPrompt = promptBuilder.buildSystemPrompt(
        scenario: context.scenario, persona: persona, phase: context.phase, state: state
      )

      var variables = state.variables
      variables["scoreboard"] = promptBuilder.formatScoreboard(state.scores)
      variables["conversation_log"] = promptBuilder.formatConversationLog(state.conversationLog)
      let userPrompt = promptBuilder.expandTemplate(promptTemplate, variables: variables)

      let output = try await llmCaller.call(
        llm: context.llm, system: systemPrompt, user: userPrompt,
        agentName: persona.name, emitter: context.emitter
      )

      context.emitter(
        .agentOutput(agent: persona.name, output: output, phaseType: context.phase.type))

      // Update state
      let mainField = promptBuilder.getMainField(phase: context.phase)
      let content = output.fields[mainField] ?? ""
      state.conversationLog.append(
        ConversationEntry(
          agentName: persona.name, content: content,
          phaseType: context.phase.type, round: state.currentRound
        )
      )
      state.lastOutputs[persona.name] = output
    }
  }
}
