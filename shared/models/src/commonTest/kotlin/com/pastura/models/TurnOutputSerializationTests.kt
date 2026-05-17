package com.pastura.models

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Serialization, accessor, and error-path tests for [TurnOutput] and [TurnOutputError].
 */
class TurnOutputSerializationTests {

    // ── Serialization ───────────────────────────────────────────────────────

    @Test
    fun encodeDecodeRoundtrip() {
        val original = TurnOutput(fields = mapOf("statement" to "Hello, world!", "inner_thought" to "I wonder..."))
        val json = Json.encodeToString(original)
        val decoded = Json.decodeFromString<TurnOutput>(json)
        assertEquals(original, decoded)
    }

    @Test
    fun wireShapeContainsFieldsKey() {
        val output = TurnOutput(fields = mapOf("vote" to "Alice", "reason" to "suspicious"))
        val json = Json.encodeToString(output)
        assertTrue(json.contains("\"fields\""), "Wire shape must include 'fields' key; got: $json")
    }

    @Test
    fun emptyFieldsRoundtrip() {
        val original = TurnOutput(fields = emptyMap())
        val json = Json.encodeToString(original)
        val decoded = Json.decodeFromString<TurnOutput>(json)
        assertEquals(original, decoded)
    }

    // ── Typed Accessors ─────────────────────────────────────────────────────

    @Test
    fun typedAccessorsReturnCorrectValues() {
        val output = TurnOutput(
            fields = mapOf(
                "statement" to "I think it was Alice.",
                "vote" to "Alice",
                "action" to "cooperate",
                "inner_thought" to "Hmm...",
                "reason" to "She was suspicious.",
            )
        )
        assertEquals("I think it was Alice.", output.statement)
        assertEquals("Alice", output.vote)
        assertEquals("cooperate", output.action)
        assertEquals("Hmm...", output.innerThought)
        assertEquals("She was suspicious.", output.reason)
    }

    @Test
    fun typedAccessorsReturnNullForMissingFields() {
        val output = TurnOutput(fields = emptyMap())
        assertNull(output.statement)
        assertNull(output.vote)
        assertNull(output.action)
        assertNull(output.innerThought)
        assertNull(output.reason)
    }

    // ── require() ───────────────────────────────────────────────────────────

    @Test
    fun requireReturnsPresentNonEmptyValue() {
        val output = TurnOutput(fields = mapOf("action" to "cooperate"))
        assertEquals("cooperate", output.require("action"))
    }

    @Test
    fun requireThrowsMissingFieldForAbsentKey() {
        val output = TurnOutput(fields = emptyMap())
        val ex = runCatching { output.require("vote") }.exceptionOrNull()
        assertIs<TurnOutputError.MissingField>(ex)
        // assertIs smart-casts `ex` to MissingField — no cast needed.
        assertEquals("vote", ex.key)
    }

    @Test
    fun requireThrowsMissingFieldForEmptyString() {
        val output = TurnOutput(fields = mapOf("statement" to ""))
        val ex = runCatching { output.require("statement") }.exceptionOrNull()
        assertIs<TurnOutputError.MissingField>(ex)
    }

    // ── primaryText() ───────────────────────────────────────────────────────

    @Test
    fun primaryTextForVoteWithReason() {
        val output = TurnOutput(fields = mapOf("vote" to "Alice", "reason" to "suspicious"))
        assertEquals("→ Alice (suspicious)", output.primaryText(PhaseType.VOTE))
    }

    @Test
    fun primaryTextForVoteWithoutReason() {
        val output = TurnOutput(fields = mapOf("vote" to "Bob"))
        assertEquals("→ Bob", output.primaryText(PhaseType.VOTE))
    }

    @Test
    fun primaryTextForVoteWithMissingVote() {
        val output = TurnOutput(fields = emptyMap())
        assertNull(output.primaryText(PhaseType.VOTE))
    }

    @Test
    fun primaryTextForSpeakAll() {
        val output = TurnOutput(fields = mapOf("statement" to "Good morning!"))
        assertEquals("Good morning!", output.primaryText(PhaseType.SPEAK_ALL))
    }

    @Test
    fun primaryTextForChoose() {
        val output = TurnOutput(fields = mapOf("action" to "cooperate"))
        assertEquals("cooperate", output.primaryText(PhaseType.CHOOSE))
    }

    @Test
    fun primaryTextForCodePhaseIsNull() {
        val output = TurnOutput(fields = mapOf("statement" to "anything"))
        assertNull(output.primaryText(PhaseType.SCORE_CALC))
        assertNull(output.primaryText(PhaseType.ASSIGN))
        assertNull(output.primaryText(PhaseType.ELIMINATE))
    }
}
