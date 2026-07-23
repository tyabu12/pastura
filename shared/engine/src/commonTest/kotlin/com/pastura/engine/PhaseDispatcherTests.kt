package com.pastura.engine

import com.pastura.models.PhaseType
import com.pastura.models.SimulationError
import kotlinx.serialization.serializer
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertTrue

/**
 * Kotlin sibling of Swift's `PhaseDispatcherTests`, scoped to the one handler this
 * slice registers.
 *
 * Ported for the ADR-023 §6 Stage-2 gate slice (#501).
 */
class PhaseDispatcherTests {

    private val dispatcher = PhaseDispatcher()

    @Test
    fun resolvesTheSpeakAllHandler() {
        assertIs<SpeakAllHandler>(dispatcher.handler(PhaseType.SPEAK_ALL))
    }

    @Test
    fun resolvesTheEliminateHandler() {
        assertIs<EliminateHandler>(dispatcher.handler(PhaseType.ELIMINATE))
    }

    @Test
    fun resolvesTheSummarizeHandler() {
        assertIs<SummarizeHandler>(dispatcher.handler(PhaseType.SUMMARIZE))
    }

    @Test
    fun resolvesTheAssignHandler() {
        assertIs<AssignHandler>(dispatcher.handler(PhaseType.ASSIGN))
    }

    @Test
    fun resolvesTheEventInjectHandler() {
        assertIs<EventInjectHandler>(dispatcher.handler(PhaseType.EVENT_INJECT))
    }

    @Test
    fun returnsAStableHandlerInstance() {
        // Handlers are stateless values; the dispatcher builds its map once.
        assertTrue(dispatcher.handler(PhaseType.SPEAK_ALL) === dispatcher.handler(PhaseType.SPEAK_ALL))
    }

    @Test
    fun throwsForAPhaseTypeThisSliceHasNotPorted() {
        val error = assertFailsWith<SimulationException> { dispatcher.handler(PhaseType.VOTE) }
        assertIs<SimulationError.ScenarioValidationFailed>(error.error)
    }

    @Test
    fun theErrorNamesThePhaseUsingItsWireNameNotItsKotlinCaseName() {
        // `speak_all`, not `SPEAK_ALL` — Swift interpolates `phaseType.rawValue`,
        // and a reader comparing the two engines' errors should see the same token.
        val error = assertFailsWith<SimulationException> { dispatcher.handler(PhaseType.SCORE_CALC) }
        val message = assertIs<SimulationError.ScenarioValidationFailed>(error.error).message
        assertTrue(message.contains("score_calc"), "expected the wire name, got: $message")
        assertTrue(!message.contains("SCORE_CALC"), "the Kotlin case name must not leak: $message")
    }

    @Test
    fun everyUnportedPhaseTypeFailsCleanlyRatherThanCrashing() {
        // A Stage-3 gap must read as a gap. Iterating allCases also means a NEW
        // PhaseType added to Models cannot silently reach dispatch unhandled.
        val unported = PhaseType.entries.filter {
            it != PhaseType.SPEAK_ALL && it != PhaseType.ELIMINATE &&
                it != PhaseType.SUMMARIZE && it != PhaseType.ASSIGN &&
                it != PhaseType.EVENT_INJECT
        }
        assertEquals(9, unported.size, "Kotlin PhaseType has 14 cases today; see the #501 drift ledger")
        for (type in unported) {
            val error = assertFailsWith<SimulationException>("$type must fail cleanly") {
                dispatcher.handler(type)
            }
            assertIs<SimulationError.ScenarioValidationFailed>(error.error)
        }
    }

    @Test
    fun wireNamesResolveFromTheSerialDescriptorForEveryCase() {
        // Asserts against the DESCRIPTOR, not against `name.lowercase()`. The
        // earlier version asserted the lowercase derivation — i.e. exactly the
        // coincidence the implementation deliberately rejects — so it passed
        // identically against a `name.lowercase()` impl and pinned nothing.
        for (type in PhaseType.entries) {
            val error = runCatching { dispatcher.handler(type) }.exceptionOrNull()
            if (error !is SimulationException) continue // SPEAK_ALL resolves
            val message = assertIs<SimulationError.ScenarioValidationFailed>(error.error).message
            val fromDescriptor = PhaseType.serializer().descriptor.getElementName(type.ordinal)
            assertTrue(
                message.contains(fromDescriptor),
                "expected @SerialName '$fromDescriptor' for $type in: $message",
            )
        }
    }
}
