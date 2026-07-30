package com.pastura.engine

import com.pastura.models.OutputSchema
import com.pastura.models.Scenario
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState

/**
 * Handles `narrate` phases (#909): a single commentator inference per round.
 *
 * Unlike the per-agent LLM handlers, `narrate` makes **one** LLM call per round —
 * a commentator persona narrates the round's highlight. The narrator is **not** a
 * participant: it is not in `scenario.personas`, so it never votes, scores, or
 * appears on the scoreboard, and its output is never written to `conversationLog`
 * or `lastOutputs` (so other agents never see it).
 *
 * ## Grounding & degradation
 *
 * - **Empty-log skip.** If nothing has happened this round (`state.conversationLog`
 *   empty — e.g. `narrate` placed first, or round 1 before any speak phase), the
 *   handler emits nothing rather than inviting the model to invent commentary about
 *   an empty round (the hallucination edge; #909 critic Axis 11).
 * - **Degrade by omission, no circuit breaker.** A failed / empty inference simply
 *   emits no `Narration`; the round proceeds without commentary. The narrator is not
 *   an agent, so it deliberately bypasses the agent-attributed [TurnFailureGate] — a
 *   narrator failure must not emit `TurnSkipped` nor feed the ADR-021
 *   consecutive-skip circuit breaker (#909 critic Axis 4).
 *
 * ## Output & display
 *
 * The commentary is emitted RAW via [SimulationEvent.Narration]; `ContentFilter` is
 * applied at the App/UI boundary (ADR-005 — the filter runs between Engine output
 * and display, never inside the Engine). The output schema is Engine-fixed
 * (`{ commentary }`), not author-declared, so a `narrate` phase needs no `output:`
 * block — authors tune only the optional `narrator:` voice, `prompt:`, and
 * `max_sentences:`.
 *
 * ## Divergences from every other ported LLM handler — all deliberate
 *
 * A port that mirrors [ReflectHandler] (the nearest structural sibling: single-field
 * engine schema, private output, no log write) would be **green and wrong**. This
 * handler must NOT call `buildSystemPrompt`, any `inject*` helper, `captureMood`, or
 * `state.copy(...)`; `ReflectHandler` calls all four and none of them would fail the
 * build here.
 *
 * - **No [PhaseContext.turnGate].** The `try/catch` below replaces it (see § Grounding).
 * - **The catch is narrower than Swift's bare `catch` — see [execute].**
 * - **`emitter = {}` into [LLMCaller]**, suppressing the agent-attributed events.
 * - **Never copies state.** `execute` returns its input `state` on all four exits;
 *   narrate is the only handler in either engine that persists nothing at all.
 *
 * Swift original: `Pastura/Pastura/Engine/Phases/NarrateHandler.swift`.
 * Ported for the ADR-023 KMP Engine migration (#501, #1330).
 */
internal class NarrateHandler : PhaseHandler {

    private val promptBuilder = PromptBuilder()

    private companion object {
        /** OSLog category for narrate diagnostics. */
        const val LOG_CATEGORY = "NarrateHandler"

        /**
         * Reserved event-attribution name for the narrator's inference. Used only
         * for the suppressed [LLMCaller] progress events (see [execute]); it never
         * reaches the UI because those events are dropped.
         */
        const val NARRATOR_AGENT_NAME = "narrator"

        /**
         * Default brevity cap when a phase does not set `max_sentences:` (#909 —
         * the narrator's runaway is the second-largest risk after hallucination).
         *
         * Deliberately narrate's OWN constant rather than
         * `PromptBuilder.DEFAULT_STATEMENT_MAX_SENTENCES`: the two defaults are
         * independent knobs, and sharing one would make the narrator's brevity
         * silently track the statement default.
         */
        const val DEFAULT_MAX_SENTENCES = 3
    }

    override suspend fun execute(context: PhaseContext, state: SimulationState): SimulationState {
        // Empty-log guard: no grounded facts to narrate → skip rather than invent.
        if (state.conversationLog.isEmpty()) {
            context.logger.log(
                level = EngineLogLevel.DEBUG,
                category = LOG_CATEGORY,
                message = "narrate: empty conversation log — skipping commentary",
                privacy = EngineLogPrivacy.PUBLIC,
            )
            return state
        }

        val language = context.scenario.engineLanguage
        // coerceIn: another site inheriting a Swift validator guarantee that does not
        // exist on this side yet. `ScenarioValidator.validateMaxSentences` enforces
        // `max_sentences` in 1..6 and is called UNCONDITIONALLY from the
        // `validatePhases` traversal (`ScenarioValidator.swift:111`, and `:216` for
        // conditional-branch sub-phases), so it covers narrate and Swift's accepted
        // domain is `{null} ∪ [1,6]` — which is why the Swift original needs no clamp.
        // That validator is a Stage-3 port, so nothing rejects `max_sentences: 0` here,
        // and un-clamped it renders "0文以内" / "at most 0 sentence(s)" — an
        // unsatisfiable instruction handed to the model. Same class as the clamp in
        // `PromptBuilder.buildAnswerRules` and the `log_window: 0` guard in
        // `formatConversationLog`.
        val maxSentences = (context.phase.maxSentences ?: DEFAULT_MAX_SENTENCES).coerceIn(1, 6)

        val systemPrompt = buildNarratorSystemPrompt(
            scenario = context.scenario,
            narrator = context.phase.narrator,
            maxSentences = maxSentences,
            language = language,
        )
        val userPrompt = buildNarratorUserPrompt(context = context, state = state, language = language)

        // Engine-fixed single-field schema (mirrors reflect's `{ note }`); a free
        // string, so the grammar constrains structure only — no value enumeration
        // (the llama.cpp accept-time crash class, see .claude/rules/engine.md).
        val schema = OutputSchema(
            fields = listOf(
                OutputSchema.Field(name = "commentary", kind = OutputSchema.Kind.StringKind),
            ),
        )

        val llmCaller = LLMCaller(logger = context.logger)
        val commentary: String
        try {
            val output = llmCaller.call(
                backend = context.backend,
                system = systemPrompt,
                user = userPrompt,
                agentName = NARRATOR_AGENT_NAME,
                schema = schema,
                detector = context.detector,
                expectedLanguage = language,
                relay = context.suspensionRelay,
                // Suppress the narrator's per-token streaming + inference-progress
                // events so the commentator never renders as a participant agent row;
                // only the final `Narration` (below) surfaces. `LLMCaller` routes every
                // agent-attributed event through this parameter, so a no-op sink drops
                // them completely. EVENTS only — the `StreamingDiag` diagnostics still
                // reach `context.logger`, exactly as in Swift.
                emitter = {},
            )
            commentary = output.fields["commentary"] ?: ""
        } catch (e: SimulationException) {
            // Degrade by omission (see type doc): no `Narration`, no `TurnSkipped`, no
            // breaker increment. `.debug`-level so no user content is logged.
            //
            // Deliberately NARROWER than Swift's bare `catch`, and the difference is
            // load-bearing rather than cosmetic. Kotlin cancellation is a *throw*, so a
            // broad `catch (e: Throwable)` here would swallow the user's cancel and let
            // the run continue to the next suspension point; Swift's bare `catch` is safe
            // only because its runner polls `Task.isCancelled`. Every other LLM handler
            // gets this rethrow for free from `TurnFailureGate.attempt`, which catches
            // `Throwable` but re-throws anything non-degradable — see
            // `TurnFailureGate.kt` § `isTurnDegradable`. narrate has no gate, so it owes
            // the discipline itself. `SimulationException` is precisely the class
            // `LLMCaller` throws for every failure mode it models, so this catches
            // everything Swift's bare `catch` does except cancellation.
            context.logger.log(
                level = EngineLogLevel.DEBUG,
                category = LOG_CATEGORY,
                message = "narrate: inference failed — skipping commentary",
                privacy = EngineLogPrivacy.PUBLIC,
            )
            return state
        }

        // **Defensive parity, not a reachable path here.** Kotlin's
        // `JSONResponseParser` applies `hasAllExpectedKeys` on every successful parse
        // when the schema declares keys, and narrate always declares `{ commentary }`,
        // so `{"commentary": ""}` throws `JsonParseFailed` on each attempt and arrives
        // as `RetriesExhausted` at the catch above — never here as `commentary == ""`.
        // Swift's parser returns the empty output instead, so there the guard IS the
        // live path. Kept to mirror the Swift handler verbatim and to stay correct if
        // that upstream divergence is ever reconciled (same posture as
        // `ReflectHandler`'s `note.isNotEmpty()` guard).
        if (commentary.isEmpty()) {
            context.logger.log(
                level = EngineLogLevel.DEBUG,
                category = LOG_CATEGORY,
                message = "narrate: empty commentary — skipping emission",
                privacy = EngineLogPrivacy.PUBLIC,
            )
            return state
        }

        // Emit RAW — ContentFilter runs at the App/UI boundary (ADR-005). NOT written
        // to conversationLog / lastOutputs: the narrator is not a participant, so
        // agents' prompts must never include the commentary. Nothing is persisted at
        // all, hence the bare `state` rather than a `state.copy(...)`.
        context.emitter(SimulationEvent.Narration(text = commentary))
        return state
    }

    /**
     * Builds the Engine-owned commentator system prompt. The factuality and brevity
     * guardrails are fixed here (not author-overridable); the optional `narrator:`
     * descriptor is injected to shape the commentator's *voice* only.
     *
     * Deliberately NOT [PromptBuilder.buildSystemPrompt]: the narrator has no
     * [com.pastura.models.Persona], no private reserved-namespace sections, and no
     * answer rules — so all five literal pairs below are narrate's own and exist
     * nowhere in `PromptBuilder`.
     */
    private fun buildNarratorSystemPrompt(
        scenario: Scenario,
        narrator: String?,
        maxSentences: Int,
        language: String,
    ): String {
        val sections = mutableListOf<String>()

        val context = scenario.context.trim()
        if (context.isNotEmpty()) {
            sections += pickLanguage(language, ja = "設定: $context", en = "Setting: $context")
        }

        // Role + factuality guardrail (Engine-owned).
        sections += pickLanguage(
            language,
            ja = "あなたはこのシミュレーションの実況者です。会話ログに実際に書かれた出来事だけを根拠に、このラウンドの見どころを実況してください。ログに無い発言・出来事・結果を創作してはいけません。",
            en = "You are the live commentator for this simulation. Narrate the highlight of this round, grounded ONLY in what actually appears in the conversation log. Never invent lines, events, or outcomes that are not in the log.",
        )

        // Optional author-supplied voice descriptor (shapes voice, not the rules).
        val trimmedNarrator = (narrator ?: "").trim()
        if (trimmedNarrator.isNotEmpty()) {
            sections += pickLanguage(
                language,
                ja = "実況者のキャラクター: $trimmedNarrator",
                en = "Commentator persona: $trimmedNarrator",
            )
        }

        // Brevity guardrail (Engine-owned).
        sections += pickLanguage(
            language,
            ja = "${maxSentences}文以内で、簡潔に述べてください。",
            en = "Keep it concise — at most $maxSentences sentence(s).",
        )

        // Output format.
        sections += pickLanguage(
            language,
            ja = "出力は次の形の1行 JSON のみ: {\"commentary\": \"...\"}",
            en = "Output only single-line JSON of the form: {\"commentary\": \"...\"}",
        )

        return sections.joinToString("\n\n")
    }

    /**
     * Builds the user prompt from the phase's `prompt:` (or a default) with the recent
     * conversation log injected — the narrator's factual grounding.
     *
     * The variable map is local and thrown away after expansion. No `inject*` helper
     * runs: those surface per-persona reserved namespaces to a speaker, and the
     * narrator is not one.
     */
    private fun buildNarratorUserPrompt(
        context: PhaseContext,
        state: SimulationState,
        language: String,
    ): String {
        val promptTemplate = context.phase.prompt
            ?: pickLanguage(
                language,
                ja = "直近のやり取り:\n{conversation_log}\n\nこのラウンドの見どころを実況してください。",
                en = "Recent exchanges:\n{conversation_log}\n\nNarrate the highlight of this round.",
            )

        val variables = state.variables.toMutableMap()
        variables["conversation_log"] = promptBuilder.formatConversationLog(
            entries = state.conversationLog,
            language = language,
            window = context.scenario.logWindow,
        )
        variables["scoreboard"] = promptBuilder.formatScoreboard(state.scores)
        return promptBuilder.expandTemplate(promptTemplate, variables)
    }
}
