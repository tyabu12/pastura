package com.pastura.engine

import com.pastura.models.PayoffRule
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState

/**
 * Generic pairwise payoff scoring logic (ADR-027).
 *
 * Scores each `Pairing` by matching `(action1, action2)` positionally against a
 * YAML-authored payoff table ([PayoffRule] list). The first row whose `when`
 * equals the pairing's two actions awards `points[0]` to `agent1` and
 * `points[1]` to `agent2`. A pairing matching no row scores nothing — the engine
 * never fabricates a verdict (a `null` action, an off-table action pair, or an
 * empty table all degrade to zero). Clears `state.pairings` after scoring,
 * exactly as the legacy [PrisonersDilemmaLogic] shim does.
 *
 * Swift original:
 * `Pastura/Pastura/Engine/ScoringLogic/PairwisePayoffLogic.swift`.
 */
internal class PairwisePayoffLogic {

    fun calculate(
        state: SimulationState,
        payoff: List<PayoffRule>,
        emitter: (SimulationEvent) -> Unit,
    ): SimulationState {
        val scores = state.scores.toMutableMap()
        for (pairing in state.pairings) {
            // A half-real pairing (either action null) matches no row and scores
            // nothing — the correct degradation, not a fabricated verdict.
            val act1 = pairing.action1 ?: continue
            val act2 = pairing.action2 ?: continue
            // No row for this action pair (or a malformed row that slipped past
            // the loader's arity guard) → score nothing.
            val row = payoff.firstOrNull { it.`when` == listOf(act1, act2) } ?: continue
            if (row.points.size != 2) continue
            scores[pairing.agent1] = (scores[pairing.agent1] ?: 0) + row.points[0]
            scores[pairing.agent2] = (scores[pairing.agent2] ?: 0) + row.points[1]
        }

        emitter(SimulationEvent.ScoreUpdate(scores = scores))
        return state.copy(scores = scores, pairings = emptyList())
    }
}
