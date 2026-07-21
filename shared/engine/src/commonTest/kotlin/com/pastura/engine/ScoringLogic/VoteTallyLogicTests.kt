package com.pastura.engine

import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Kotlin sibling of Swift's `VoteTallyLogicTests`.
 *
 * Ported for the ADR-023 Stage-3 PR-1 score_calc slice (#501).
 */
class VoteTallyLogicTests {

    private val logic = VoteTallyLogic()

    @Test
    fun talliesVotesIntoScores() {
        val state = SimulationState(
            scores = mapOf("A" to 5, "B" to 3),
            voteResults = mapOf("A" to 2, "B" to 1),
        )
        val events = mutableListOf<SimulationEvent>()
        val next = logic.calculate(state) { events += it }
        assertEquals(7, next.scores["A"])
        assertEquals(4, next.scores["B"])
        assertEquals(1, events.filterIsInstance<SimulationEvent.ScoreUpdate>().size)
    }

    @Test
    fun handlesZeroVotes() {
        val state = SimulationState(
            scores = mapOf("A" to 5, "B" to 3),
            voteResults = mapOf("A" to 0, "B" to 0),
        )
        val next = logic.calculate(state) { }
        assertEquals(5, next.scores["A"])
        assertEquals(3, next.scores["B"])
    }

    @Test
    fun ignoresVotesForUnknownAgents() {
        val state = SimulationState(
            scores = mapOf("A" to 5),
            voteResults = mapOf("Unknown" to 3),
        )
        val next = logic.calculate(state) { }
        assertEquals(5, next.scores["A"])
        // Unknown must not be added to scores.
        assertNull(next.scores["Unknown"])
    }
}
