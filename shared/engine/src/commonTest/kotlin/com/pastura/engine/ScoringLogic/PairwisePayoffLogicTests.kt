package com.pastura.engine

import com.pastura.models.Pairing
import com.pastura.models.PayoffRule
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Kotlin sibling of Swift's `PairwisePayoffLogicTests`.
 *
 * Ported for the ADR-023 Stage-3 PR-1 score_calc slice (#501).
 */
class PairwisePayoffLogicTests {

    private val logic = PairwisePayoffLogic()

    /**
     * A localized (Japanese-token) payoff table — the motivating case for
     * ADR-027, unscorable by the pre-ADR hardcoded English matrix.
     */
    private val jaTable: List<PayoffRule> = listOf(
        PayoffRule(`when` = listOf("協力", "協力"), points = listOf(3, 3)),
        PayoffRule(`when` = listOf("協力", "裏切り"), points = listOf(0, 5)),
        PayoffRule(`when` = listOf("裏切り", "協力"), points = listOf(5, 0)),
        PayoffRule(`when` = listOf("裏切り", "裏切り"), points = listOf(1, 1)),
    )

    private fun makeState() = SimulationState(scores = mapOf("A" to 0, "B" to 0))

    private fun stateWith(action1: String?, action2: String?) = makeState().copy(
        pairings = listOf(Pairing(agent1 = "A", agent2 = "B", action1 = action1, action2 = action2)),
    )

    @Test
    fun matchesRowAndAwardsPointsPositionally() {
        val next = logic.calculate(stateWith("協力", "裏切り"), jaTable) { }
        assertEquals(0, next.scores["A"])
        assertEquals(5, next.scores["B"])
    }

    @Test
    fun unmatchedActionPairScoresNothing() {
        // Neither action appears in any row's `when`.
        val next = logic.calculate(stateWith("abstain", "abstain"), jaTable) { }
        assertEquals(0, next.scores["A"])
        assertEquals(0, next.scores["B"])
    }

    @Test
    fun nilActionScoresNothing() {
        // A half-real pairing (action2 null) matches no row — no fabricated verdict.
        val next = logic.calculate(stateWith("協力", null), jaTable) { }
        assertEquals(0, next.scores["A"])
        assertEquals(0, next.scores["B"])
    }

    @Test
    fun emptyTableScoresNothing() {
        val next = logic.calculate(stateWith("協力", "協力"), emptyList()) { }
        assertEquals(0, next.scores["A"])
        assertEquals(0, next.scores["B"])
    }

    @Test
    fun malformedRowArityIsSkippedDefensively() {
        // A row whose `points` is not two elements must not crash (index guard) —
        // it simply scores nothing.
        val badTable = listOf(PayoffRule(`when` = listOf("x", "y"), points = listOf(7)))
        val next = logic.calculate(stateWith("x", "y"), badTable) { }
        assertEquals(0, next.scores["A"])
        assertEquals(0, next.scores["B"])
    }

    @Test
    fun firstMatchingRowWins() {
        val table = listOf(
            PayoffRule(`when` = listOf("協力", "協力"), points = listOf(3, 3)),
            PayoffRule(`when` = listOf("協力", "協力"), points = listOf(9, 9)),
        )
        val next = logic.calculate(stateWith("協力", "協力"), table) { }
        assertEquals(3, next.scores["A"])
        assertEquals(3, next.scores["B"])
    }

    @Test
    fun clearsStatePairingsAfterCalc() {
        val next = logic.calculate(stateWith("協力", "協力"), jaTable) { }
        assertTrue(next.pairings.isEmpty())
    }

    @Test
    fun emitsScoreUpdateEvent() {
        val events = mutableListOf<SimulationEvent>()
        logic.calculate(stateWith("協力", "協力"), jaTable) { events += it }
        assertEquals(1, events.filterIsInstance<SimulationEvent.ScoreUpdate>().size)
    }
}
