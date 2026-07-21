package com.pastura.engine

import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState

/**
 * Event-reactive payoff scoring logic (#931).
 *
 * Rewards every agent whose most recent `choose` action matched the favored
 * action for this round's injected event. The favored action is read from
 * `state.variables[favoredVariable]`, written by `EventInjectHandler` for
 * dict-shaped events.
 *
 * A flat `+3` for a correct read is enough to prove the mechanic; scarcity/curve
 * bonuses and wrong-read penalties are out of scope for v1.
 *
 * Swift original:
 * `Pastura/Pastura/Engine/ScoringLogic/EventReactivePayoffLogic.swift`.
 */
internal class EventReactivePayoffLogic {

    fun calculate(
        state: SimulationState,
        favoredVariable: String,
        emitter: (SimulationEvent) -> Unit,
    ): SimulationState {
        // No favored action for this round (plain-string event list, a
        // probability miss, or an untagged dict entry) → inert no-op. The
        // empty-string check also covers the ghosting-prevention "" that
        // EventInjectHandler writes on a miss round.
        val favored = state.variables[favoredVariable]
        if (favored.isNullOrEmpty()) {
            emitter(SimulationEvent.ScoreUpdate(scores = state.scores))
            return state
        }
        val normalizedFavored = normalize(favored)

        // `state.scores[name] != null` gates out non-agent outputs; scores are
        // seeded for every agent at `SimulationState.initial`, so a live agent
        // is always present.
        val scores = state.scores.toMutableMap()
        for ((name, output) in state.lastOutputs) {
            if (state.scores[name] == null) continue
            val action = output.action ?: continue
            if (normalize(action) == normalizedFavored) {
                scores[name] = (scores[name] ?: 0) + matchReward
            }
        }

        emitter(SimulationEvent.ScoreUpdate(scores = scores))
        return state.copy(scores = scores)
    }

    companion object {
        /** Points awarded to each agent whose action matched the favored action. */
        const val matchReward: Int = 3

        /**
         * Trim + case-fold for the action↔favored comparison. The individual
         * (non-round-robin) `choose` path stores the LLM's raw `action` without
         * canonicalization, so the model may emit `"Betray"` / `" betray"` for a
         * `favors: betray` round; symmetric fold-both-sides never over-matches.
         */
        private fun normalize(value: String): String = value.trim().lowercase()
    }
}
