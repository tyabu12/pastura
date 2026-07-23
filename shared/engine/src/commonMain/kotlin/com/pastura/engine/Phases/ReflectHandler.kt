package com.pastura.engine

import com.pastura.models.OutputSchema
import com.pastura.models.Persona
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState

/**
 * Handles `reflect` phases, where each active agent privately updates a personal memo.
 *
 * Each non-eliminated agent makes one LLM call producing `{ note }` — a short
 * private memo (impressions, suspicions, plans). The note is stored under the
 * reserved per-persona key `notes_<name>` in [SimulationState.variables]
 * (mirroring the `assigned_<name>` namespace, see [PromptBuilder.injectNotes]) and
 * surfaced back to that agent — and only that agent — in every subsequent LLM
 * call's system prompt.
 *
 * Unlike the speak handlers, the note is **private**: it is never appended to
 * `conversationLog` (so other agents can't see it) and never written to
 * `lastOutputs` (so it doesn't replace the public last output). Only the
 * `AgentOutput` event is emitted, keeping the persistence / UI / replay flow
 * identical to the other LLM phases.
 *
 * A turn-degradable LLM failure is routed through [PhaseContext.turnGate]
 * (ADR-021 D1/D2): the failing agent's turn is skipped — no `AgentOutput` and no
 * `notes_<name>` write, so a prior round's memo survives (the same outcome as the
 * non-empty guard below; private memory persists). Reflect never touches
 * `lastOutputs`, so — unlike [SpeakAllHandler]'s skip path — there is nothing to
 * clear: the skip simply returns the state unchanged.
 *
 * Swift original: `Pastura/Pastura/Engine/Phases/ReflectHandler.swift`.
 */
internal class ReflectHandler : PhaseHandler {

    private val promptBuilder = PromptBuilder()

    override suspend fun execute(context: PhaseContext, state: SimulationState): SimulationState {
        val promptTemplate = context.phase.prompt
            ?: pickLanguage(
                context.scenario.engineLanguage,
                ja = "これまでの会話: {conversation_log}\n" +
                    "これまでの状況を踏まえ、所感・警戒・今後の方針を自分用のメモとして更新してください。",
                en = "Conversation so far: {conversation_log}\n" +
                    "Update your private notes: impressions, suspicions, and your plan going forward.",
            )

        var current = state
        for (persona in context.scenario.personas) {
            // `== true` to SKIP: an agent absent from the map reads `null`, which
            // is not `true`, so it reflects — matching Swift's
            // `guard state.eliminated[persona.name] != true else { continue }`.
            if (current.eliminated[persona.name] == true) continue
            current = reflectTurn(context, persona, promptTemplate, current)
        }
        return current
    }

    /**
     * Runs one persona's reflect turn: builds the prompt, routes the LLM call
     * through [PhaseContext.turnGate] (ADR-021 D1/D2), and on success emits
     * `AgentOutput` and persists a non-empty note. On a skipped turn, writes
     * nothing — the prior `notes_<name>` memo is left intact.
     *
     * Returns the next state — Kotlin [SimulationState] is immutable, so unlike
     * Swift's `inout` the caller MUST use the return value (see [PhaseHandler]).
     */
    private suspend fun reflectTurn(
        context: PhaseContext,
        persona: Persona,
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
        // `{token}` to only this reflector; none of this touches persisted state.
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
        }
        // Skipped (ADR-021 D2): a null return means the gate absorbed a
        // turn-degradable failure. No note write — the prior `notes_<name>` memo
        // persists; and nothing to clear (reflect never writes `lastOutputs`), so
        // the state is returned unchanged — the deliberate divergence from
        // SpeakAllHandler's skip path.
            ?: return state

        context.emitter(
            SimulationEvent.AgentOutput(
                agent = persona.name,
                output = output,
                phaseType = context.phase.type,
            ),
        )

        // Fold BOTH persisted writes into one `state.copy(variables = …)`:
        //  1. the memo under the reserved `notes_<name>` namespace, and
        //  2. captureMood (#913), a no-op unless this reflect phase declares a
        //     `mood` output field.
        // Both mutate the SAME fresh map before the single copy — Kotlin's
        // immutable state means a second `state.copy` off the original would drop
        // the first write (Swift threads two sequential `inout` mutations instead).
        //
        // The `note.isNotEmpty()` guard is **defensive parity** with Swift, not a
        // reachable path here: the parser rejects a present-but-empty expected key
        // (`hasAllExpectedKeys` requires non-empty content), so an all-empty
        // inference exhausts the retry budget and is absorbed as a turn skip
        // upstream (the `?: return state` arm above) rather than arriving here as
        // `note == ""`. Kept so the write stays correct if that upstream guarantee
        // ever changes — and to mirror the Swift handler verbatim.
        val nextVariables = state.variables.toMutableMap()
        val note = output.fields["note"] ?: ""
        if (note.isNotEmpty()) {
            nextVariables["notes_${persona.name}"] = note
        }
        promptBuilder.captureMood(output, nextVariables, persona.name)

        // Deliberately NOT appended to `conversationLog` (the note is private, so
        // other agents whose prompts include the log must never see it) and NOT
        // written to `lastOutputs` (the public last output must not be replaced by
        // a private memo).
        return state.copy(variables = nextVariables)
    }
}
