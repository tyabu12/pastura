import Foundation

/// Handles `choose` phases where agents select from options.
///
/// Supports two modes: round-robin pairing (adjacent pairs, each agent calls LLM
/// with opponent context) or individual choice (each agent chooses independently).
/// Invalid actions fall back to `options[0]` via `validateAction`.
///
/// `validateAction` is the **sole** value constraint: the `action` field is a
/// `.choice` in the grammar (structure-only — no value enumeration; see
/// ``OutputSchema/Kind/choice`` and ADR-002 §Amendment 2026-06-14, #599), so
/// the runtime check is what keeps the result within the option set. The model
/// is steered toward valid options by ``PromptBuilder``, which lists them in
/// the prompt, so the fallback is rare in practice.
///
/// A turn-degradable LLM failure is routed through `context.turnGate`
/// (ADR-021 D1/D2). In **round-robin**, a skipped call drops the *whole
/// pairing* — a pairing with one real and one absent action would flow into
/// `PrisonersDilemmaLogic`'s `?? "cooperate"` default, i.e. fabrication — while
/// the partner's already-emitted `.agentOutput` and `lastOutputs` still stand
/// (consumed by `EventReactivePayoffLogic`). In **individual** mode a skipped
/// turn writes nothing and clears the agent's stale `lastOutputs`.
nonisolated struct ChooseHandler: PhaseHandler {
  private let promptBuilder = PromptBuilder()

  /// Immutable per-phase invariants for the round-robin call helper, bundled to
  /// keep ``callAgent(persona:opponent:run:state:succeeded:)`` under SwiftLint's
  /// `function_parameter_count` (`state` / `succeeded` stay `inout` args).
  nonisolated private struct Run {
    let context: PhaseContext
    let promptTemplate: String
  }

  func execute(
    context: PhaseContext,
    state: inout SimulationState
  ) async throws {
    let promptTemplate =
      context.phase.prompt
      ?? pickLanguage(
        context.scenario.engineLanguage,
        ja: "選択してください。",
        en: "Make a choice.")
    let options = context.phase.options ?? []

    if context.phase.pairing == .roundRobin {
      try await executeRoundRobin(
        context: context, state: &state,
        promptTemplate: promptTemplate, options: options
      )
    } else {
      try await executeIndividual(
        context: context, state: &state, promptTemplate: promptTemplate
      )
    }
  }

  // MARK: - Round Robin

  private func executeRoundRobin(
    context: PhaseContext, state: inout SimulationState,
    promptTemplate: String, options: [String]
  ) async throws {
    let active = context.scenario.personas.filter { state.eliminated[$0.name] != true }
    let pairs = (0..<active.count).map { idx in
      (active[idx], active[(idx + 1) % active.count])
    }

    // Agents that produced a successful turn somewhere in this phase. Each agent
    // participates in two adjacency pairs, so a skip on one call must not clear
    // a valid output the agent produced on its other call (ADR-021 D2).
    var succeeded: Set<String> = []
    let run = Run(context: context, promptTemplate: promptTemplate)
    for (persona1, persona2) in pairs {
      let output1 = try await callAgent(
        persona: persona1, opponent: persona2,
        run: run, state: &state, succeeded: &succeeded
      )
      let output2 = try await callAgent(
        persona: persona2, opponent: persona1,
        run: run, state: &state, succeeded: &succeeded
      )

      // Drop the whole pairing if either member skipped (ADR-021 D2): a
      // half-real pairing would fabricate the missing action downstream.
      guard let out1 = output1, let out2 = output2 else { continue }

      let action1 = validateAction(out1.action ?? "", options: options)
      let action2 = validateAction(out2.action ?? "", options: options)
      state.pairings.append(
        Pairing(agent1: persona1.name, agent2: persona2.name, action1: action1, action2: action2)
      )
      context.emitter(
        .pairingResult(
          agent1: persona1.name, action1: action1,
          agent2: persona2.name, action2: action2
        ))
    }
  }

  /// Runs one member's round-robin call through `context.turnGate`. On success,
  /// emits `.agentOutput`, records `lastOutputs`, marks the agent in `succeeded`,
  /// and returns the output. On a skipped turn, emits nothing and clears the
  /// agent's stale `lastOutputs` **only if it hasn't already succeeded this
  /// phase** (its other pairing may hold a valid output), then returns `nil`.
  private func callAgent(
    persona: Persona, opponent: Persona,
    run: Run, state: inout SimulationState,
    succeeded: inout Set<String>
  ) async throws -> TurnOutput? {
    let context = run.context
    let systemPrompt = promptBuilder.buildSystemPrompt(
      scenario: context.scenario, persona: persona, phase: context.phase, state: state
    )

    var variables = state.variables
    variables["opponent_name"] = opponent.name
    variables["scoreboard"] = promptBuilder.formatScoreboard(state.scores)
    variables["conversation_log"] = promptBuilder.formatConversationLog(
      state.conversationLog, language: context.scenario.engineLanguage,
      window: context.scenario.logWindow)
    promptBuilder.injectAssigned(into: &variables, personaName: persona.name)
    promptBuilder.injectNotes(into: &variables, personaName: persona.name)
    promptBuilder.injectWhispers(into: &variables, personaName: persona.name)
    promptBuilder.injectRelationships(into: &variables, personaName: persona.name)
    promptBuilder.injectMood(into: &variables, personaName: persona.name)
    let userPrompt = promptBuilder.expandTemplate(run.promptTemplate, variables: variables)

    // Construct per turn with the injected logger (stateless value — cheap).
    let llmCaller = LLMCaller(logger: context.logger)
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
      if !succeeded.contains(persona.name) { state.lastOutputs[persona.name] = nil }
      return nil
    }
    succeeded.insert(persona.name)
    context.emitter(
      .agentOutput(agent: persona.name, output: output, phaseType: context.phase.type))
    state.lastOutputs[persona.name] = output
    promptBuilder.captureMood(
      from: output, into: &state.variables, personaName: persona.name)
    return output
  }

  // MARK: - Individual

  private func executeIndividual(
    context: PhaseContext, state: inout SimulationState,
    promptTemplate: String
  ) async throws {
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
      promptBuilder.injectRelationships(into: &variables, personaName: persona.name)
      // executeIndividual omits injectWhispers (a real handler asymmetry), but
      // mood is symmetric — surfaced in every LLM phase (like injectNotes).
      promptBuilder.injectMood(into: &variables, personaName: persona.name)
      let userPrompt = promptBuilder.expandTemplate(promptTemplate, variables: variables)

      // Construct per run with the injected logger (stateless value — cheap).
      let llmCaller = LLMCaller(logger: context.logger)
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
        // Skipped (ADR-021 D2): write nothing, clear any stale prior-round output.
        state.lastOutputs[persona.name] = nil
        continue
      }
      context.emitter(
        .agentOutput(agent: persona.name, output: output, phaseType: context.phase.type))

      state.lastOutputs[persona.name] = output
      promptBuilder.captureMood(
        from: output, into: &state.variables, personaName: persona.name)
    }
  }

  // MARK: - Helpers

  private func validateAction(_ action: String, options: [String]) -> String {
    if options.isEmpty { return action }
    return options.contains(action) ? action : options[0]
  }
}
