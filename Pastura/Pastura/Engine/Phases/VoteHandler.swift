import Foundation

/// Handles `vote` phases where all agents vote for one agent.
///
/// Collects votes, tallies results, updates `state.voteResults`, and emits
/// a `voteResults` event. A vote outside the voter's candidate list (self
/// under `exclude_self`, an eliminated agent, or a hallucinated name) is
/// dropped from the tally so it cannot distort scoring or elimination; the
/// raw value is still recorded in the per-voter `votes` map for
/// observability in the `voteResults` event (#524).
///
/// A turn-degradable LLM failure is routed through `context.turnGate`
/// (ADR-021 D1/D2) and treated as an **abstention**: no ballot is recorded
/// (neither the `votes` map nor the tally), no `.agentOutput` is emitted,
/// and the voter's stale `lastOutputs` entry is cleared so a decision that
/// never happened this turn can't leak into consumers keyed on it. The
/// remaining agents still vote.
nonisolated struct VoteHandler: PhaseHandler {
  private let promptBuilder = PromptBuilder()

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

      let candidates = voteCandidates(
        scenario: context.scenario, voter: persona, excludeSelf: excludeSelf, state: state)

      guard
        let output = try await voteTurn(
          context: context, persona: persona,
          promptTemplate: promptTemplate, candidates: candidates, state: &state)
      else { continue }  // abstention — gate already emitted .turnSkipped

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
    }

    state.voteResults = tallies
    // Key matches {vote_results} placeholder documented in PhaseEditorSheet
    // and used by the word_wolf preset's summarize template.
    state.variables["vote_results"] = promptBuilder.formatScoreboard(tallies)

    context.emitter(.voteResults(votes: votes, tallies: tallies))
  }

  /// Runs one voter's turn: builds the prompt, routes the LLM call through
  /// `context.turnGate` (ADR-021 D1/D2), and on success emits `.agentOutput`
  /// and records the ballot in `lastOutputs`. On a skipped turn, emits nothing,
  /// clears any stale `lastOutputs` entry, and returns `nil` (the caller records
  /// no ballot — an abstention). Split out of `execute` to stay under
  /// SwiftLint's `function_body_length`.
  private func voteTurn(
    context: PhaseContext,
    persona: Persona,
    promptTemplate: String,
    candidates: [String],
    state: inout SimulationState
  ) async throws -> TurnOutput? {
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
    variables["candidates"] = candidates.joined(separator: ", ")
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
      // Abstention (ADR-021 D2): clear any stale prior-round output so
      // downstream consumers keyed on `lastOutputs` don't silently read a
      // decision that never happened this turn.
      state.lastOutputs[persona.name] = nil
      return nil
    }

    context.emitter(
      .agentOutput(agent: persona.name, output: output, phaseType: context.phase.type))
    state.lastOutputs[persona.name] = output
    promptBuilder.captureMood(
      from: output, into: &state.variables, personaName: persona.name)
    return output
  }

  /// The valid vote targets for `voter`: all personas minus self (under
  /// `exclude_self`) and any eliminated agent. Extracted from `execute` to keep
  /// that method under the `function_body_length` cap.
  private func voteCandidates(
    scenario: Scenario, voter: Persona, excludeSelf: Bool, state: SimulationState
  ) -> [String] {
    scenario.personas
      .map(\.name)
      .filter { name in
        if excludeSelf && name == voter.name { return false }
        if state.eliminated[name] == true { return false }
        return true
      }
  }
}
