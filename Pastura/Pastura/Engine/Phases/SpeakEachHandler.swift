import Foundation

/// Handles `speak_each` phases where agents speak sequentially with accumulating context.
///
/// Unlike `speak_all`, the conversation log accumulates within sub-rounds,
/// so each agent sees what previous agents said in the current sub-round.
nonisolated struct SpeakEachHandler: PhaseHandler {
  private let promptBuilder = PromptBuilder()
  private let llmCaller = LLMCaller()

  func execute(
    context: PhaseContext,
    state: inout SimulationState
  ) async throws {
    let subRounds = context.phase.subRounds ?? 1
    let promptTemplate =
      context.phase.prompt
      ?? pickLanguage(
        context.scenario.engineLanguage,
        ja: "これまでの会話: {conversation_log}\nあなたの番です。",
        en: "Conversation so far: {conversation_log}\nYour turn.")

    for _ in 1...subRounds {
      for persona in context.scenario.personas {
        guard state.eliminated[persona.name] != true else { continue }

        let systemPrompt = promptBuilder.buildSystemPrompt(
          scenario: context.scenario, persona: persona, phase: context.phase, state: state
        )

        var variables = state.variables
        variables["scoreboard"] = promptBuilder.formatScoreboard(state.scores)
        variables["conversation_log"] = promptBuilder.formatConversationLog(
          state.conversationLog, language: context.scenario.engineLanguage,
          window: context.scenario.logWindow)
        promptBuilder.injectAssigned(into: &variables, personaName: persona.name)
        promptBuilder.injectNotes(into: &variables, personaName: persona.name)
        let userPrompt = promptBuilder.expandTemplate(promptTemplate, variables: variables)

        let output = try await llmCaller.call(
          llm: context.llm, system: systemPrompt, user: userPrompt,
          agentName: persona.name,
          schema: OutputSchema.from(phase: context.phase),
          detector: context.detector,
          expectedLanguage: context.scenario.engineLanguage,
          suspendController: context.suspendController,
          emitter: context.emitter
        )

        context.emitter(
          .agentOutput(agent: persona.name, output: output, phaseType: context.phase.type))

        // Accumulate conversation within sub-rounds
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
}
