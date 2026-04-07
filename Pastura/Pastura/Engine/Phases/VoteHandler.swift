import Foundation

/// Handles `vote` phases where all agents vote for one agent.
///
/// Collects votes, tallies results, updates `state.voteResults`, and emits
/// a `voteResults` event. Invalid vote targets are accepted dynamically
/// (following prototype behavior).
nonisolated struct VoteHandler: PhaseHandler {
  private let promptBuilder = PromptBuilder()
  private let llmCaller = LLMCaller()

  func execute(
    scenario: Scenario,
    phase: Phase,
    state: inout SimulationState,
    llm: LLMService,
    emitter: @Sendable (SimulationEvent) -> Void
  ) async throws {
    let promptTemplate = phase.prompt ?? "最も怪しいと思う人に投票してください。"
    let excludeSelf = phase.excludeSelf ?? true

    var votes: [String: String] = [:]  // voter -> target
    var tallies: [String: Int] = [:]

    for persona in scenario.personas {
      guard state.eliminated[persona.name] != true else { continue }

      let systemPrompt = promptBuilder.buildSystemPrompt(
        scenario: scenario, persona: persona, phase: phase, state: state
      )

      let candidates = scenario.personas
        .map(\.name)
        .filter { name in
          if excludeSelf && name == persona.name { return false }
          if state.eliminated[name] == true { return false }
          return true
        }

      var variables = state.variables
      variables["scoreboard"] = formatScoreboard(state.scores)
      variables["conversation_log"] = promptBuilder.formatConversationLog(state.conversationLog)
      variables["candidates"] = candidates.joined(separator: ", ")
      let userPrompt = promptBuilder.expandTemplate(promptTemplate, variables: variables)

      let output = try await llmCaller.call(
        llm: llm, system: systemPrompt, user: userPrompt,
        agentName: persona.name, emitter: emitter
      )

      emitter(.agentOutput(agent: persona.name, output: output, phaseType: phase.type))

      let votedFor = output.vote ?? ""
      votes[persona.name] = votedFor
      // Accept any vote target dynamically (prototype behavior)
      tallies[votedFor, default: 0] += 1

      state.lastOutputs[persona.name] = output
    }

    state.voteResults = tallies
    state.variables["vote_result"] = formatScoreboard(tallies)

    emitter(.voteResults(votes: votes, tallies: tallies))
  }

  private func formatScoreboard(_ scores: [String: Int]) -> String {
    let pairs = scores.sorted { $0.key < $1.key }
      .map { "\"\($0.key)\": \($0.value)" }
    return "{\(pairs.joined(separator: ", "))}"
  }
}
