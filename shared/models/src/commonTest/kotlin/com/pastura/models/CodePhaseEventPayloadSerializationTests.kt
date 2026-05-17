package com.pastura.models

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Roundtrip + discriminator wire-shape tests for [CodePhaseEventPayload].
 *
 * Production-relevance note: unlike [SimulationEvent], this type IS
 * persisted (`code_phase_events.payloadJSON`). The Kotlin wire shape
 * (kotlinx polymorphism with `type` discriminator) diverges from Swift's
 * auto-synth `{"<caseName>":<payload>}` form — documented in the type
 * kdoc and flagged for PR-B canonicalizer.
 */
class CodePhaseEventPayloadSerializationTests {

    private val json = Json { ignoreUnknownKeys = true }

    private inline fun <reified T : CodePhaseEventPayload> assertRoundtripAndDiscriminator(
        original: T,
        expectedSerialName: String,
    ) {
        val encoded = json.encodeToString<CodePhaseEventPayload>(original)
        assertTrue(
            encoded.contains("\"type\":\"$expectedSerialName\""),
            "Wire shape missing discriminator '$expectedSerialName' in $encoded",
        )
        val decoded = json.decodeFromString<CodePhaseEventPayload>(encoded)
        assertEquals(original, decoded)
    }

    @Test
    fun eliminationRoundtrip() {
        assertRoundtripAndDiscriminator(
            CodePhaseEventPayload.Elimination(agent = "Carol", voteCount = 3),
            "elimination",
        )
    }

    @Test
    fun scoreUpdateRoundtrip() {
        assertRoundtripAndDiscriminator(
            CodePhaseEventPayload.ScoreUpdate(scores = mapOf("Alice" to 3, "Bob" to 5)),
            "scoreUpdate",
        )
    }

    @Test
    fun summaryRoundtrip() {
        assertRoundtripAndDiscriminator(
            CodePhaseEventPayload.Summary(text = "Round 1 complete."),
            "summary",
        )
    }

    @Test
    fun voteResultsRoundtrip() {
        assertRoundtripAndDiscriminator(
            CodePhaseEventPayload.VoteResults(
                votes = mapOf("Alice" to "Bob", "Bob" to "Alice"),
                tallies = mapOf("Alice" to 1, "Bob" to 1),
            ),
            "voteResults",
        )
    }

    @Test
    fun pairingResultRoundtrip() {
        assertRoundtripAndDiscriminator(
            CodePhaseEventPayload.PairingResult(
                agent1 = "Alice",
                action1 = "cooperate",
                agent2 = "Bob",
                action2 = "betray",
            ),
            "pairingResult",
        )
    }

    @Test
    fun assignmentRoundtrip() {
        assertRoundtripAndDiscriminator(
            CodePhaseEventPayload.Assignment(agent = "Alice", value = "wolf"),
            "assignment",
        )
    }

    @Test
    fun eventInjectedHandlesHitAndMiss() {
        // Hit.
        assertRoundtripAndDiscriminator(
            CodePhaseEventPayload.EventInjected(event = "earthquake"),
            "eventInjected",
        )
        // Miss — explicit null preserves the "rolled and lost" signal per kdoc.
        assertRoundtripAndDiscriminator(
            CodePhaseEventPayload.EventInjected(event = null),
            "eventInjected",
        )
    }
}
