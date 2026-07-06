import Foundation

/// Handles `reflect` phases where each agent privately updates a personal memo.
///
/// Each non-eliminated agent makes one LLM call producing `{ note }` — a short
/// private memo (impressions, suspicions, plans). The note is stored under the
/// reserved per-persona key `notes_<name>` in ``SimulationState/variables``
/// (mirroring the `assigned_<name>` namespace, see
/// ``PromptBuilder/injectNotes(into:personaName:)``) and surfaced back to that
/// agent — and only that agent — in every subsequent LLM call's system prompt.
///
/// Unlike the speak handlers, the note is **private**: it is never appended to
/// `conversationLog` (so other agents can't see it) and never written to
/// `lastOutputs` (so it doesn't replace the public last output). Only the
/// `.agentOutput` event is emitted, keeping the persistence / UI / replay flow
/// identical to the other LLM phases.
nonisolated struct ReflectHandler: PhaseHandler {
  private let promptBuilder = PromptBuilder()
  private let llmCaller = LLMCaller()

  func execute(
    context: PhaseContext,
    state: inout SimulationState
  ) async throws {
    let promptTemplate =
      context.phase.prompt
      ?? pickLanguage(
        context.scenario.engineLanguage,
        ja: "これまでの会話: {conversation_log}\nこれまでの状況を踏まえ、所感・警戒・今後の方針を自分用のメモとして更新してください。",
        en:
          "Conversation so far: {conversation_log}\nUpdate your private notes: impressions, suspicions, and your plan going forward."
      )

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
      promptBuilder.injectWhispers(into: &variables, personaName: persona.name)
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

      // Persist the memo privately under the reserved `notes_<name>` namespace.
      // Only write a non-empty note: a failed/empty inference (LLMCaller returns
      // "" after exhausting the empty-field retry budget) must not erase the
      // agent's memo from a previous round.
      let note = output.fields["note"] ?? ""
      if !note.isEmpty {
        state.variables["notes_\(persona.name)"] = note
      }

      // Deliberately NOT appended to `conversationLog`: the note is private, so
      // other agents (whose prompts include the log) must never see it.
      // Deliberately NOT written to `lastOutputs`: the public last output must
      // not be replaced by a private memo (it feeds `{last_output}`-style
      // downstream reads and the public display).
    }
  }
}
