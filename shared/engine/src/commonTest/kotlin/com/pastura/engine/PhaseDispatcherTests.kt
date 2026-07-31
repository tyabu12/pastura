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
 * Kotlin sibling of Swift's `PhaseDispatcherTests`.
 *
 * All 14 phase types are registered as of Wave B's completion (#1342), so the tests
 * that used `CONDITIONAL` as the "not ported yet" exemplar are gone. The two that
 * exercise the *error* contract now drive an empty-map dispatcher through the
 * production seam instead — see [anUnregisteredPhaseTypeFailsCleanlyRatherThanCrashing].
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
    fun resolvesTheConditionalHandler() {
        assertIs<ConditionalHandler>(dispatcher.handler(PhaseType.CONDITIONAL))
    }

    @Test
    fun returnsAStableHandlerInstance() {
        // Handlers are stateless values; the dispatcher builds its map once.
        assertTrue(dispatcher.handler(PhaseType.SPEAK_ALL) === dispatcher.handler(PhaseType.SPEAK_ALL))
    }

    @Test
    fun everyPhaseTypeResolvesToAHandler() {
        // Wave B completed at 14/14 (#1342), so this flipped from "exactly 1
        // unported" to "none". It keeps its value in the new polarity: the set is
        // still DERIVED from the dispatcher rather than hand-listed, so it fires on
        // BOTH enum growth (a new PhaseType with no handler) and an accidental
        // de-registration. A hand list cannot disagree with itself and would silently
        // stop guarding registration.
        //
        // Asserted against a DEFAULT-constructed dispatcher on purpose: the seam
        // exercised below could otherwise satisfy this with an injected map, which
        // would measure the fixture instead of the production registration.
        val unported = PhaseType.entries.filter {
            runCatching { dispatcher.handler(it) }.isFailure
        }
        assertEquals(14, PhaseType.entries.size, "the drift ledger's case count is now executable")
        assertEquals(0, unported.size, "unregistered after Wave B completed: $unported")
    }

    @Test
    fun anUnregisteredPhaseTypeFailsCleanlyRatherThanCrashing() {
        // The throw survives 14/14 registration because it defends the recurring
        // window where a PhaseType lands in shared/models before its handler is
        // ported. No real PhaseType reaches it today, so the seam supplies the
        // negative control — without one this guard would be asserted only by its
        // own success case, which proves nothing.
        val empty = PhaseDispatcher(handlers = emptyMap())
        for (type in PhaseType.entries) {
            val error = assertFailsWith<SimulationException>("$type must fail cleanly") {
                empty.handler(type)
            }
            assertIs<SimulationError.ScenarioValidationFailed>(error.error)
        }
    }

    @Test
    fun theErrorNamesThePhaseUsingItsWireNameNotItsKotlinCaseName() {
        // `conditional`, not `CONDITIONAL` — Swift interpolates `phaseType.rawValue`,
        // and a reader comparing the two engines' errors should see the same token.
        val error = assertFailsWith<SimulationException> {
            PhaseDispatcher(handlers = emptyMap()).handler(PhaseType.CONDITIONAL)
        }
        val message = assertIs<SimulationError.ScenarioValidationFailed>(error.error).message
        assertTrue(message.contains("conditional"), "expected the wire name, got: $message")
        assertTrue(!message.contains("CONDITIONAL"), "the Kotlin case name must not leak: $message")
    }

    @Test
    fun wireNamesResolveFromTheSerialDescriptorForEveryCase() {
        // Asserts against the DESCRIPTOR, not against `name.lowercase()`. The
        // earlier version asserted the lowercase derivation — i.e. exactly the
        // coincidence the implementation deliberately rejects — so it passed
        // identically against a `name.lowercase()` impl and pinned nothing.
        //
        // It also used to `continue` past every registered type, so at 14/14 it would
        // have checked NOTHING while still reporting green. Driving the empty-map
        // dispatcher turns that vacuum into full coverage: all 14 cases now throw, so
        // all 14 wire names are actually asserted.
        val empty = PhaseDispatcher(handlers = emptyMap())
        for (type in PhaseType.entries) {
            val error = assertFailsWith<SimulationException> { empty.handler(type) }
            val message = assertIs<SimulationError.ScenarioValidationFailed>(error.error).message
            val fromDescriptor = PhaseType.serializer().descriptor.getElementName(type.ordinal)
            assertTrue(
                message.contains(fromDescriptor),
                "expected @SerialName '$fromDescriptor' for $type in: $message",
            )
        }
    }
}
