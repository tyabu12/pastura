package com.pastura.engine

import com.pastura.models.ConversationEntry
import com.pastura.models.OutputSchema
import com.pastura.models.Persona
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState

/**
 * Handles `speak_each` phases where agents speak sequentially with accumulating
 * context.
 *
 * Unlike `speak_all`, the conversation log accumulates *within* sub-rounds, so
 * each agent sees what previous agents said in the current sub-round.
 *
 * A turn-degradable LLM failure is routed through [PhaseContext.turnGate]
 * (ADR-021 D1/D2): the failing agent's turn is skipped — no `AgentOutput`, no
 * `conversationLog` entry, and any stale `lastOutputs` entry for that agent is
 * cleared — and the sub-round continues with the next persona.
 *
 * ## Sole seeder of the DRY anti-repetition sampler (#1105)
 *
 * This is the only handler in either engine that populates
 * [GenerationRequest.antiRepetitionSeeds]. It seeds each turn with **that
 * agent's own** most-recent statement, which is still in `lastOutputs` because
 * that key is overwritten only after the turn succeeds. Read
 * [GenerationRequest.antiRepetitionSeeds] before assuming this covers more than
 * it does — cross-*agent* template collapse and every other phase are not
 * reached by it.
 *
 * Because it is the sole producer, no consumer test can catch a dropped seed:
 * the backend takes whatever list it is handed and a `emptyList()` here is
 * indistinguishable from a phase that legitimately does not seed. That is why
 * `SpeakEachHandlerTests` asserts against the backend's recorded requests rather
 * than against [LLMCaller] in isolation.
 *
 * ## State threading (Kotlin immutability)
 *
 * Swift mutates an `inout state` per turn; Kotlin's [SimulationState] is
 * immutable, so [speakTurn] returns the next state and the loops thread it
 * through a single `current`. Threading — not a frozen phase-start snapshot as
 * in `WhisperHandler` — is what makes the accumulation above work: each turn
 * formats its `conversation_log` from the state the previous turn returned.
 *
 * Swift original: `Pastura/Pastura/Engine/Phases/SpeakEachHandler.swift`.
 */
internal class SpeakEachHandler : PhaseHandler {

    private val promptBuilder = PromptBuilder()

    override suspend fun execute(context: PhaseContext, state: SimulationState): SimulationState {
        // `subRounds` is untrusted (any un-vetted YAML ingest can set `rounds: 0`
        // or a negative). Swift clamps because `1...subRounds` would form an
        // invalid ClosedRange and TRAP; Kotlin's `1..0` is merely an EMPTY range,
        // so here the same missing clamp is a silent zero-inference phase instead
        // of a crash — quieter, and therefore worth guarding just as much.
        val subRounds = maxOf(1, context.phase.subRounds ?: 1)
        val promptTemplate = context.phase.prompt
            ?: pickLanguage(
                context.scenario.engineLanguage,
                ja = "これまでの会話: {conversation_log}\nあなたの番です。",
                en = "Conversation so far: {conversation_log}\nYour turn.",
            )

        var current = state
        repeat(subRounds) {
            for (persona in context.scenario.personas) {
                // `== true` to SKIP: an agent absent from the map reads `null`,
                // which is not `true`, so it speaks — matching Swift's
                // `guard state.eliminated[persona.name] != true else { continue }`.
                if (current.eliminated[persona.name] == true) continue
                current = speakTurn(context, persona, promptTemplate, current)
            }
        }
        return current
    }

    /**
     * Runs one persona's turn: builds the prompt, routes the LLM call through
     * [PhaseContext.turnGate] (ADR-021 D1/D2), and folds the result into state on
     * success. On a skipped turn, writes nothing and clears any stale
     * `lastOutputs` entry.
     *
     * Returns the next state — [SimulationState] is immutable, so unlike Swift's
     * `inout` the caller MUST use the return value (see [PhaseHandler]).
     */
    private suspend fun speakTurn(
        context: PhaseContext,
        persona: Persona,
        promptTemplate: String,
        state: SimulationState,
    ): SimulationState {
        // Constructed per turn, matching Swift — a stateless value, cheap. The
        // logger seam is threaded from the context.
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

        // Hoisted above the call because the seed reads the SAME field the
        // conversation-log entry below writes.
        val mainField = promptBuilder.getMainField(context.phase)
        // Anti-repetition seed (#1105): this agent's own most-recent statement,
        // still in `lastOutputs` because it is overwritten only after this turn
        // succeeds. Seeded into the DRY sampler (content-only, value text) so a
        // token-level penalty spans the turn boundary — the register-dominant
        // cross-round verbatim echo that prompt-side fixes could not suppress
        // (#912 No-Go). Empty only when the agent has NO prior statement under
        // this field at all — its first such turn of the run, or right after a D2
        // skip cleared the key. `lastOutputs` is not reset per round, so a later
        // round's first sub-round normally still seeds.
        //
        // `isNotBlank()` mirrors Swift's whitespace-trim filter: an empty or
        // `"..."` statement is already caught upstream by the empty-field retry,
        // but a blank-but-nonempty one (`"   "`) reaches `lastOutputs` and would
        // otherwise be seeded as a meaningless span.
        val antiRepetitionSeeds =
            listOfNotNull(state.lastOutputs[persona.name]?.fields?.get(mainField))
                .filter { it.isNotBlank() }

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
                phaseType = context.phase.type,
                schema = OutputSchema.from(context.phase),
                detector = context.detector,
                expectedLanguage = context.scenario.engineLanguage,
                antiRepetitionSeeds = antiRepetitionSeeds,
                relay = context.suspensionRelay,
                emitter = context.emitter,
            )
        } ?: return state.copy(
            // Turn skipped (ADR-021 D2): write nothing, and clear any stale
            // prior-round output so downstream consumers keyed on `lastOutputs`
            // don't read a decision that never happened this turn. Matches Swift's
            // `state.lastOutputs[persona.name] = nil` on the skip path.
            //
            // Note the interaction with the seed above: clearing here also means
            // the agent's NEXT sub-round seeds empty rather than re-seeding a
            // statement from before the failure. Swift behaves identically.
            lastOutputs = state.lastOutputs - persona.name,
        )

        context.emitter(
            SimulationEvent.AgentOutput(
                agent = persona.name,
                output = output,
                phaseType = context.phase.type,
            ),
        )

        val content = output.fields[mainField] ?: ""
        // Fold ALL THREE success-path writes into ONE `state.copy` — the log
        // entry, `lastOutputs`, and captureMood's `variables` (#913, a no-op
        // unless the phase declares `mood`). A second copy off the original would
        // drop the first write; see `ChooseHandler`'s § "State threading".
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
