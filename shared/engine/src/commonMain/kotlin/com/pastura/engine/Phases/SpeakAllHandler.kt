package com.pastura.engine

import com.pastura.models.ConversationEntry
import com.pastura.models.OutputSchema
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState

/**
 * Handles `speak_all` phases, where every active agent speaks simultaneously.
 *
 * Each non-eliminated agent generates output via the LLM. Outputs are appended to
 * the conversation log and stored in `lastOutputs` for subsequent phases.
 *
 * A turn-degradable LLM failure is routed through [PhaseContext.turnGate]
 * (ADR-021 D1/D2): the failing agent's turn is *skipped* — no `AgentOutput`, no
 * conversation-log entry, and any stale `lastOutputs` entry for that agent is
 * cleared — while the remaining agents still speak. Systemic errors, cancellation,
 * and the D4 circuit breaker propagate and abort the run (see [TurnFailureGate]).
 *
 * ## Prompt-injection parity (Wave B)
 *
 * The reserved-namespace `inject*` family (assigned / notes / whispers /
 * relationships / mood) and [PromptBuilder.captureMood] ARE now wired here — this
 * handler is the first consumer of the Wave-B injection infrastructure. It calls
 * all five injectors on the local prompt map (a miss resolves to `""`, so a scenario
 * whose producer phases never ran is unaffected) and folds `captureMood` into its
 * success-path state, a no-op unless the phase declares a `mood` output field. The
 * `detector` / `logger` seams were wired earlier (B0b) — the handler threads them
 * from [PhaseContext] into [LLMCaller].
 *
 * Swift original: `Pastura/Pastura/Engine/Phases/SpeakAllHandler.swift`.
 */
internal class SpeakAllHandler : PhaseHandler {

    private val promptBuilder = PromptBuilder()

    override suspend fun execute(context: PhaseContext, state: SimulationState): SimulationState {
        val promptTemplate = context.phase.prompt
            ?: pickLanguage(
                context.scenario.engineLanguage,
                ja = "あなたの意見を述べてください。",
                en = "Share your opinion.",
            )

        var current = state
        for (persona in context.scenario.personas) {
            // `== true` to SKIP: an agent absent from the map reads `null`, which
            // is not `true`, so it speaks — matching Swift's
            // `guard state.eliminated[persona.name] != true else { continue }`.
            // `!= false` would wrongly skip every agent the map never mentioned.
            if (current.eliminated[persona.name] == true) continue
            current = speakTurn(context, persona, promptTemplate, current)
        }
        return current
    }

    /**
     * Run one persona's turn: build the prompt, route the LLM call through
     * [PhaseContext.turnGate] (ADR-021 D1/D2), and fold the result into state on
     * success. On a skipped turn, write nothing and clear any stale `lastOutputs`
     * entry for the agent.
     *
     * Returns the next state — Kotlin [SimulationState] is immutable, so unlike
     * Swift's `inout` the caller MUST use the return value (see [PhaseHandler]).
     */
    private suspend fun speakTurn(
        context: PhaseContext,
        persona: com.pastura.models.Persona,
        promptTemplate: String,
        state: SimulationState,
    ): SimulationState {
        // Constructed per turn, matching Swift — a stateless value, cheap. The
        // logger seam is threaded from the context (Noop by default in the current
        // run path — see PhaseContext § "Knowingly absent").
        val llmCaller = LLMCaller(logger = context.logger)

        val systemPrompt = promptBuilder.buildSystemPrompt(
            scenario = context.scenario,
            persona = persona,
            phase = context.phase,
            state = state,
        )

        // Local prompt-variable map (thrown away after the prompt is built). The
        // `inject*` family mutates it in place to surface each reserved-namespace
        // `{token}` to only this speaker; none of this touches persisted state.
        val variables = state.variables.toMutableMap()
        variables["scoreboard"] = promptBuilder.formatScoreboard(state.scores)
        variables["conversation_log"] = promptBuilder.formatConversationLog(
            entries = state.conversationLog,
            language = context.scenario.engineLanguage,
            window = context.scenario.logWindow,
        )
        promptBuilder.injectAssigned(variables, persona.name)
        promptBuilder.injectNotes(variables, persona.name)
        promptBuilder.injectWhispers(variables, persona.name)
        promptBuilder.injectRelationships(variables, persona.name)
        promptBuilder.injectMood(variables, persona.name)
        val userPrompt = promptBuilder.expandTemplate(promptTemplate, variables)

        val output = context.turnGate.attempt(
            agent = persona.name,
            phaseType = context.phase.type,
            emitter = context.emitter,
        ) {
            llmCaller.call(
                backend = context.backend,
                system = systemPrompt,
                user = userPrompt,
                agentName = persona.name,
                schema = OutputSchema.from(context.phase),
                detector = context.detector,
                expectedLanguage = context.scenario.engineLanguage,
                relay = context.suspensionRelay,
                emitter = context.emitter,
            )
        } ?: return state.copy(
            // Turn skipped (ADR-021 D2): write nothing, and clear any stale
            // prior-round output so downstream consumers keyed on `lastOutputs`
            // don't read a decision that never happened this turn. Matches Swift's
            // `state.lastOutputs[persona.name] = nil` on the skip path.
            lastOutputs = state.lastOutputs - persona.name,
        )

        context.emitter(
            SimulationEvent.AgentOutput(
                agent = persona.name,
                output = output,
                phaseType = context.phase.type,
            ),
        )

        val mainField = promptBuilder.getMainField(context.phase)
        val content = output.fields[mainField] ?: ""
        // captureMood (#913) folds into the PERSISTED `state.variables` (a fresh
        // copy), NOT the local prompt map above — and only here on the success
        // path, never on the skip-path copy. Mirrors Swift's
        // `captureMood(from: output, into: &state.variables, ...)` after the
        // conversation-log / lastOutputs writes.
        val nextVariables = state.variables.toMutableMap()
        promptBuilder.captureMood(output, nextVariables, persona.name)
        return state.copy(
            variables = nextVariables,
            conversationLog = state.conversationLog + ConversationEntry(
                agentName = persona.name,
                content = content,
                phaseType = context.phase.type,
                round = state.currentRound,
            ),
            lastOutputs = state.lastOutputs + (persona.name to output),
        )
    }
}
