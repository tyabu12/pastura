package com.pastura.models

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * JSON roundtrip tests and `requiresLLM` invariants for [PhaseType].
 *
 * Wire shapes must match Swift's `Codable` default for `enum PhaseType: String`
 * — each case encodes to its raw value string (e.g. `"speak_all"`, `"vote"`).
 *
 * These tests are the Swift↔Kotlin parity gate for the enum (ADR-023 §12
 * condition 2): the expectation map pins every case's wire string to Swift's
 * raw value, and the `requiresLLM` assertions pin the classification — a Kotlin
 * case added without its Swift-matching `@SerialName` or with the wrong
 * `requiresLLM` arm reddens here rather than shipping latently.
 */
class PhaseTypeTests {

    @Test
    fun allCasesEncodeToSwiftRawValueStrings() {
        val expectations = mapOf(
            PhaseType.SPEAK_ALL to "\"speak_all\"",
            PhaseType.SPEAK_EACH to "\"speak_each\"",
            PhaseType.VOTE to "\"vote\"",
            PhaseType.CHOOSE to "\"choose\"",
            PhaseType.REFLECT to "\"reflect\"",
            PhaseType.WHISPER to "\"whisper\"",
            PhaseType.SCORE_CALC to "\"score_calc\"",
            PhaseType.ASSIGN to "\"assign\"",
            PhaseType.ELIMINATE to "\"eliminate\"",
            PhaseType.SUMMARIZE to "\"summarize\"",
            PhaseType.CONDITIONAL to "\"conditional\"",
            PhaseType.EVENT_INJECT to "\"event_inject\"",
            PhaseType.RELATIONSHIP_UPDATE to "\"relationship_update\"",
            PhaseType.NARRATE to "\"narrate\"",
        )
        // Completeness: every case must be pinned, so a new Kotlin case with no
        // Swift-matching expectation reddens instead of slipping through.
        assertEquals(PhaseType.entries.size, expectations.size, "Expectation map missing a case")
        expectations.forEach { (case, expectedJson) ->
            assertEquals(expectedJson, Json.encodeToString(case), "Wire mismatch for $case")
        }
    }

    @Test
    fun allCasesRoundtripPreservesEquality() {
        PhaseType.entries.forEach { original ->
            val decoded = Json.decodeFromString<PhaseType>(Json.encodeToString(original))
            assertEquals(original, decoded, "Roundtrip failed for $original")
        }
    }

    @Test
    fun requiresLLMTrueForLLMPhases() {
        assertTrue(PhaseType.SPEAK_ALL.requiresLLM)
        assertTrue(PhaseType.SPEAK_EACH.requiresLLM)
        assertTrue(PhaseType.VOTE.requiresLLM)
        assertTrue(PhaseType.CHOOSE.requiresLLM)
        assertTrue(PhaseType.REFLECT.requiresLLM)
        assertTrue(PhaseType.WHISPER.requiresLLM)
        // NARRATE: one commentator inference per round (#909), still an LLM phase.
        assertTrue(PhaseType.NARRATE.requiresLLM)
    }

    @Test
    fun requiresLLMFalseForCodePhases() {
        // CONDITIONAL: handler evaluates DSL expression, no LLM call itself.
        // EVENT_INJECT: picks a random string from extraData, no LLM call.
        // RELATIONSHIP_UPDATE: deterministic affinity update from history (#910).
        assertFalse(PhaseType.SCORE_CALC.requiresLLM)
        assertFalse(PhaseType.ASSIGN.requiresLLM)
        assertFalse(PhaseType.ELIMINATE.requiresLLM)
        assertFalse(PhaseType.SUMMARIZE.requiresLLM)
        assertFalse(PhaseType.CONDITIONAL.requiresLLM)
        assertFalse(PhaseType.EVENT_INJECT.requiresLLM)
        assertFalse(PhaseType.RELATIONSHIP_UPDATE.requiresLLM)
    }
}
