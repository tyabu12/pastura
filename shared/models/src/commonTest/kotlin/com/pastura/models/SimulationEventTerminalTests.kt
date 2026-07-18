package com.pastura.models

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Tests for [SimulationEvent.isTerminal] (#1171).
 *
 * These pin the terminality of the subclasses that exist **today** — that
 * [SimulationEvent.SimulationCompleted] and [SimulationEvent.ErrorEvent] stay
 * terminal, and that their nearest neighbours stay non-terminal.
 *
 * What they deliberately do NOT cover, since it would be easy to read them as
 * covering it: a *newly added* subclass mis-assigned to a `false` branch. The
 * exhaustive `when` forces a new subclass to make *a* decision, not the *right*
 * one, and a new subclass appears in none of the sample lists below, so nothing
 * here turns red either. Neither gate catches that; only review does.
 * (`sealedSubclasses` is JVM-reflection-only and unavailable in `commonMain`,
 * so there is no cheap machinery to close it.)
 *
 * `SimulationEventTerminalTests.swift` declares the same two terminal cases on
 * the Swift mirror. That agreement is maintained by hand — no gate compares the
 * two files.
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
     * Of these nine sampled subclasses, exactly the two known terminals are
     * terminal. `sample` is a fixed list, so this does not oblige a visit when
     * a subclass is added — it pins that the seven non-terminal neighbours stay
     * that way, which is the direction a careless `true`-side edit would break.
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
