import Foundation

/// Handles `vote` phases where all agents vote for one agent.
///
/// Collects votes, tallies results, updates `state.voteResults`, and emits
/// a `voteResults` event. A vote outside the voter's candidate list (self
/// under `exclude_self`, an eliminated agent, or a hallucinated name) is
/// dropped from the tally so it cannot distort scoring or elimination; the
/// raw value is still recorded in the per-voter `votes` map for
/// observability in the `voteResults` event (#524).
nonisolated struct VoteHandler: PhaseHandler {
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
        ja: "最も怪しいと思う人に投票してください。",
        en: "Vote for the person you find most suspicious.")
    let excludeSelf = context.phase.excludeSelf ?? true

    var votes: [String: String] = [:]  // voter -> target
    var tallies: [String: Int] = [:]

    for persona in context.scenario.personas {
      guard state.eliminated[persona.name] != true else { continue }

      let systemPrompt = promptBuilder.buildSystemPrompt(
        scenario: context.scenario, persona: persona, phase: context.phase, state: state
      )

      let candidates = context.scenario.personas
        .map(\.name)
        .filter { name in
          if excludeSelf && name == persona.name { return false }
          if state.eliminated[name] == true { return false }
          return true
        }

      var variables = state.variables
      variables["scoreboard"] = promptBuilder.formatScoreboard(state.scores)
      variables["conversation_log"] = promptBuilder.formatConversationLog(
        state.conversationLog, language: context.scenario.engineLanguage)
      variables["candidates"] = candidates.joined(separator: ", ")
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

      let votedFor = output.vote ?? ""
      votes[persona.name] = votedFor
      // Tally only votes for a valid candidate. Out-of-candidate votes
      // (self under exclude_self, eliminated agents, or hallucinated names)
      // are dropped so they cannot distort scoring or elimination (#524).
      // The raw value stays in `votes` for observability in the
      // voteResults event.
      if candidates.contains(votedFor) {
        tallies[votedFor, default: 0] += 1
      }

      state.lastOutputs[persona.name] = output
    }

    state.voteResults = tallies
    // Key matches {vote_results} placeholder documented in PhaseEditorSheet
    // and used by the word_wolf preset's summarize template.
    state.variables["vote_results"] = promptBuilder.formatScoreboard(tallies)

    context.emitter(.voteResults(votes: votes, tallies: tallies))
  }
}
