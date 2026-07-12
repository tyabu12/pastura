package com.pastura.models

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Roundtrip + discriminator wire-shape tests for [SimulationError].
 *
 * Each case asserts:
 * 1. Encode produces the expected discriminator (matches Swift case name).
 * 2. Roundtrip preserves Equatable identity.
 *
 * Unit cases (RetriesExhausted, ModelNotLoaded, Cancelled) carry only the
 * discriminator. Cases with payload (ScenarioValidationFailed,
 * LlmGenerationFailed, JsonParseFailed) carry their associated string.
 */
class SimulationErrorSerializationTests {

    private val json = Json { ignoreUnknownKeys = true }

    private inline fun <reified T : SimulationError> assertRoundtripAndDiscriminator(
        original: T,
        expectedSerialName: String,
    ) {
        val encoded = json.encodeToString<SimulationError>(original)
        assertTrue(
            encoded.contains("\"type\":\"$expectedSerialName\""),
            "Wire shape missing discriminator '$expectedSerialName' in $encoded",
        )
        val decoded = json.decodeFromString<SimulationError>(encoded)
        assertEquals(original, decoded)
    }

    @Test
    fun scenarioValidationFailedRoundtrip() {
        assertRoundtripAndDiscriminator(
            SimulationError.ScenarioValidationFailed(message = "agentCount mismatch"),
            "scenarioValidationFailed",
        )
    }

    @Test
    fun llmGenerationFailedRoundtrip() {
        assertRoundtripAndDiscriminator(
            SimulationError.LlmGenerationFailed(description = "connection refused"),
            "llmGenerationFailed",
        )
    }

    @Test
    fun jsonParseFailedRoundtripWithLargeRaw() {
        // Swift's LocalizedError truncates at 200 chars for display, but the
        // wire shape carries the full raw — Kotlin port preserves the same
        // contract since the LocalizedError extension is Swift-only.
        val largeRaw = "x".repeat(500)
        assertRoundtripAndDiscriminator(
            SimulationError.JsonParseFailed(raw = largeRaw),
            "jsonParseFailed",
        )
    }

    @Test
    fun unitCasesAreDiscriminatorOnly() {
        // Encode unit cases and verify they carry no payload beyond the
        // discriminator — equivalent to Swift's `case retriesExhausted` etc.
        // which auto-encode as `{"retriesExhausted":{}}` per Swift's
        // Codable default (the empty payload form). Kotlin's equivalent is
        // `{"type":"retriesExhausted"}` (single discriminator key).
        val unitCases = listOf(
            SimulationError.RetriesExhausted to "retriesExhausted",
            SimulationError.ModelNotLoaded to "modelNotLoaded",
            SimulationError.Cancelled to "cancelled",
        )
        for ((case, name) in unitCases) {
            val encoded = json.encodeToString<SimulationError>(case)
            assertEquals("""{"type":"$name"}""", encoded)
            val decoded = json.decodeFromString<SimulationError>(encoded)
            assertEquals(case, decoded)
        }
    }
}
