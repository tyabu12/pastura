package com.pastura.models

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * JSON roundtrip tests for [ScoreCalcLogic].
 *
 * Wire shapes must match Swift's `Codable` default for `enum ScoreCalcLogic: String`
 * — each case encodes to its raw value string (`"prisoners_dilemma"`, etc.).
 *
 * Swift↔Kotlin parity gate for the enum (ADR-023 §12 condition 2): a new Kotlin
 * case without its Swift-matching `@SerialName` reddens the completeness check.
 */
class ScoreCalcLogicTests {

    @Test
    fun allCasesEncodeToSwiftRawValueStrings() {
        val expectations = mapOf(
            ScoreCalcLogic.PRISONERS_DILEMMA to "\"prisoners_dilemma\"",
            ScoreCalcLogic.VOTE_TALLY to "\"vote_tally\"",
            ScoreCalcLogic.WORDWOLF_JUDGE to "\"wordwolf_judge\"",
            ScoreCalcLogic.EVENT_REACTIVE to "\"event_reactive\"",
            ScoreCalcLogic.PAIRWISE_PAYOFF to "\"pairwise_payoff\"",
        )
        assertEquals(ScoreCalcLogic.entries.size, expectations.size, "Expectation map missing a case")
        expectations.forEach { (case, expectedJson) ->
            assertEquals(expectedJson, Json.encodeToString(case), "Wire mismatch for $case")
        }
    }

    @Test
    fun allCasesRoundtripPreservesEquality() {
        ScoreCalcLogic.entries.forEach { original ->
            val decoded = Json.decodeFromString<ScoreCalcLogic>(Json.encodeToString(original))
            assertEquals(original, decoded, "Roundtrip failed for $original")
        }
    }
}
