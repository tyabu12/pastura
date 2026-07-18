package com.pastura.models

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Tests for [SimulationEvent.isTerminal] (#1171).
 *
 * The exhaustive `when` behind the property forces a new subclass to make *a*
 * terminality decision at compile time, but not the *right* one: dropping a
 * genuinely terminal subclass into a `false` branch compiles clean and silently
 * reproduces the never-finishing `AsyncStream` the property exists to prevent.
 * These pins are the half the compiler cannot cover.
 *
 * Mirrored on the Swift side by `SimulationEventTerminalTests.swift` — the two
 * Models declarations must agree, and nothing else asserts that they do.
 */
class SimulationEventTerminalTests {

    @Test
    fun simulationCompletedIsTerminal() {
        assertTrue(SimulationEvent.SimulationCompleted.isTerminal)
    }

    @Test
    fun errorEventIsTerminal() {
        assertTrue(SimulationEvent.ErrorEvent(SimulationError.Cancelled).isTerminal)
        assertTrue(SimulationEvent.ErrorEvent(SimulationError.RetriesExhausted).isTerminal)
    }

    /**
     * `SimulationPaused` is the trap this pins: a run stops after it, so it
     * reads terminal, but the stream must stay open — a paused run resumes and
     * keeps emitting. Treating it as terminal would truncate every resumed run.
     */
    @Test
    fun pausedIsNotTerminal() {
        assertFalse(SimulationEvent.SimulationPaused(round = 2, phasePath = listOf(0)).isTerminal)
    }

    @Test
    fun ordinaryEventsAreNotTerminal() {
        assertFalse(SimulationEvent.RoundStarted(round = 1, totalRounds = 3).isTerminal)
        assertFalse(SimulationEvent.ScoreUpdate(scores = mapOf("Alice" to 1)).isTerminal)
        assertFalse(SimulationEvent.Summary(text = "s").isTerminal)
        assertFalse(SimulationEvent.InferenceStarted(agent = "a").isTerminal)
    }

    /**
     * Exactly two subclasses are terminal. A future subclass added to the
     * `true` side widens stream termination for every consumer, so it should be
     * a deliberate edit rather than an incidental one.
     */
    @Test
    fun onlyTwoCasesAreTerminal() {
        val sample = listOf(
            SimulationEvent.RoundStarted(round = 1, totalRounds = 1),
            SimulationEvent.RoundCompleted(round = 1, scores = emptyMap()),
            SimulationEvent.ScoreUpdate(scores = emptyMap()),
            SimulationEvent.Summary(text = "s"),
            SimulationEvent.Elimination(agent = "a", voteCount = 1),
            SimulationEvent.SimulationPaused(round = 1, phasePath = listOf(0)),
            SimulationEvent.InferenceStarted(agent = "a"),
            SimulationEvent.SimulationCompleted,
            SimulationEvent.ErrorEvent(SimulationError.Cancelled),
        )

        assertEquals(2, sample.count { it.isTerminal })
    }
}
