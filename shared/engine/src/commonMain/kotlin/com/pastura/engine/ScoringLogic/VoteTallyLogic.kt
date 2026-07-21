package com.pastura.engine

import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState

/**
 * Vote tally scoring logic.
 *
 * Adds each agent's vote count from `state.voteResults` to their cumulative
 * score. Votes for names not already present in `state.scores` are ignored.
 *
 * Kotlin [SimulationState] is immutable, so unlike Swift's `inout` this returns
 * the next state (see [SpeakAllHandler]).
 *
 * Swift original: `Pastura/Pastura/Engine/ScoringLogic/VoteTallyLogic.swift`.
 */
internal class VoteTallyLogic {

    fun calculate(
        state: SimulationState,
        emitter: (SimulationEvent) -> Unit,
    ): SimulationState {
        val scores = state.scores.toMutableMap()
        for ((name, count) in state.voteResults) {
            if (state.scores[name] != null) {
                scores[name] = (scores[name] ?: 0) + count
            }
        }
        emitter(SimulationEvent.ScoreUpdate(scores = scores))
        return state.copy(scores = scores)
    }
}
