package com.pastura.engine

import com.pastura.models.PhaseType
import com.pastura.models.SimulationError
import com.pastura.models.SimulationEvent
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.assertFailsWith

/**
 * commonTest parity spec for [TurnFailureGate], ported from
 * `Pastura/PasturaTests/Engine/TurnFailureGateTests.swift` (7 Swift tests) plus
 * one new wrapped-wrong-case probe.
 */
class TurnFailureGateTests {

    // A type DISJOINT from the cancellation hierarchy: Kotlin
    // `CancellationException : IllegalStateException`, so a systemic-rethrow probe
    // must not use IllegalStateException or it would read as cancellation.
    private class ProbeError : RuntimeException("boom")

    private fun MutableList<SimulationEvent>.skipped(): List<SimulationEvent.TurnSkipped> =
        filterIsInstance<SimulationEvent.TurnSkipped>()

    @Test
    fun successReturnsValueAndEmitsNothing() = runTest {
        val gate = TurnFailureGate()
        val events = mutableListOf<SimulationEvent>()

        val value = gate.attempt(
            agent = "Alice", phaseType = PhaseType.SPEAK_ALL, emitter = { events.add(it) },
        ) { "ok" }

        assertEquals("ok", value)
        assertTrue(events.isEmpty())
    }

    @Test
    fun transientFailureSkipsTurnAndEmitsTurnSkipped() = runTest {
        val gate = TurnFailureGate()
        val events = mutableListOf<SimulationEvent>()

        val value: String? = gate.attempt(
            agent = "Alice", phaseType = PhaseType.SPEAK_ALL, emitter = { events.add(it) },
        ) { throw SimulationException(SimulationError.RetriesExhausted) }

        assertNull(value)
        assertEquals(
            listOf(
                SimulationEvent.TurnSkipped(
                    agent = "Alice", phaseType = PhaseType.SPEAK_ALL, cause = "retries exhausted",
                ),
            ),
            events.skipped(),
        )
    }

    @Test
    fun generationFailureCarriesDescriptionAsCause() = runTest {
        val gate = TurnFailureGate()
        val events = mutableListOf<SimulationEvent>()

        val value: String? = gate.attempt(
            agent = "Bob", phaseType = PhaseType.VOTE, emitter = { events.add(it) },
        ) { throw SimulationException(SimulationError.LlmGenerationFailed("transient blip")) }

        assertNull(value)
        assertEquals(
            listOf(
                SimulationEvent.TurnSkipped(
                    agent = "Bob", phaseType = PhaseType.VOTE, cause = "transient blip",
                ),
            ),
            events.skipped(),
        )
    }

    @Test
    fun systemicErrorRethrowsTypedWithoutSkip() = runTest {
        // ADR-021 D3: a deterministic engineering bug must abort in one throw,
        // not degrade turn-by-turn. ProbeError stands in for Swift's
        // LLMError.invalidGrammar (not ported to Kotlin).
        val gate = TurnFailureGate()
        val events = mutableListOf<SimulationEvent>()

        assertFailsWith<ProbeError> {
            gate.attempt(
                agent = "Alice", phaseType = PhaseType.SPEAK_ALL, emitter = { events.add(it) },
            ) { throw ProbeError() }
        }
        assertTrue(events.isEmpty())
    }

    @Test
    fun cancellationRethrowsWithoutSkip() = runTest {
        // ADR-021 D3 control-flow class: user cancellation must never be
        // converted into a skipped turn.
        val gate = TurnFailureGate()
        val events = mutableListOf<SimulationEvent>()

        assertFailsWith<CancellationException> {
            gate.attempt(
                agent = "Alice", phaseType = PhaseType.SPEAK_ALL, emitter = { events.add(it) },
            ) { throw CancellationException("cancel") }
        }
        assertTrue(events.isEmpty())
    }

    @Test
    fun thirdConsecutiveFailureTripsBreaker() = runTest {
        // ADR-021 D4: skips 1 and 2 emit TurnSkipped; the 3rd consecutive failure
        // throws turnFailureLimitReached INSTEAD of a 3rd skip. The counter is
        // shared across phases — the failures span speak_all → vote.
        val gate = TurnFailureGate()
        val events = mutableListOf<SimulationEvent>()

        for (phase in listOf(PhaseType.SPEAK_ALL, PhaseType.SPEAK_ALL)) {
            val value: String? = gate.attempt(
                agent = "Alice", phaseType = phase, emitter = { events.add(it) },
            ) { throw SimulationException(SimulationError.RetriesExhausted) }
            assertNull(value)
        }

        val thrown = assertFailsWith<SimulationException> {
            gate.attempt(
                agent = "Bob", phaseType = PhaseType.VOTE, emitter = { events.add(it) },
            ) { throw SimulationException(SimulationError.RetriesExhausted) }
        }
        val error = thrown.error
        assertIs<SimulationError.TurnFailureLimitReached>(error)
        assertEquals(3, error.consecutiveCount)
        // Only the first two failures produced skip events.
        assertEquals(2, events.skipped().size)
    }

    @Test
    fun successResetsConsecutiveCounter() = runTest {
        // ADR-021 D4: F F S F F must NOT trip the 3-consecutive breaker.
        val gate = TurnFailureGate()
        val events = mutableListOf<SimulationEvent>()

        suspend fun fail(): String? = gate.attempt(
            agent = "Alice", phaseType = PhaseType.SPEAK_ALL, emitter = { events.add(it) },
        ) { throw SimulationException(SimulationError.RetriesExhausted) }

        fail()
        fail()
        val ok = gate.attempt(
            agent = "Alice", phaseType = PhaseType.SPEAK_ALL, emitter = { events.add(it) },
        ) { "recovered" }
        assertEquals("recovered", ok)
        fail()
        fail()

        assertEquals(4, events.skipped().size)
    }

    @Test
    fun wrappedNonDegradableCaseRethrowsBeforeCounterIncrements() = runTest {
        // NEW (fills a gap the Swift set misses): a WRAPPED but non-degradable
        // SimulationError (ModelNotLoaded) must rethrow before the counter
        // increments — proving the branch a too-broad `catch(SimulationException)`
        // would silently degrade. No skip event may be emitted.
        val gate = TurnFailureGate()
        val events = mutableListOf<SimulationEvent>()

        val thrown = assertFailsWith<SimulationException> {
            gate.attempt(
                agent = "Alice", phaseType = PhaseType.SPEAK_ALL, emitter = { events.add(it) },
            ) { throw SimulationException(SimulationError.ModelNotLoaded) }
        }
        assertIs<SimulationError.ModelNotLoaded>(thrown.error)
        assertTrue(events.isEmpty())
    }
}
