package com.pastura.engine

import com.pastura.models.PhaseType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Handler-anchored tests for [PlaceholderAvailability] — mirrors
 * `Pastura/PasturaTests/Engine/PlaceholderAvailabilityTests.swift` 1:1 (21
 * test functions). Each per-row test names the handler it mirrors so a
 * handler change that drifts the map fails here with a legible pointer. The
 * union test is the ADR's phantom/missing-token maintenance guard.
 *
 * ## Condition-4 perturbation record
 *
 * ADR-023 §12 condition 4 (perturbation sensitivity), measured at porting time
 * against a 21-test baseline green before the first mutation and after the
 * last revert:
 *
 * | # | Mutation of `PlaceholderAvailability.kt` | Reddened |
 * |---|---|---|
 * | 1 | moved `crossPhaseStateReadable` above `producerMap` | **compile error**, not a test: `Variable 'producerMap' must be initialized.` |
 * | 2 | added `whisperSelfInjected` to the `chooseRoundRobin == false` branch | `chooseIndividualOmitsWhisperChannel` |
 * | 3 | dropped `WHISPER` from `producerMap["my_mood"]` | `moodProducedByAllLLMPhases` |
 * | 4 | dropped `assigned_topic` from `assignProduced` | `unionOfSuppliedEqualsEngineSuppliedPlusDocumentedDelta`, `everyEngineSuppliedTokenIsSuppliedBySomePhase`, `everyProducedTokenIsInItsProducersSuppliedSet` |
 *
 * Mutation 4 was added at review so that three mutations are test-detected;
 * mutation 1 is a compiler detection.
 *
 * Mutation 1 is the reason the value pin in
 * [crossPhaseStateReadableIsProducerTokensMinusPerPersona] is *not* the
 * declaration-order guard it was first planned as: an initialiser that reads
 * a later-declared `object` property is a Kotlin frontend error, so a wrong
 * order cannot reach the test at all — the pin's job is the derived
 * contents, which no compiler checks.
 */
class PlaceholderAvailabilityTests {

    // MARK: - Union guard (ADR-024 maintenance point)

    @Test
    fun unionOfSuppliedEqualsEngineSuppliedPlusDocumentedDelta() {
        val union = mutableSetOf<String>()
        for (phaseType in PhaseType.entries) {
            union.addAll(PlaceholderAvailability.supplied(phaseType, chooseRoundRobin = true))
            union.addAll(PlaceholderAvailability.supplied(phaseType, chooseRoundRobin = false))
        }
        val expected = PromptPlaceholders.engineSupplied.union(
            PlaceholderAvailability.tokensBeyondEngineSupplied
        )
        assertEquals(expected, union)
    }

    @Test
    fun everyEngineSuppliedTokenIsSuppliedBySomePhase() {
        val union = mutableSetOf<String>()
        for (phaseType in PhaseType.entries) {
            union.addAll(PlaceholderAvailability.supplied(phaseType, chooseRoundRobin = true))
        }
        // No engine-supplied token is orphaned (the "missing token" half of the guard).
        assertTrue(union.containsAll(PromptPlaceholders.engineSupplied))
    }

    @Test
    fun deltaTokensAreDisjointFromEngineSupplied() {
        // The delta names tokens engineSupplied does NOT carry -- if one were added
        // there, this catches the stale duplication.
        assertTrue(
            PlaceholderAvailability.tokensBeyondEngineSupplied
                .none { PromptPlaceholders.engineSupplied.contains(it) }
        )
    }

    // MARK: - Cross-phase readable set (#920 B editor-hint source)

    /**
     * [PlaceholderAvailability.crossPhaseStateReadable] is the producer-gated
     * tokens minus the per-persona / whisper injected forms — the
     * state-variable tokens any LLM phase's prompt can read. Pins the
     * derived value so a `producerMap` / `perPersonaInjected` change that
     * shifts it fails here.
     *
     * This pin is deliberately *not* a declaration-order guard for
     * [PlaceholderAvailability.producerMap] /
     * [PlaceholderAvailability.crossPhaseStateReadable], although it was
     * first planned as one: declaring `crossPhaseStateReadable` first is a
     * compile error (`Variable 'producerMap' must be initialized.` — measured
     * as condition-4 mutation 1 in the class KDoc), not a silent empty set,
     * so the order never reaches a test. What no compiler checks is the
     * derived *contents*, and that is what this value pin holds.
     */
    @Test
    fun crossPhaseStateReadableIsProducerTokensMinusPerPersona() {
        assertEquals(
            setOf("assigned_topic", "wolf_name", "vote_results", "current_event"),
            PlaceholderAvailability.crossPhaseStateReadable
        )
    }

    // MARK: - Vote (VoteHandler)

    @Test
    fun candidatesSuppliedByVoteOnly() {
        for (phaseType in PhaseType.entries) {
            val hasCandidates =
                PlaceholderAvailability
                    .supplied(phaseType, chooseRoundRobin = true)
                    .contains("candidates")
            assertEquals(phaseType == PhaseType.VOTE, hasCandidates)
        }
    }

    @Test
    fun voteResultsSuppliedByVote() {
        assertTrue(
            PlaceholderAvailability.supplied(PhaseType.VOTE, chooseRoundRobin = false)
                .contains("vote_results")
        )
    }

    // MARK: - Choose (ChooseHandler round-robin qualifier)

    @Test
    fun opponentNameSuppliedByChooseRoundRobinOnly() {
        assertTrue(
            PlaceholderAvailability.supplied(PhaseType.CHOOSE, chooseRoundRobin = true)
                .contains("opponent_name")
        )
        assertFalse(
            PlaceholderAvailability.supplied(PhaseType.CHOOSE, chooseRoundRobin = false)
                .contains("opponent_name")
        )
        // Absent from every non-choose phase, under either qualifier value.
        for (phaseType in PhaseType.entries) {
            if (phaseType == PhaseType.CHOOSE) continue
            assertFalse(
                PlaceholderAvailability.supplied(phaseType, chooseRoundRobin = true)
                    .contains("opponent_name")
            )
        }
    }

    @Test
    fun chooseIndividualOmitsWhisperChannel() {
        // executeIndividual does not call injectWhispers.
        assertTrue(
            PlaceholderAvailability.supplied(PhaseType.CHOOSE, chooseRoundRobin = true)
                .contains("my_whispers")
        )
        assertFalse(
            PlaceholderAvailability.supplied(PhaseType.CHOOSE, chooseRoundRobin = false)
                .contains("my_whispers")
        )
    }

    // MARK: - Whisper (WhisperHandler in-phase tokens)

    @Test
    fun whisperInPhaseTokensSuppliedByWhisperOnly() {
        for (token in listOf("whisper_partner", "whisper_exchange")) {
            for (phaseType in PhaseType.entries) {
                val supplied =
                    PlaceholderAvailability
                        .supplied(phaseType, chooseRoundRobin = true)
                        .contains(token)
                assertEquals(phaseType == PhaseType.WHISPER, supplied)
            }
        }
    }

    // MARK: - Per-persona tokens absent from summarize / code phases (rule R12)

    @Test
    fun perPersonaTokensAbsentFromSummarizeAndCodePhases() {
        val perPersona = listOf("assigned", "my_notes", "my_whispers", "relationships", "my_mood")
        // summarize + every non-LLM phase except the producers that write these vars
        // downstream (assign -> assigned, relationship_update -> relationships).
        val codeLike = listOf(
            PhaseType.SUMMARIZE, PhaseType.SCORE_CALC, PhaseType.ELIMINATE,
            PhaseType.CONDITIONAL, PhaseType.EVENT_INJECT
        )
        for (phaseType in codeLike) {
            val supplied = PlaceholderAvailability.supplied(phaseType, chooseRoundRobin = true)
            for (token in perPersona) {
                assertFalse(supplied.contains(token), "$token must not be injected in $phaseType")
            }
        }
    }

    @Test
    fun summarizeSuppliesPairingTokensNotPerPersona() {
        val supplied = PlaceholderAvailability.supplied(PhaseType.SUMMARIZE, chooseRoundRobin = true)
        assertTrue(supplied.contains("agent1"))
        assertTrue(supplied.contains("action1"))
        assertTrue(supplied.contains("scoreboard"))
        assertFalse(supplied.contains("assigned"))
        assertFalse(supplied.contains("relationships"))
    }

    @Test
    fun perPersonaTokensPresentInLLMPhases() {
        // The four inject{Assigned,Notes,Relationships}-always phases plus vote.
        for (phaseType in listOf(
            PhaseType.SPEAK_ALL, PhaseType.SPEAK_EACH, PhaseType.VOTE,
            PhaseType.REFLECT, PhaseType.WHISPER
        )) {
            val supplied = PlaceholderAvailability.supplied(phaseType, chooseRoundRobin = true)
            for (token in listOf("assigned", "my_notes", "relationships", "my_mood")) {
                assertTrue(supplied.contains(token), "$token missing from $phaseType")
            }
        }
    }

    // MARK: - Producer relation

    @Test
    fun assignProducesAssignedFamily() {
        for (token in listOf("assigned", "assigned_word", "assigned_topic", "wolf_name")) {
            assertEquals(
                setOf(PhaseType.ASSIGN),
                PlaceholderAvailability.producers(token),
                "producer of $token"
            )
        }
    }

    @Test
    fun reflectProducesMyNotes() {
        assertEquals(setOf(PhaseType.REFLECT), PlaceholderAvailability.producers("my_notes"))
    }

    @Test
    fun whisperProducesMyWhispers() {
        assertEquals(setOf(PhaseType.WHISPER), PlaceholderAvailability.producers("my_whispers"))
    }

    @Test
    fun relationshipUpdateProducesRelationships() {
        assertEquals(
            setOf(PhaseType.RELATIONSHIP_UPDATE),
            PlaceholderAvailability.producers("relationships")
        )
    }

    @Test
    fun voteProducesVoteResults() {
        assertEquals(setOf(PhaseType.VOTE), PlaceholderAvailability.producers("vote_results"))
    }

    @Test
    fun eventInjectProducesCurrentEvent() {
        assertEquals(
            setOf(PhaseType.EVENT_INJECT),
            PlaceholderAvailability.producers("current_event")
        )
    }

    // #913: mood is an intentional over-approximation -- any LLM phase can declare
    // a `mood` output field, so all six are listed as producers (unlike the
    // single-producer entries above). This asserts the full set so a future edit
    // that narrows or drops one is caught.
    @Test
    fun moodProducedByAllLLMPhases() {
        assertEquals(
            setOf(
                PhaseType.SPEAK_ALL, PhaseType.SPEAK_EACH, PhaseType.VOTE,
                PhaseType.CHOOSE, PhaseType.REFLECT, PhaseType.WHISPER
            ),
            PlaceholderAvailability.producers("my_mood")
        )
    }

    @Test
    fun nonProducerGatedTokensReturnNil() {
        // Always-resolvable-in-supplying-phase tokens are not producer-gated.
        for (token in listOf("scoreboard", "conversation_log", "current_round", "candidates", "opponent_name")) {
            assertNull(PlaceholderAvailability.producers(token), "$token should be ungated")
        }
    }

    @Test
    fun everyProducedTokenIsInItsProducersSuppliedSet() {
        // Cross-check: a producer's output token appears in that producer's supplied set.
        for ((token, phaseTypes) in PlaceholderAvailability.producerMap) {
            for (phaseType in phaseTypes) {
                assertTrue(
                    PlaceholderAvailability.supplied(phaseType, chooseRoundRobin = true).contains(token),
                    "$phaseType produces $token but does not supply it"
                )
            }
        }
    }
}
