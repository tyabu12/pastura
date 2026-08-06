package com.pastura.engine

import com.pastura.models.OutputSchema
import com.pastura.models.Persona
import com.pastura.models.Scenario
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState
import com.pastura.models.TurnOutput

/**
 * Handles `vote` phases, where every active agent votes for one agent.
 *
 * Each non-eliminated agent generates one `{vote}` via the LLM. Votes are tallied,
 * the result is stored in [SimulationState.voteResults] (and the `{vote_results}`
 * template variable), and a [SimulationEvent.VoteResults] event is emitted.
 *
 * ## Hybrid write semantics — neither pure speak nor pure reflect
 *
 * Like [SpeakAllHandler], a vote WRITES `lastOutputs` (so `relationship_update` can
 * read `state.lastOutputs[voter].vote`) and CLEARS a stale entry on an abstention.
 * Unlike the speak handlers, a vote is NOT an utterance, so it is never appended to
 * `conversationLog`. Unlike [ReflectHandler] (which never touches `lastOutputs`),
 * the skip path here must actively clear the stale ballot.
 *
 * A vote outside the voter's candidate list — self under `exclude_self`, an
 * eliminated agent, or a hallucinated name — is dropped from the tally so it cannot
 * distort scoring or elimination; the raw value is still recorded in the per-voter
 * `votes` map for observability in the event (#524).
 *
 * A turn-degradable LLM failure is routed through [PhaseContext.turnGate]
 * (ADR-021 D1/D2) and treated as an **abstention**: no ballot is recorded (neither
 * the `votes` map nor the tally), no `AgentOutput` is emitted, and the voter's
 * stale `lastOutputs` entry is cleared so a decision that never happened this turn
 * can't leak into consumers keyed on it. The remaining agents still vote.
 *
 * Swift original: `Pastura/Pastura/Engine/Phases/VoteHandler.swift`.
 */
internal class VoteHandler : PhaseHandler {

    private val promptBuilder = PromptBuilder()

    /** A voter's turn outcome: the next state, plus the ballot (`null` on abstention). */
    private data class VoteTurn(val state: SimulationState, val output: TurnOutput?)

    override suspend fun execute(context: PhaseContext, state: SimulationState): SimulationState {
        val promptTemplate = context.phase.prompt
            ?: pickLanguage(
                context.scenario.engineLanguage,
                ja = "最も怪しいと思う人に投票してください。",
                en = "Vote for the person you find most suspicious.",
            )
        val excludeSelf = context.phase.excludeSelf ?: true

        val votes = mutableMapOf<String, String>() // voter -> target (raw value)
        val tallies = mutableMapOf<String, Int>()
        var current = state

        for (persona in context.scenario.personas) {
            // `== true` to SKIP: an agent absent from the map reads `null`, which is
            // not `true`, so it votes — matching Swift's `!= true` guard.
            if (current.eliminated[persona.name] == true) continue

            val candidates = voteCandidates(context.scenario, persona, excludeSelf, current)
            val turn = voteTurn(context, persona, promptTemplate, candidates, current)
            // Thread `current` BEFORE the abstention `continue`: the skip path returns
            // a state with the voter's stale `lastOutputs` cleared, so this assignment
            // is load-bearing even when there is no ballot. Reordering it after the
            // `?: continue` would silently drop that clear.
            current = turn.state
            val output = turn.output ?: continue // abstention — gate already emitted TurnSkipped

            val votedFor = output.fields["vote"] ?: ""
            votes[persona.name] = votedFor
            // Tally only votes for a valid candidate. Out-of-candidate votes (self
            // under exclude_self, eliminated agents, or hallucinated names) are
            // dropped so they cannot distort scoring or elimination (#524); the raw
            // value stays in `votes` for observability in the VoteResults event.
            if (candidates.contains(votedFor)) {
                tallies[votedFor] = (tallies[votedFor] ?: 0) + 1
            }
        }

        // Post-loop fold: ONE copy off the THREADED `current` (which already carries
        // every per-turn lastOutputs / captureMood write) — NOT off the original
        // `state`, which would drop them all. Key must be "vote_results" (plural) to
        // match the {vote_results} placeholder documented in PhaseEditorSheet and
        // used by the word_wolf preset's summarize template.
        val nextVariables = current.variables.toMutableMap()
        nextVariables["vote_results"] = promptBuilder.formatScoreboard(tallies)
        val next = current.copy(
            voteResults = tallies,
            variables = nextVariables,
        )

        context.emitter(SimulationEvent.VoteResults(votes = votes, tallies = tallies))
        return next
    }

    /**
     * Runs one voter's turn: builds the prompt, routes the LLM call through
     * [PhaseContext.turnGate] (ADR-021 D1/D2), and on success emits `AgentOutput`,
     * records the ballot in `lastOutputs`, and captures mood. On a skipped turn,
     * emits nothing, clears any stale `lastOutputs` entry, and returns a `null`
     * output (the caller records no ballot — an abstention).
     *
     * Returns BOTH the next state and the output — unlike [SpeakAllHandler]'s
     * `speakTurn` / [ReflectHandler]'s `reflectTurn` (state only), the caller needs
     * the vote value to tally. Kotlin [SimulationState] is immutable, so the caller
     * MUST use the returned state (see [PhaseHandler]).
     */
    private suspend fun voteTurn(
        context: PhaseContext,
        persona: Persona,
        promptTemplate: String,
        candidates: List<String>,
        state: SimulationState,
    ): VoteTurn {
        // Constructed per turn, matching Swift — a stateless value, cheap. The logger
        // seam is threaded from the context (Noop by default in the current run
        // path — see PhaseContext § "Knowingly absent").
        val llmCaller = LLMCaller(logger = context.logger)

        val systemPrompt = promptBuilder.buildSystemPrompt(
            scenario = context.scenario,
            persona = persona,
            phase = context.phase,
            state = state,
        )

        // Local prompt-variable map (thrown away after the prompt is built). The
        // `inject*` family mutates it in place to surface each reserved-namespace
        // `{token}` to only this voter; none of this touches persisted state.
        val variables = state.variables.toMutableMap()
        variables["scoreboard"] = promptBuilder.formatScoreboard(state.scores)
        variables["conversation_log"] = promptBuilder.formatConversationLog(
            entries = state.conversationLog,
            language = context.scenario.engineLanguage,
            window = context.scenario.logWindow,
        )
        variables["candidates"] = candidates.joinToString(separator = ", ")
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
                phaseType = context.phase.type,
                schema = OutputSchema.from(context.phase),
                detector = context.detector,
                expectedLanguage = context.scenario.engineLanguage,
                relay = context.suspensionRelay,
                emitter = context.emitter,
            )
        } ?: return VoteTurn(
            // Abstention (ADR-021 D2): clear any stale prior-round output so
            // downstream consumers keyed on `lastOutputs` (e.g. relationship_update)
            // don't read a decision that never happened this turn. Matches Swift's
            // `state.lastOutputs[persona.name] = nil` on the skip path — the
            // deliberate divergence from ReflectHandler, which has nothing to clear.
            state = state.copy(lastOutputs = state.lastOutputs - persona.name),
            output = null,
        )

        context.emitter(
            SimulationEvent.AgentOutput(
                agent = persona.name,
                output = output,
                phaseType = context.phase.type,
            ),
        )

        // Fold BOTH success-path writes into ONE `state.copy`: the ballot into
        // `lastOutputs`, and captureMood (#913, a no-op unless the phase declares
        // `mood`) into a fresh `variables` copy. A second copy off the original would
        // drop the first write (Kotlin's immutable state; Swift threads two
        // sequential `inout` mutations instead). No conversationLog entry — a vote is
        // not an utterance.
        val nextVariables = state.variables.toMutableMap()
        promptBuilder.captureMood(output, nextVariables, persona.name)
        return VoteTurn(
            state = state.copy(
                variables = nextVariables,
                lastOutputs = state.lastOutputs + (persona.name to output),
            ),
            output = output,
        )
    }

    /**
     * The valid vote targets for [voter]: all personas minus self (under
     * [excludeSelf]) and any eliminated agent. Kept in lockstep with
     * `PromptBuilder.voteCandidateRule`, which lists the same set in the prompt, so
     * the prompt's "valid names" and the accepted-vote tally never diverge.
     */
    private fun voteCandidates(
        scenario: Scenario,
        voter: Persona,
        excludeSelf: Boolean,
        state: SimulationState,
    ): List<String> =
        scenario.personas
            .map { it.name }
            .filter { name ->
                if (excludeSelf && name == voter.name) return@filter false
                if (state.eliminated[name] == true) return@filter false
                true
            }
}
