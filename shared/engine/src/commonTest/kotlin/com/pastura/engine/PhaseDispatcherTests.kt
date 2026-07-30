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
 * Kotlin sibling of Swift's `PhaseDispatcherTests`, scoped to the handlers this
 * port has registered so far.
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
    fun resolvesTheScoreCalcHandler() {
        assertIs<ScoreCalcHandler>(dispatcher.handler(PhaseType.SCORE_CALC))
    }

    @Test
    fun resolvesTheRelationshipUpdateHandler() {
        assertIs<RelationshipUpdateHandler>(dispatcher.handler(PhaseType.RELATIONSHIP_UPDATE))
    }

    @Test
    fun resolvesTheReflectHandler() {
        assertIs<ReflectHandler>(dispatcher.handler(PhaseType.REFLECT))
    }

    @Test
    fun resolvesTheVoteHandler() {
        assertIs<VoteHandler>(dispatcher.handler(PhaseType.VOTE))
    }

    @Test
    fun resolvesTheWhisperHandler() {
        assertIs<WhisperHandler>(dispatcher.handler(PhaseType.WHISPER))
    }

    @Test
    fun resolvesTheChooseHandler() {
        assertIs<ChooseHandler>(dispatcher.handler(PhaseType.CHOOSE))
    }

    @Test
    fun resolvesTheSpeakEachHandler() {
        assertIs<SpeakEachHandler>(dispatcher.handler(PhaseType.SPEAK_EACH))
    }

    @Test
    fun resolvesTheNarrateHandler() {
        assertIs<NarrateHandler>(dispatcher.handler(PhaseType.NARRATE))
    }

    @Test
    fun returnsAStableHandlerInstance() {
        // Handlers are stateless values; the dispatcher builds its map once.
        assertTrue(dispatcher.handler(PhaseType.SPEAK_ALL) === dispatcher.handler(PhaseType.SPEAK_ALL))
    }

    @Test
    fun throwsForAPhaseTypeThisSliceHasNotPorted() {
        val error = assertFailsWith<SimulationException> { dispatcher.handler(PhaseType.CONDITIONAL) }
        assertIs<SimulationError.ScenarioValidationFailed>(error.error)
    }

    @Test
    fun theErrorNamesThePhaseUsingItsWireNameNotItsKotlinCaseName() {
        // `conditional`, not `CONDITIONAL` — Swift interpolates `phaseType.rawValue`,
        // and a reader comparing the two engines' errors should see the same token.
        // The exemplar is CONDITIONAL because it is the SOLE remaining unported
        // handler (Wave B is 13/14), so no further repoint is possible: the next port
        // to land is Conditional itself, and that PR retires this exemplar rather than
        // moving it.
        val error = assertFailsWith<SimulationException> { dispatcher.handler(PhaseType.CONDITIONAL) }
        val message = assertIs<SimulationError.ScenarioValidationFailed>(error.error).message
        assertTrue(message.contains("conditional"), "expected the wire name, got: $message")
        assertTrue(!message.contains("CONDITIONAL"), "the Kotlin case name must not leak: $message")
    }

    @Test
    fun everyUnportedPhaseTypeFailsCleanlyRatherThanCrashing() {
        // A Stage-3 gap must read as a gap. Iterating allCases also means a NEW
        // PhaseType added to Models cannot silently reach dispatch unhandled.
        // DERIVED from the dispatcher, not a hand-written exclusion list. A hand
        // list cannot disagree with itself, so it silently stops guarding
        // registration: de-registering a ported handler just moves that case into
        // the excluded set, leaving this test green. Deriving makes the count below
        // fire on BOTH enum growth and an accidental de-registration.
        val unported = PhaseType.entries.filter {
            runCatching { dispatcher.handler(it) }.isFailure
        }
        assertEquals(14, PhaseType.entries.size, "the drift ledger's case count is now executable")
        assertEquals(1, unported.size, "see the #501 drift ledger")
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
