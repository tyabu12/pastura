package com.pastura.engine

import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState
import com.pastura.models.TurnOutput
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Kotlin sibling of Swift's `EventReactivePayoffLogicTests` (#931).
 *
 * The favored action is read from `state.variables[favoredVariable]`; these
 * tests write it directly rather than routing through `EventInjectHandler`.
 * (Swift's `customEventVariableScoresNothingUnderV1` case is a ScoreCalcHandler
 * dispatch test — that handler is not part of this slice — so it is omitted.)
 *
 * Ported for the ADR-023 Stage-3 PR-1 score_calc slice (#501).
 */
class EventReactivePayoffLogicTests {

    private val logic = EventReactivePayoffLogic()
    private val favoredKey = "current_event__favors"
    private val reward = EventReactivePayoffLogic.matchReward

    private fun output(action: String) = TurnOutput(fields = mapOf("action" to action))

    @Test
    fun rewardsOnlyAgentsWhoMatchedFavoredAction() {
        val state = SimulationState(
            scores = mapOf("Alice" to 0, "Bob" to 0),
            lastOutputs = mapOf("Alice" to output("betray"), "Bob" to output("cooperate")),
            variables = mapOf(favoredKey to "betray"),
        )
        val next = logic.calculate(state, favoredKey) { }
        assertEquals(reward, next.scores["Alice"])
        assertEquals(0, next.scores["Bob"])
    }

    @Test
    fun symmetricForCooperateFavored() {
        val state = SimulationState(
            scores = mapOf("Alice" to 0, "Bob" to 0),
            lastOutputs = mapOf("Alice" to output("betray"), "Bob" to output("cooperate")),
            variables = mapOf(favoredKey to "cooperate"),
        )
        val next = logic.calculate(state, favoredKey) { }
        assertEquals(0, next.scores["Alice"])
        assertEquals(reward, next.scores["Bob"])
    }

    @Test
    fun rewardAddsToExistingScore() {
        val state = SimulationState(
            scores = mapOf("Alice" to 5),
            lastOutputs = mapOf("Alice" to output("betray")),
            variables = mapOf(favoredKey to "betray"),
        )
        val next = logic.calculate(state, favoredKey) { }
        assertEquals(5 + reward, next.scores["Alice"])
    }

    @Test
    fun missingFavoredVariableIsNoOp() {
        // favoredKey absent → simulates a plain-string event list (no companion var).
        val state = SimulationState(
            scores = mapOf("Alice" to 0, "Bob" to 0),
            lastOutputs = mapOf("Alice" to output("betray"), "Bob" to output("cooperate")),
        )
        val next = logic.calculate(state, favoredKey) { }
        assertEquals(0, next.scores["Alice"])
        assertEquals(0, next.scores["Bob"])
    }

    @Test
    fun emptyFavoredVariableIsNoOp() {
        // "" is what EventInjectHandler writes on a miss round — must not reward.
        val state = SimulationState(
            scores = mapOf("Alice" to 0),
            lastOutputs = mapOf("Alice" to output("betray")),
            variables = mapOf(favoredKey to ""),
        )
        val next = logic.calculate(state, favoredKey) { }
        assertEquals(0, next.scores["Alice"])
    }

    @Test
    fun alwaysEmitsScoreUpdate() {
        // No favored var → inert, but a scoreUpdate must still be emitted.
        val state = SimulationState(
            scores = mapOf("Alice" to 0),
            lastOutputs = mapOf("Alice" to output("betray")),
        )
        val events = mutableListOf<SimulationEvent>()
        logic.calculate(state, favoredKey) { events += it }
        assertEquals(1, events.filterIsInstance<SimulationEvent.ScoreUpdate>().size)
    }

    @Test
    fun ignoresOutputsWithoutASeededScore() {
        val state = SimulationState(
            scores = mapOf("Alice" to 0),
            // No score seeded for "Ghost" → gated out (not a live agent).
            lastOutputs = mapOf("Alice" to output("betray"), "Ghost" to output("betray")),
            variables = mapOf(favoredKey to "betray"),
        )
        val next = logic.calculate(state, favoredKey) { }
        assertEquals(reward, next.scores["Alice"])
        assertNull(next.scores["Ghost"])
    }

    @Test
    fun rewardsCaseAndWhitespaceVariantActions() {
        // Casing/whitespace variants must still count against a lowercase favors.
        val state = SimulationState(
            scores = mapOf("Alice" to 0, "Bob" to 0, "Carol" to 0),
            lastOutputs = mapOf(
                "Alice" to output("Betray"),
                "Bob" to output(" betray "),
                "Carol" to output("BETRAY"),
            ),
            variables = mapOf(favoredKey to "betray"),
        )
        val next = logic.calculate(state, favoredKey) { }
        assertEquals(reward, next.scores["Alice"])
        assertEquals(reward, next.scores["Bob"])
        assertEquals(reward, next.scores["Carol"])
    }

    @Test
    fun doesNotRewardNonMatchingActionAfterNormalization() {
        val state = SimulationState(
            scores = mapOf("Alice" to 0),
            lastOutputs = mapOf("Alice" to output("Cooperate")),
            variables = mapOf(favoredKey to "betray"),
        )
        val next = logic.calculate(state, favoredKey) { }
        assertEquals(0, next.scores["Alice"])
    }
}
