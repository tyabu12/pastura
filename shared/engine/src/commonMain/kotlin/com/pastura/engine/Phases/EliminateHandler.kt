package com.pastura.engine

import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState

/**
 * Handles `eliminate` phases that remove the most-voted agent.
 *
 * Finds the agent with the highest vote count in `state.voteResults` via the
 * shared canonical tie-break ([VoteTally.winner]: count desc, name desc), marks
 * them as eliminated, and emits an elimination event. The canonical tie-break is
 * why an `eliminate` phase and a `conditional` reading `vote_winner` in the same
 * round never disagree on a tie (#1056).
 *
 * A code phase — it never touches [PhaseContext.turnGate] (no LLM turn), matching
 * Swift, where the code phases ignore it too.
 *
 * **No `state: inout`.** Kotlin [SimulationState] is an immutable `data class`, so
 * this returns the next state rather than mutating in place. A handler that builds
 * a `.copy` but returns the original `state` compiles cleanly and silently drops
 * the change — the no-signal paths below therefore `return state` unchanged.
 *
 * Swift original: `Pastura/Pastura/Engine/Phases/EliminateHandler.swift`.
 */
internal class EliminateHandler : PhaseHandler {

    override suspend fun execute(context: PhaseContext, state: SimulationState): SimulationState {
        if (state.voteResults.isEmpty()) return state

        val winner = VoteTally.winner(state.voteResults) ?: return state

        context.emitter(SimulationEvent.Elimination(agent = winner.first, voteCount = winner.second))
        return state.copy(eliminated = state.eliminated + (winner.first to true))
    }
}
