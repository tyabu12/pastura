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
      let userPrompt = promptBuilder.expandTemplate(promptTemplate, variables: variables)

      let output = try await llmCaller.call(
        llm: context.llm, system: systemPrompt, user: userPrompt,
        agentName: persona.name,
        schema: voteSchema(phase: context.phase, candidates: candidates),
        detector: context.detector,
        expectedLanguage: context.scenario.engineLanguage,
        suspendController: context.suspendController,
        emitter: context.emitter
      )

      context.emitter(
        .agentOutput(agent: persona.name, output: output, phaseType: context.phase.type))

      let votedFor = output.vote ?? ""
      votes[persona.name] = votedFor
      // Accept any vote target dynamically (prototype behavior)
      tallies[votedFor, default: 0] += 1

      state.lastOutputs[persona.name] = output
    }

    state.voteResults = tallies
    // Key matches {vote_results} placeholder documented in PhaseEditorSheet
    // and used by the word_wolf preset's summarize template.
    state.variables["vote_results"] = promptBuilder.formatScoreboard(tallies)

    context.emitter(.voteResults(votes: votes, tallies: tallies))
  }

  /// Build the per-voter `OutputSchema`, constraining the `vote` field to the
  /// voter's candidate list at the grammar level when every candidate is
  /// GBNF-safe and the list is non-empty.
  ///
  /// This is the on-device prevention layer: a grammar enumeration makes a
  /// self-vote (under `exclude_self`) or a vote for an eliminated agent
  /// structurally unreachable on backends that honor the schema (#524). The
  /// runtime drop in `execute(...)` remains the correctness floor for
  /// backends that don't constrain (Mock / Ollama) or grammar bypass.
  ///
  /// Falls back to the unconstrained `OutputSchema.from(phase:)` when the
  /// candidate list is empty or any candidate contains a GBNF-hostile
  /// character — emitting an `.enumeration` there would throw
  /// `BuilderError.invalidEnumerationOption`, which propagates as a
  /// non-retried `llmGenerationFailed` and aborts the run (worse than the
  /// bug). Candidate values are persona names (arbitrary user / factory
  /// input), so this guard is load-bearing; `choose`'s author-curated
  /// `options` never hit it.
  private func voteSchema(phase: Phase, candidates: [String]) -> OutputSchema? {
    guard let base = OutputSchema.from(phase: phase) else { return nil }
    guard !candidates.isEmpty,
      candidates.allSatisfy(GBNFGrammarBuilder.isSafeEnumerationOption)
    else { return base }
    let fields = base.fields.map { field in
      field.name == "vote"
        ? OutputSchema.Field(name: field.name, kind: .enumeration(candidates))
        : field
    }
    return OutputSchema(fields: fields)
  }
}
