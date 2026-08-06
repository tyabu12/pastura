import Foundation

/// Handles `narrate` phases (#909): a single commentator inference per round.
///
/// Unlike the per-agent LLM handlers, `narrate` makes **one** LLM call per
/// round — a commentator persona narrates the round's highlight. The narrator
/// is **not** a participant: it is not in `scenario.personas`, so it never
/// votes, scores, or appears on the scoreboard, and its output is never written
/// to `conversationLog` or `lastOutputs` (so other agents never see it).
///
/// ## Grounding & degradation
///
/// - **Empty-log skip.** If nothing has happened this round
///   (`state.conversationLog` empty — e.g. `narrate` placed first, or round 1
///   before any speak phase), the handler emits nothing rather than inviting
///   the model to invent commentary about an empty round (the hallucination
///   edge; #909 critic Axis 11).
/// - **Degrade by omission, no circuit breaker.** A failed / empty inference
///   simply emits no `.narration`; the round proceeds without commentary. The
///   narrator is not an agent, so it deliberately bypasses the agent-attributed
///   ``TurnFailureGate`` — a narrator failure must not emit `.turnSkipped` nor
///   feed the ADR-021 consecutive-skip circuit breaker (#909 critic Axis 4).
///
/// ## Output & display
///
/// The commentary is emitted RAW via ``SimulationEvent/narration(text:)``;
/// `ContentFilter` is applied at the App/UI boundary (ADR-005 — the filter runs
/// between Engine output and display, never inside the Engine). The output
/// schema is Engine-fixed (`{ commentary }`), not author-declared, so a
/// `narrate` phase needs no `output:` block — authors tune only the optional
/// `narrator:` voice, `prompt:`, and `max_sentences:`.
nonisolated struct NarrateHandler: PhaseHandler {
  private let promptBuilder = PromptBuilder()

  /// OSLog category for narrate diagnostics.
  static let logCategory = "NarrateHandler"

  /// Reserved event-attribution name for the narrator's inference. Used only
  /// for the suppressed `LLMCaller` progress events (see `execute`); it never
  /// reaches the UI because those events are dropped.
  private static let narratorAgentName = "narrator"

  /// Default brevity cap when a phase does not set `max_sentences:` (#909 —
  /// the narrator's runaway is the second-largest risk after hallucination).
  private static let defaultMaxSentences = 3

  func execute(
    context: PhaseContext,
    state: inout SimulationState
  ) async throws {
    // Empty-log guard: no grounded facts to narrate → skip rather than invent.
    guard !state.conversationLog.isEmpty else {
      context.logger.log(
        .debug, category: Self.logCategory,
        "narrate: empty conversation log — skipping commentary", privacy: .public)
      return
    }

    let language = context.scenario.engineLanguage
    let maxSentences = context.phase.maxSentences ?? Self.defaultMaxSentences

    let systemPrompt = buildNarratorSystemPrompt(
      scenario: context.scenario, narrator: context.phase.narrator,
      maxSentences: maxSentences, language: language)
    let userPrompt = buildNarratorUserPrompt(context: context, state: state, language: language)

    // Engine-fixed single-field schema (mirrors reflect's `{ note }`); a free
    // string, so the grammar constrains structure only — no value enumeration
    // (the llama.cpp accept-time crash class, see .claude/rules/engine.md).
    let schema = OutputSchema(fields: [OutputSchema.Field(name: "commentary", kind: .string)])

    let llmCaller = LLMCaller(logger: context.logger)
    let commentary: String
    do {
      let output = try await llmCaller.call(
        llm: context.llm, system: systemPrompt, user: userPrompt,
        agentName: Self.narratorAgentName,
        // `primaryField(for: .narrate)` is nil (engine-fixed `{ commentary }`
        // schema, not author-declared), so the ADR-021 Amendment 2026-08-06
        // skip rule cannot fire here. That is load-bearing: this is the one
        // LLM call site NOT wrapped in `turnGate.attempt`, so a throw would
        // abort the run rather than skip the turn.
        phaseType: context.phase.type,
        schema: schema,
        detector: context.detector,
        expectedLanguage: language,
        suspendController: context.suspendController,
        // Suppress the narrator's per-token streaming + inference-progress
        // events so the commentator never renders as a participant agent row;
        // only the final `.narration` (below) surfaces. `LLMCaller` emits only
        // these agent-attributed events, so a no-op sink drops them completely.
        emitter: { _ in })
      commentary = output.fields["commentary"] ?? ""
    } catch {
      // Degrade by omission (see type doc): no `.narration`, no `.turnSkipped`,
      // no breaker increment. `.debug`-level so no user content is logged.
      context.logger.log(
        .debug, category: Self.logCategory,
        "narrate: inference failed — skipping commentary", privacy: .public)
      return
    }

    guard !commentary.isEmpty else {
      context.logger.log(
        .debug, category: Self.logCategory,
        "narrate: empty commentary — skipping emission", privacy: .public)
      return
    }

    // Emit RAW — ContentFilter runs at the App/UI boundary (ADR-005). NOT
    // written to conversationLog / lastOutputs: the narrator is not a
    // participant, so agents' prompts must never include the commentary.
    context.emitter(.narration(text: commentary))
  }

  /// Builds the Engine-owned commentator system prompt. The factuality and
  /// brevity guardrails are fixed here (not author-overridable); the optional
  /// `narrator:` descriptor is injected to shape the commentator's *voice* only.
  private func buildNarratorSystemPrompt(
    scenario: Scenario, narrator: String?, maxSentences: Int, language: String
  ) -> String {
    var sections: [String] = []

    let context = scenario.context.trimmingCharacters(in: .whitespacesAndNewlines)
    if !context.isEmpty {
      sections.append(pickLanguage(language, ja: "設定: \(context)", en: "Setting: \(context)"))
    }

    // Role + factuality guardrail (Engine-owned).
    sections.append(
      pickLanguage(
        language,
        ja:
          "あなたはこのシミュレーションの実況者です。会話ログに実際に書かれた出来事だけを根拠に、このラウンドの見どころを実況してください。ログに無い発言・出来事・結果を創作してはいけません。",
        en:
          "You are the live commentator for this simulation. Narrate the highlight of this round, grounded ONLY in what actually appears in the conversation log. Never invent lines, events, or outcomes that are not in the log."
      ))

    // Optional author-supplied voice descriptor (shapes voice, not the rules).
    let trimmedNarrator = (narrator ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedNarrator.isEmpty {
      sections.append(
        pickLanguage(
          language,
          ja: "実況者のキャラクター: \(trimmedNarrator)",
          en: "Commentator persona: \(trimmedNarrator)"))
    }

    // Brevity guardrail (Engine-owned).
    sections.append(
      pickLanguage(
        language,
        ja: "\(maxSentences)文以内で、簡潔に述べてください。",
        en: "Keep it concise — at most \(maxSentences) sentence(s)."))

    // Output format.
    sections.append(
      pickLanguage(
        language,
        ja: "出力は次の形の1行 JSON のみ: {\"commentary\": \"...\"}",
        en: "Output only single-line JSON of the form: {\"commentary\": \"...\"}"))

    return sections.joined(separator: "\n\n")
  }

  /// Builds the user prompt from the phase's `prompt:` (or a default) with the
  /// recent conversation log injected — the narrator's factual grounding.
  private func buildNarratorUserPrompt(
    context: PhaseContext, state: SimulationState, language: String
  ) -> String {
    let promptTemplate =
      context.phase.prompt
      ?? pickLanguage(
        language,
        ja: "直近のやり取り:\n{conversation_log}\n\nこのラウンドの見どころを実況してください。",
        en: "Recent exchanges:\n{conversation_log}\n\nNarrate the highlight of this round.")

    var variables = state.variables
    variables["conversation_log"] = promptBuilder.formatConversationLog(
      state.conversationLog, language: language, window: context.scenario.logWindow)
    variables["scoreboard"] = promptBuilder.formatScoreboard(state.scores)
    return promptBuilder.expandTemplate(promptTemplate, variables: variables)
  }
}
