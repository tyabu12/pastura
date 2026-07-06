import Foundation

/// Handles `whisper` phases: a secret pairwise exchange between two agents.
///
/// Active (non-eliminated) agents are paired off in persona declaration order,
/// rotated by round so the pairings vary. Each pair runs `subRounds` exchanges;
/// an exchange is agent1 speaking then agent2 speaking. Every utterance reuses
/// the `.agentOutput` event with a reserved `whisper_to` field naming the
/// partner, so the whisper surfaces in the viewer UI / persistence exactly like
/// any other LLM output.
///
/// Whisper content is **pair-private**: it is never appended to
/// `conversationLog` or `lastOutputs`, so other agents' prompts can't see it
/// (mirroring ``ReflectHandler``'s private note). At the end of the phase each
/// participant's formatted view of their pair's exchange is written to the
/// reserved `whispers_<name>` key (overwrite semantics — latest exchange only,
/// per the #908 plan). An active agent who sat out an odd-count round has their stale
/// `whispers_<name>` cleared so a later reader never sees a whisper from a round
/// they didn't participate in; eliminated agents' keys are left untouched (they
/// are simply not participants this round).
nonisolated struct WhisperHandler: PhaseHandler {
  private let promptBuilder = PromptBuilder()
  private let llmCaller = LLMCaller()

  /// Per-execution invariants bundled to keep the LLM-call helpers under
  /// SwiftLint's `function_parameter_count`. `state` is a phase-start snapshot:
  /// whisper reads it for prompt building but never mutates the public log /
  /// outputs / scores during the phase, so the copy stays accurate.
  nonisolated private struct Run {
    let context: PhaseContext
    let state: SimulationState
    let promptTemplate: String
  }

  func execute(
    context: PhaseContext,
    state: inout SimulationState
  ) async throws {
    let active = context.scenario.personas.filter { state.eliminated[$0.name] != true }
    // Fewer than two active agents → nothing to pair. Return without any LLM
    // call or state write; in particular, do NOT clear anyone's channel here.
    guard active.count >= 2 else { return }

    let rotated = Self.rotate(active, by: state.currentRound)
    let promptTemplate =
      context.phase.prompt
      ?? pickLanguage(
        context.scenario.engineLanguage,
        ja: "相手にこっそり耳打ちしてください。",
        en: "Whisper privately to your partner.")
    let run = Run(context: context, state: state, promptTemplate: promptTemplate)
    let exchanges = max(1, context.phase.subRounds ?? 1)
    let language = context.scenario.engineLanguage

    var pairIndex = 0
    while pairIndex + 1 < rotated.count {
      let (first, second) = (rotated[pairIndex], rotated[pairIndex + 1])
      let transcript = try await runPair(first, second, exchanges: exchanges, run: run)
      // Both members see the same exchange body, each headed by their own
      // partner-identifying line.
      state.variables["whispers_\(first.name)"] =
        formatChannel(transcript, partner: second, language: language)
      state.variables["whispers_\(second.name)"] =
        formatChannel(transcript, partner: first, language: language)
      pairIndex += 2
    }

    // Odd active count: the last rotated element sat this round out. Clear its
    // stale channel for D4 "latest only" consistency.
    if rotated.count % 2 == 1, let satOut = rotated.last {
      state.variables.removeValue(forKey: "whispers_\(satOut.name)")
    }
  }

  // MARK: - Pairing

  /// Rotates the active list by `(round - 1)` positions so consecutive rounds
  /// draw different adjacent pairs. The modulo is normalized non-negative to
  /// tolerate a `round` of `0`.
  private static func rotate(_ agents: [Persona], by round: Int) -> [Persona] {
    let count = agents.count
    let offset = ((round - 1) % count + count) % count
    return Array(agents[offset...] + agents[..<offset])
  }

  /// Runs `exchanges` back-and-forth turns for one pair, accumulating the
  /// running transcript so each speaker's prompt can reference what was said
  /// so far via `{whisper_exchange}`.
  private func runPair(
    _ first: Persona, _ second: Persona, exchanges: Int, run: Run
  ) async throws -> [Utterance] {
    var transcript: [Utterance] = []
    for _ in 0..<exchanges {
      let out1 = try await whisperTurn(
        speaker: first, partner: second, transcript: transcript, run: run)
      transcript.append(Utterance(name: first.name, statement: out1.statement ?? ""))
      let out2 = try await whisperTurn(
        speaker: second, partner: first, transcript: transcript, run: run)
      transcript.append(Utterance(name: second.name, statement: out2.statement ?? ""))
    }
    return transcript
  }

  // MARK: - Single Turn

  private func whisperTurn(
    speaker: Persona, partner: Persona, transcript: [Utterance], run: Run
  ) async throws -> TurnOutput {
    let context = run.context
    let state = run.state
    let language = context.scenario.engineLanguage

    let systemPrompt = promptBuilder.buildSystemPrompt(
      scenario: context.scenario, persona: speaker, phase: context.phase, state: state)

    var variables = state.variables
    variables["scoreboard"] = promptBuilder.formatScoreboard(state.scores)
    // The PUBLIC conversation log — whisper participants still see it.
    variables["conversation_log"] = promptBuilder.formatConversationLog(
      state.conversationLog, language: language, window: context.scenario.logWindow)
    variables["whisper_partner"] = partner.name
    variables["whisper_exchange"] = formatTranscript(transcript)
    promptBuilder.injectAssigned(into: &variables, personaName: speaker.name)
    promptBuilder.injectNotes(into: &variables, personaName: speaker.name)
    promptBuilder.injectWhispers(into: &variables, personaName: speaker.name)
    // ALWAYS append a partner-naming context block after expanding the user
    // template: the default template never names the partner, and a custom
    // author prompt may omit `{whisper_partner}` / `{whisper_exchange}`. The
    // template still keeps those placeholders resolvable for authors who DO
    // reference them; this block guarantees the partner + running exchange
    // reach the model regardless of template content.
    let userPrompt =
      promptBuilder.expandTemplate(run.promptTemplate, variables: variables)
      + whisperContextBlock(partner: partner, transcript: transcript, language: language)

    let output = try await llmCaller.call(
      llm: context.llm, system: systemPrompt, user: userPrompt,
      agentName: speaker.name,
      schema: OutputSchema.from(phase: context.phase),
      detector: context.detector,
      expectedLanguage: context.scenario.engineLanguage,
      suspendController: context.suspendController,
      emitter: context.emitter
    )

    // Attribute the partner via the reserved `whisper_to` field, preserving the
    // original `rawText` provenance per the design contract.
    var merged = output.fields
    merged["whisper_to"] = partner.name
    let attributed = TurnOutput(fields: merged, rawText: output.rawText)
    context.emitter(
      .agentOutput(agent: speaker.name, output: attributed, phaseType: context.phase.type))
    // NOT appended to `conversationLog` and NOT written to `lastOutputs`: a
    // whisper is pair-private and must never reach another agent's prompt or
    // the public last-output display (mirrors ``ReflectHandler``).
    return attributed
  }

  // MARK: - Formatting

  /// A single whisper line, `name` + spoken `statement`.
  nonisolated private struct Utterance {
    let name: String
    let statement: String
  }

  /// Formats the exchange body one utterance per line, mirroring
  /// ``PromptBuilder/formatConversationLog(_:language:window:)``'s `  Name:
  /// content` style.
  private func formatTranscript(_ transcript: [Utterance]) -> String {
    transcript.map { "  \($0.name): \($0.statement)" }.joined(separator: "\n")
  }

  /// A language-aware block appended to every whisper turn prompt so the model
  /// always knows who its partner is — and, once the pair has spoken, what was
  /// said so far — no matter what the (possibly partner-agnostic) user template
  /// contains. The exchange section is omitted on the opening utterance (empty
  /// transcript) to avoid an empty header.
  private func whisperContextBlock(
    partner: Persona, transcript: [Utterance], language: String
  ) -> String {
    let partnerLine = pickLanguage(
      language,
      ja: "\n\n密談相手: \(partner.name)（この相手だけにこっそり話しかけてください）",
      en: "\n\nWhisper partner: \(partner.name) (speak privately to them only).")
    guard !transcript.isEmpty else { return partnerLine }
    let exchangeHeader = pickLanguage(language, ja: "これまでの密談:", en: "Whisper so far:")
    return "\(partnerLine)\n\(exchangeHeader)\n\(formatTranscript(transcript))"
  }

  /// A participant's stored channel view: a partner-identifying header line
  /// followed by the full exchange body.
  private func formatChannel(
    _ transcript: [Utterance], partner: Persona, language: String
  ) -> String {
    let header = pickLanguage(
      language,
      ja: "密談相手: \(partner.name)",
      en: "Whispering with \(partner.name)")
    let body = formatTranscript(transcript)
    return body.isEmpty ? header : "\(header)\n\(body)"
  }
}
