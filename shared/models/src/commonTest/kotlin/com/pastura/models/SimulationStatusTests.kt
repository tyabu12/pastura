package com.pastura.models

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * JSON roundtrip tests for [SimulationStatus].
 *
 * Wire shapes must match Swift's `Codable` default for `enum SimulationStatus: String`
 * — each case encodes to its raw value string (`"running"`, `"paused"`, etc.).
 */
class SimulationStatusTests {

    @Test
    fun allCasesEncodeToSwiftRawValueStrings() {
        val expectations = mapOf(
            SimulationStatus.RUNNING to "\"running\"",
            SimulationStatus.PAUSED to "\"paused\"",
            SimulationStatus.COMPLETED to "\"completed\"",
            SimulationStatus.FAILED to "\"failed\"",
            SimulationStatus.CANCELLED to "\"cancelled\"",
        )
        expectations.forEach { (case, expectedJson) ->
            assertEquals(expectedJson, Json.encodeToString(case), "Wire mismatch for $case")
        }
    }

    @Test
    fun allCasesRoundtripPreservesEquality() {
        SimulationStatus.entries.forEach { original ->
            val decoded = Json.decodeFromString<SimulationStatus>(Json.encodeToString(original))
            assertEquals(original, decoded, "Roundtrip failed for $original")
        }
    }
}
