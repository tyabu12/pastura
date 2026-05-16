package com.pastura.models

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Kotlin-side JSON roundtrip tests for [PairingStrategy] (W1 pilot —
 * added per code-reviewer warning #3 to exercise raw-value-string enum
 * serialization surface).
 *
 * **W2 canonicalizer canary:** Swift's `PairingStrategy` (`enum
 * PairingStrategy: String, Codable { case roundRobin = "round_robin" }`)
 * encodes the same logical value as the JSON string `"round_robin"`.
 * Kotlin's idiomatic mapping uses `@SerialName("round_robin")` on an
 * uppercase-enum-constant. The wire shape matches; the language-level
 * Kotlin constant is named differently (`ROUND_ROBIN`). W2 canonicalizer
 * must verify wire-shape equivalence holds across the full Phase /
 * AssignTarget / ... enum population.
 */
class PairingStrategyTests {

    @Test
    fun roundRobinSerializesToSwiftRawValueString() {
        val json = Json.encodeToString(PairingStrategy.ROUND_ROBIN)
        // Swift's `Codable` default for `enum Foo: String` emits the raw
        // value as a JSON string. Kotlin's `@SerialName` overrides the
        // default uppercase-constant-name. Wire shape matches.
        assertEquals("\"round_robin\"", json)
    }

    @Test
    fun encodeDecodeRoundtripPreservesEquality() {
        val original = PairingStrategy.ROUND_ROBIN
        val json = Json.encodeToString(original)
        val decoded = Json.decodeFromString<PairingStrategy>(json)
        assertEquals(original, decoded)
    }
}
