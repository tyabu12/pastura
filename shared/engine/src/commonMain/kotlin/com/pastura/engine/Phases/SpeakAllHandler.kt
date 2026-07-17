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
 * ## Scope: the ADR-023 §6 Stage-2 gate slice
 *
 * **`TurnFailureGate` (ADR-021) is deliberately absent** — a named deferral, not a
 * silent drop. Swift routes each per-agent call through `context.turnGate.attempt`
 * so a turn-degradable LLM failure *skips* that agent's turn and the remaining
 * agents still speak (D1/D2). Here a failure propagates and aborts the run.
 *
 * Why it stays out: the gate measures boundary ergonomics, and pulling ADR-021 in
 * would drag `turnSkipped` + `SimulationError.turnFailureLimitReached` onto the
 * slice path — neither exists in Kotlin `SimulationEvent` yet — for no measurement
 * benefit. Stage 3 restores it against `SpeakAllHandlerTests`, which ADR-023 §6
 * names as the executable spec.
 *
 * Also absent, per [PromptBuilder]'s absence table: the `inject*` family
 * (assigned / notes / whispers / relationships / mood) and `captureMood`, whose
 * producer phases are all Stage-3 freight.
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
            // `!= true` rather than `== false`: an agent absent from the map is
            // active, matching Swift's `state.eliminated[persona.name] != true`.
            if (current.eliminated[persona.name] == true) continue
            current = speakTurn(context, persona, promptTemplate, current)
        }
        return current
    }

    /**
     * Run one persona's turn: build the prompt, call the LLM, fold the result into
     * state.
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
        // Constructed per turn, matching Swift — a stateless value, cheap.
        val llmCaller = LLMCaller()

        val systemPrompt = promptBuilder.buildSystemPrompt(
            scenario = context.scenario,
            persona = persona,
            phase = context.phase,
            state = state,
        )

        val variables = state.variables.toMutableMap()
        variables["scoreboard"] = promptBuilder.formatScoreboard(state.scores)
        variables["conversation_log"] = promptBuilder.formatConversationLog(
            entries = state.conversationLog,
            language = context.scenario.engineLanguage,
            window = context.scenario.logWindow,
        )
        val userPrompt = promptBuilder.expandTemplate(promptTemplate, variables)

        val output = llmCaller.call(
            backend = context.backend,
            system = systemPrompt,
            user = userPrompt,
            agentName = persona.name,
            schema = OutputSchema.from(context.phase),
            relay = context.suspensionRelay,
            emitter = context.emitter,
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
        return state.copy(
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
