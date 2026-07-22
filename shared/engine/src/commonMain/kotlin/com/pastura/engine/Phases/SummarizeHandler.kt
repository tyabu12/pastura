package com.pastura.engine

import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState

/**
 * Handles `summarize` phases that format round summary text.
 *
 * Expands a template with state variables. If pairings exist and the template
 * contains `{agent1}`, expands per-pairing (joining the results with `\n`).
 * Otherwise expands once. The default template (when the phase declares none) is
 * language-dispatched via [pickLanguage].
 *
 * **Emit-only — this handler never mutates state.** Swift's `execute` reads state
 * and emits `.summary` but never writes `state`; every path here therefore
 * `return state` UNCHANGED. A handler that built a `.copy` but returned the
 * original would compile cleanly and silently drop the change — see
 * [PhaseHandler]. There is nothing to change, so no `.copy` is invented.
 *
 * **`formatConversationLog` is called with NO `window` argument** (full log).
 * `log_window` is a prompt-side lever for LLM phases only; summarize is a code
 * phase, so the full log is formatted — matching Swift, which deliberately omits
 * the window here.
 *
 * A code phase — it never touches [PhaseContext.turnGate] (no LLM turn), matching
 * Swift, where the code phases ignore it too.
 *
 * Swift original: `Pastura/Pastura/Engine/Phases/SummarizeHandler.swift`.
 */
internal class SummarizeHandler : PhaseHandler {

    private val promptBuilder = PromptBuilder()

    override suspend fun execute(context: PhaseContext, state: SimulationState): SimulationState {
        val template = context.phase.template
            ?: pickLanguage(
                context.scenario.engineLanguage,
                ja = "ラウンド {current_round} 完了",
                en = "Round {current_round} complete",
            )

        // Invariant across pairings — formatted once, injected per-iteration below.
        // No `window` arg: full log, unlike the LLM phases (see the class doc).
        val conversationLog = promptBuilder.formatConversationLog(
            entries = state.conversationLog,
            language = context.scenario.engineLanguage,
        )

        if (state.pairings.isNotEmpty() && template.contains("{agent1}")) {
            // Expand template per pairing.
            val lines = state.pairings.map { pairing ->
                // Superset of the prototype's pair path: we also merge state.variables
                // so shared placeholders like {scoreboard}, {current_round},
                // {vote_results} resolve inside pair expansion. Pair-specific keys
                // (agent1, action1, …) are written *after* the merge so they can never
                // be shadowed by a user-defined state.variables entry with the same name.
                val variables = state.variables.toMutableMap()
                variables["agent1"] = pairing.agent1
                variables["action1"] = pairing.action1 ?: "?"
                variables["agent2"] = pairing.agent2
                variables["action2"] = pairing.action2 ?: "?"
                variables["score1"] = "${state.scores[pairing.agent1] ?: 0}"
                variables["score2"] = "${state.scores[pairing.agent2] ?: 0}"
                variables["scoreboard"] = promptBuilder.formatScoreboard(state.scores)
                variables["current_round"] = "${state.currentRound}"
                variables["conversation_log"] = conversationLog
                promptBuilder.expandTemplate(template, variables)
            }
            context.emitter(SimulationEvent.Summary(text = lines.joinToString(separator = "\n")))
        } else {
            // Simple expansion.
            val variables = state.variables.toMutableMap()
            variables["scoreboard"] = promptBuilder.formatScoreboard(state.scores)
            variables["current_round"] = "${state.currentRound}"
            variables["conversation_log"] = conversationLog
            val text = promptBuilder.expandTemplate(template, variables)
            context.emitter(SimulationEvent.Summary(text = text))
        }

        return state
    }
}
