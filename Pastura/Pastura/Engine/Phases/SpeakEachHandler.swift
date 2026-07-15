import Foundation

/// Handles `speak_each` phases where agents speak sequentially with accumulating context.
///
/// Unlike `speak_all`, the conversation log accumulates within sub-rounds,
/// so each agent sees what previous agents said in the current sub-round.
///
/// A turn-degradable LLM failure is routed through `context.turnGate`
/// (ADR-021 D1/D2): the failing agent's turn is skipped — no
/// `.agentOutput`, no `conversationLog` entry, and any stale
/// `lastOutputs` entry for that agent is cleared — and the sub-round
/// continues with the next persona.
nonisolated struct SpeakEachHandler: PhaseHandler {
  private let promptBuilder = PromptBuilder()

  func execute(
    context: PhaseContext,
    state: inout SimulationState
  ) async throws {
    // `subRounds` is untrusted (any un-vetted YAML ingest can set `rounds: 0`
    // or a negative); clamp to ≥1 so `1...subRounds` below can't form an
    // invalid ClosedRange and trap. Mirrors WhisperHandler's guard on the
    // same "sub-rounds" input.
    let subRounds = max(1, context.phase.subRounds ?? 1)
    let promptTemplate =
      context.phase.prompt
      ?? pickLanguage(
        context.scenario.engineLanguage,
        ja: "これまでの会話: {conversation_log}\nあなたの番です。",
        en: "Conversation so far: {conversation_log}\nYour turn.")

    for _ in 1...subRounds {
      for persona in context.scenario.personas {
        guard state.eliminated[persona.name] != true else { continue }
        try await speakTurn(
          context: context, persona: persona, promptTemplate: promptTemplate, state: &state)
      }
    }
  }

  /// Runs one persona's turn: builds the prompt, routes the LLM call through
  /// `context.turnGate` (ADR-021 D1/D2), and accumulates `state` on success.
  /// On a skipped turn, writes nothing and clears any stale `lastOutputs`
  /// entry. Split out of `execute` to stay under SwiftLint's
  /// `function_body_length`.
  private func speakTurn(
    context: PhaseContext,
    persona: Persona,
    promptTemplate: String,
    state: inout SimulationState
  ) async throws {
    // Construct per turn with the injected logger (stateless value — cheap).
    let llmCaller = LLMCaller(logger: context.logger)
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
    promptBuilder.injectRelationships(into: &variables, personaName: persona.name)
    promptBuilder.injectMood(into: &variables, personaName: persona.name)
    let userPrompt = promptBuilder.expandTemplate(promptTemplate, variables: variables)

    guard
      let output = try await context.turnGate.attempt(
        agent: persona.name, phaseType: context.phase.type, emitter: context.emitter,
        work: {
          try await llmCaller.call(
            llm: context.llm, system: systemPrompt, user: userPrompt,
            agentName: persona.name,
            schema: OutputSchema.from(phase: context.phase),
            detector: context.detector,
            expectedLanguage: context.scenario.engineLanguage,
            suspendController: context.suspendController,
            emitter: context.emitter
          )
        })
    else {
      // Turn skipped (ADR-021 D2): write nothing, and clear any stale
      // prior-round output so downstream consumers keyed on
      // `lastOutputs` don't silently read a decision that never
      // happened this turn.
      state.lastOutputs[persona.name] = nil
      return
    }

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
    promptBuilder.captureMood(
      from: output, into: &state.variables, personaName: persona.name)
  }
}
