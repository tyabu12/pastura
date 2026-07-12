package com.pastura.models

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Kotlin-side JSON roundtrip tests for [Pairing] (W1 2nd pilot per critic
 * Axis 5 in Issue #220 — Optional null-vs-omit canary).
 *
 * **Scope:** same as [PersonaSerializationTests] plus null-emission semantics
 * for `String?` fields. Does NOT validate Swift↔Kotlin H2 roundtrip.
 */
class PairingSerializationTests {

    @Test
    fun encodeDecodeRoundtripWithoutActions() {
        val original = Pairing(agent1 = "Alice", agent2 = "Bob")
        val json = Json.encodeToString(original)
        val decoded = Json.decodeFromString<Pairing>(json)
        assertEquals(original, decoded)
        assertNull(decoded.action1)
        assertNull(decoded.action2)
    }

    @Test
    fun encodeDecodeRoundtripWithActions() {
        val original = Pairing(
            agent1 = "Alice",
            agent2 = "Bob",
            action1 = "cooperate",
            action2 = "defect",
        )
        val json = Json.encodeToString(original)
        val decoded = Json.decodeFromString<Pairing>(json)
        assertEquals(original, decoded)
    }

    @Test
    fun nullOptionalsAreOmittedByDefault() {
        // CANARY for W2 canonicalizer design (critic Axis 5) — and a real
        // H2-relevant divergence surfaced by the W1 pilot.
        //
        // kotlinx.serialization's default behavior: properties whose value
        // equals their default are NOT encoded. `action2 = null` matches
        // the `= null` default, so it is OMITTED from JSON output.
        //
        // Swift Codable's default: nil IS emitted as `"action2":null`.
        //
        // **The two platforms produce different JSON shapes for the same
        // logical value.** H2 canonicalizer (W2) must reconcile via one
        // of two paths:
        //   (a) Kotlin: `Json { encodeDefaults = true }` makes Kotlin emit
        //       null (matches Swift Codable default), OR
        //   (b) Swift: custom `encode(to:)` overrides skip nil keys
        //       (matches Kotlin default).
        //
        // W2 decision deferred until the full 17-type audit; this test
        // pins the current default so any platform-level behavior change
        // surfaces here first.
        val withOneAction = Pairing(agent1 = "A", agent2 = "B", action1 = "cooperate")
        val json = Json.encodeToString(withOneAction)
        assertEquals(
            """{"agent1":"A","agent2":"B","action1":"cooperate"}""",
            json,
        )
    }

    @Test
    fun encodeDecodeEncodeIsSelfEquivalentWithMixedNullability() {
        val original = Pairing(agent1 = "A", agent2 = "B", action1 = "cooperate")
        val json1 = Json.encodeToString(original)
        val decoded = Json.decodeFromString<Pairing>(json1)
        val json2 = Json.encodeToString(decoded)
        assertEquals(json1, json2)
    }
}
