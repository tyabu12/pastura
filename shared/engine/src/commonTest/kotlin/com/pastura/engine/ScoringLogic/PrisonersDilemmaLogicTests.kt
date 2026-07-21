package com.pastura.engine

import com.pastura.models.Pairing
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Kotlin sibling of Swift's `PrisonersDilemmaLogicTests`.
 *
 * Ported for the ADR-023 Stage-3 PR-1 score_calc slice (#501).
 */
class PrisonersDilemmaLogicTests {

    private val logic = PrisonersDilemmaLogic()

    private fun makeState() = SimulationState(scores = mapOf("A" to 0, "B" to 0))

    private fun stateWith(action1: String, action2: String) = makeState().copy(
        pairings = listOf(Pairing(agent1 = "A", agent2 = "B", action1 = action1, action2 = action2)),
    )

    @Test
    fun cooperateCooperate() {
        val next = logic.calculate(stateWith("cooperate", "cooperate")) { }
        assertEquals(3, next.scores["A"])
        assertEquals(3, next.scores["B"])
    }

    @Test
    fun cooperateBetray() {
        val next = logic.calculate(stateWith("cooperate", "betray")) { }
        assertEquals(0, next.scores["A"])
        assertEquals(5, next.scores["B"])
    }

    @Test
    fun betrayCooperate() {
        val next = logic.calculate(stateWith("betray", "cooperate")) { }
        assertEquals(5, next.scores["A"])
        assertEquals(0, next.scores["B"])
    }

    @Test
    fun betrayBetray() {
        val next = logic.calculate(stateWith("betray", "betray")) { }
        assertEquals(1, next.scores["A"])
        assertEquals(1, next.scores["B"])
    }

    @Test
    fun clearsStatePairingsAfterCalc() {
        val next = logic.calculate(stateWith("cooperate", "cooperate")) { }
        assertTrue(next.pairings.isEmpty())
    }

    @Test
    fun emitsScoreUpdateEvent() {
        val events = mutableListOf<SimulationEvent>()
        logic.calculate(stateWith("cooperate", "cooperate")) { events += it }
        assertEquals(1, events.filterIsInstance<SimulationEvent.ScoreUpdate>().size)
    }
}
