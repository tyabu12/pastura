import Foundation

/// Handles `choose` phases where agents select from options.
///
/// Supports two modes: round-robin pairing (adjacent pairs, each agent calls LLM
/// with opponent context) or individual choice (each agent chooses independently).
/// Invalid actions fall back to `options[0]`.
nonisolated struct ChooseHandler: PhaseHandler {
  private let promptBuilder = PromptBuilder()
  private let llmCaller = LLMCaller()

  func execute(
    context: PhaseContext,
    state: inout SimulationState
  ) async throws {
    let promptTemplate = context.phase.prompt ?? "選択してください。"
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

    for (persona1, persona2) in pairs {
      let output1 = try await callAgent(
        persona: persona1, opponent: persona2,
        context: context, state: state, promptTemplate: promptTemplate
      )
      let action1 = validateAction(output1.action ?? "", options: options)
      state.lastOutputs[persona1.name] = output1

      let output2 = try await callAgent(
        persona: persona2, opponent: persona1,
        context: context, state: state, promptTemplate: promptTemplate
      )
      let action2 = validateAction(output2.action ?? "", options: options)
      state.lastOutputs[persona2.name] = output2

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

  private func callAgent(
    persona: Persona, opponent: Persona,
    context: PhaseContext, state: SimulationState,
    promptTemplate: String
  ) async throws -> TurnOutput {
    let systemPrompt = promptBuilder.buildSystemPrompt(
      scenario: context.scenario, persona: persona, phase: context.phase, state: state
    )

    var variables = state.variables
    variables["opponent_name"] = opponent.name
    variables["scoreboard"] = formatScoreboard(state.scores)
    variables["conversation_log"] = promptBuilder.formatConversationLog(state.conversationLog)
    let userPrompt = promptBuilder.expandTemplate(promptTemplate, variables: variables)

    let output = try await llmCaller.call(
      llm: context.llm, system: systemPrompt, user: userPrompt,
      agentName: persona.name, emitter: context.emitter
    )
    context.emitter(
      .agentOutput(agent: persona.name, output: output, phaseType: context.phase.type))
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
      variables["scoreboard"] = formatScoreboard(state.scores)
      variables["conversation_log"] = promptBuilder.formatConversationLog(state.conversationLog)
      let userPrompt = promptBuilder.expandTemplate(promptTemplate, variables: variables)

      let output = try await llmCaller.call(
        llm: context.llm, system: systemPrompt, user: userPrompt,
        agentName: persona.name, emitter: context.emitter
      )
      context.emitter(
        .agentOutput(agent: persona.name, output: output, phaseType: context.phase.type))

      state.lastOutputs[persona.name] = output
    }
  }

  // MARK: - Helpers

  private func validateAction(_ action: String, options: [String]) -> String {
    if options.isEmpty { return action }
    return options.contains(action) ? action : options[0]
  }

  private func formatScoreboard(_ scores: [String: Int]) -> String {
    let pairs = scores.sorted { $0.key < $1.key }
      .map { "\"\($0.key)\": \($0.value)" }
    return "{\(pairs.joined(separator: ", "))}"
  }
}
