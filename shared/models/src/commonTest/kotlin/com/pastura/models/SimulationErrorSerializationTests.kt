package com.pastura.models

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
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

    // ── turnFailureLimitReached (ADR-021 D4 breaker) — PR0-b ─────────────

    @Test
    fun turnFailureLimitReachedRoundtrip() {
        assertRoundtripAndDiscriminator(
            SimulationError.TurnFailureLimitReached(consecutiveCount = 3),
            "turnFailureLimitReached",
        )
    }

    // ── Case-mirror completeness (substitute for golden JSON parity) ─────

    /**
     * The substitute parity instrument #501 mandates for [SimulationError],
     * which is not `Codable` on Swift (`Error, Sendable, Equatable`) so golden
     * JSON parity is the wrong instrument (PR0-b carve-out — see #501).
     *
     * Pins the Kotlin case set against [SWIFT_ERROR_CASES] (hardcoded from
     * `Pastura/Pastura/Models/SimulationEvent.swift:SimulationError`, 7 cases),
     * discriminator read from real encoded JSON (swap-safe). Unlike
     * [SimulationEvent], `SimulationError` has no production exhaustive `when`,
     * so [assertHandledExhaustively] below is the sole compile-time canary: a
     * newly-added subclass fails to compile until handled there.
     *
     * Honest residual: a *future* Swift-side addition is not auto-detected
     * (no `sealedSubclasses` in commonMain); [SWIFT_ERROR_CASES] is updated by
     * hand, as PR0-b does.
     */
    @Test
    fun caseSetMirrorsSwift() {
        val actual = errorSamples().map(::discriminatorOf).toSet()
        assertEquals(SWIFT_ERROR_CASES, actual)
        assertEquals(SWIFT_ERROR_CASES.size, errorSamples().size)
        errorSamples().forEach(::assertHandledExhaustively)
    }

    private fun discriminatorOf(error: SimulationError): String =
        json.encodeToJsonElement(SimulationError.serializer(), error)
            .jsonObject["type"]!!.jsonPrimitive.content

    private fun assertHandledExhaustively(error: SimulationError) {
        when (error) {
            is SimulationError.ScenarioValidationFailed -> Unit
            is SimulationError.LlmGenerationFailed -> Unit
            is SimulationError.JsonParseFailed -> Unit
            is SimulationError.RetriesExhausted -> Unit
            is SimulationError.ModelNotLoaded -> Unit
            is SimulationError.Cancelled -> Unit
            is SimulationError.TurnFailureLimitReached -> Unit
        }
    }

    private fun errorSamples(): List<SimulationError> = listOf(
        SimulationError.ScenarioValidationFailed(message = "m"),
        SimulationError.LlmGenerationFailed(description = "d"),
        SimulationError.JsonParseFailed(raw = "r"),
        SimulationError.RetriesExhausted,
        SimulationError.ModelNotLoaded,
        SimulationError.Cancelled,
        SimulationError.TurnFailureLimitReached(consecutiveCount = 3),
    )

    private companion object {
        /**
         * The 7 `SimulationError` cases on the Swift side, by wire
         * discriminator. Kept in sync with
         * `Pastura/Pastura/Models/SimulationEvent.swift:SimulationError` by
         * hand — see [caseSetMirrorsSwift]'s residual note.
         */
        val SWIFT_ERROR_CASES: Set<String> = setOf(
            "scenarioValidationFailed", "llmGenerationFailed", "jsonParseFailed",
            "retriesExhausted", "modelNotLoaded", "cancelled",
            "turnFailureLimitReached",
        )
    }
}
