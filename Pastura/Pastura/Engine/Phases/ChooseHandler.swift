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
    scenario: Scenario,
    phase: Phase,
    state: inout SimulationState,
    llm: LLMService,
    emitter: @Sendable (SimulationEvent) -> Void
  ) async throws {
    let promptTemplate = phase.prompt ?? "選択してください。"
    let options = phase.options ?? []

    if phase.pairing == .roundRobin {
      try await executeRoundRobin(
        scenario: scenario, phase: phase, state: &state, llm: llm,
        emitter: emitter, promptTemplate: promptTemplate, options: options
      )
    } else {
      try await executeIndividual(
        scenario: scenario, phase: phase, state: &state, llm: llm,
        emitter: emitter, promptTemplate: promptTemplate, options: options
      )
    }
  }

  // MARK: - Round Robin

  private func executeRoundRobin(
    scenario: Scenario,
    phase: Phase,
    state: inout SimulationState,
    llm: LLMService,
    emitter: @Sendable (SimulationEvent) -> Void,
    promptTemplate: String,
    options: [String]
  ) async throws {
    let active = scenario.personas.filter { state.eliminated[$0.name] != true }
    // Adjacent pairs matching prototype: (0,1), (1,2), ..., (N-1,0)
    let pairs = (0..<active.count).map { i in
      (active[i], active[(i + 1) % active.count])
    }

    for (persona1, persona2) in pairs {
      var action1 = ""
      var action2 = ""

      // Agent 1 chooses
      let output1 = try await callForAgent(
        persona: persona1, opponent: persona2,
        scenario: scenario, phase: phase, state: state,
        llm: llm, emitter: emitter, promptTemplate: promptTemplate
      )
      action1 = validateAction(output1.action ?? "", options: options)
      state.lastOutputs[persona1.name] = output1

      // Agent 2 chooses
      let output2 = try await callForAgent(
        persona: persona2, opponent: persona1,
        scenario: scenario, phase: phase, state: state,
        llm: llm, emitter: emitter, promptTemplate: promptTemplate
      )
      action2 = validateAction(output2.action ?? "", options: options)
      state.lastOutputs[persona2.name] = output2

      state.pairings.append(
        Pairing(agent1: persona1.name, agent2: persona2.name, action1: action1, action2: action2)
      )

      emitter(
        .pairingResult(
          agent1: persona1.name, action1: action1,
          agent2: persona2.name, action2: action2
        ))
    }
  }

  private func callForAgent(
    persona: Persona,
    opponent: Persona,
    scenario: Scenario,
    phase: Phase,
    state: SimulationState,
    llm: LLMService,
    emitter: @Sendable (SimulationEvent) -> Void,
    promptTemplate: String
  ) async throws -> TurnOutput {
    let systemPrompt = promptBuilder.buildSystemPrompt(
      scenario: scenario, persona: persona, phase: phase, state: state
    )

    var variables = state.variables
    variables["opponent_name"] = opponent.name
    variables["scoreboard"] = formatScoreboard(state.scores)
    variables["conversation_log"] = promptBuilder.formatConversationLog(state.conversationLog)
    let userPrompt = promptBuilder.expandTemplate(promptTemplate, variables: variables)

    let output = try await llmCaller.call(
      llm: llm, system: systemPrompt, user: userPrompt,
      agentName: persona.name, emitter: emitter
    )
    emitter(.agentOutput(agent: persona.name, output: output, phaseType: phase.type))
    return output
  }

  // MARK: - Individual

  private func executeIndividual(
    scenario: Scenario,
    phase: Phase,
    state: inout SimulationState,
    llm: LLMService,
    emitter: @Sendable (SimulationEvent) -> Void,
    promptTemplate: String,
    options: [String]
  ) async throws {
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

      state.lastOutputs[persona.name] = output
    }
  }

  // MARK: - Helpers

  /// Falls back to first option if action is not in the valid options list.
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
