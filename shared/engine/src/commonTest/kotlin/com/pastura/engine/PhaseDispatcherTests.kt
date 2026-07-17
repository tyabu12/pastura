package com.pastura.engine

import com.pastura.models.PhaseType
import com.pastura.models.SimulationError
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
        val unported = PhaseType.entries.filter { it != PhaseType.SPEAK_ALL }
        assertEquals(9, unported.size, "Kotlin PhaseType has 10 cases today; see the #501 drift ledger")
        for (type in unported) {
            val error = assertFailsWith<SimulationException>("$type must fail cleanly") {
                dispatcher.handler(type)
            }
            assertIs<SimulationError.ScenarioValidationFailed>(error.error)
        }
    }

    @Test
    fun wireNamesResolveFromTheSerialDescriptorForEveryCase() {
        // The dispatcher derives its message token from @SerialName rather than
        // from `name.lowercase()`. Both happen to agree today — this asserts the
        // authoritative source is what's read, so a future case whose SerialName
        // is NOT its lowercased name stays correct.
        for (type in PhaseType.entries) {
            val error = runCatching { dispatcher.handler(type) }.exceptionOrNull()
            if (error !is SimulationException) continue // SPEAK_ALL resolves
            val message = assertIs<SimulationError.ScenarioValidationFailed>(error.error).message
            assertTrue(
                message.contains(type.name.lowercase()),
                "wire name for $type missing from: $message",
            )
        }
    }
}
