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
 */
class PhaseTypeTests {

    @Test
    fun allCasesEncodeToSwiftRawValueStrings() {
        val expectations = mapOf(
            PhaseType.SPEAK_ALL to "\"speak_all\"",
            PhaseType.SPEAK_EACH to "\"speak_each\"",
            PhaseType.VOTE to "\"vote\"",
            PhaseType.CHOOSE to "\"choose\"",
            PhaseType.SCORE_CALC to "\"score_calc\"",
            PhaseType.ASSIGN to "\"assign\"",
            PhaseType.ELIMINATE to "\"eliminate\"",
            PhaseType.SUMMARIZE to "\"summarize\"",
            PhaseType.CONDITIONAL to "\"conditional\"",
            PhaseType.EVENT_INJECT to "\"event_inject\"",
        )
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
    }

    @Test
    fun requiresLLMFalseForCodePhases() {
        // CONDITIONAL: handler evaluates DSL expression, no LLM call itself.
        // EVENT_INJECT: picks a random string from extraData, no LLM call.
        assertFalse(PhaseType.SCORE_CALC.requiresLLM)
        assertFalse(PhaseType.ASSIGN.requiresLLM)
        assertFalse(PhaseType.ELIMINATE.requiresLLM)
        assertFalse(PhaseType.SUMMARIZE.requiresLLM)
        assertFalse(PhaseType.CONDITIONAL.requiresLLM)
        assertFalse(PhaseType.EVENT_INJECT.requiresLLM)
    }
}
