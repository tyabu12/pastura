package com.pastura.models

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Kotlin-side JSON roundtrip tests for [Persona] (W1 pilot per Issue #220).
 *
 * **Scope:** validates that the kotlinx.serialization toolchain — plugin
 * codegen, `@Serializable` annotation, and `Json` runtime — works end to
 * end on the simplest possible data class. Does NOT validate Swift↔Kotlin
 * H2 roundtrip (deferred to W2/W3 canonicalizer).
 */
class PersonaSerializationTests {

    @Test
    fun encodeDecodeRoundtripPreservesEquality() {
        val original = Persona(name = "Bob", description = "Cautious cooperator")
        val json = Json.encodeToString(original)
        val decoded = Json.decodeFromString<Persona>(json)
        assertEquals(original, decoded)
    }

    @Test
    fun encodeDecodeEncodeIsSelfEquivalent() {
        // Self-equivalence: encode(decode(encode(x))) == encode(x).
        // Catches non-determinism in the encoder (key ordering, whitespace,
        // number formatting). kotlinx.serialization's default `Json` is
        // deterministic on data classes; this test pins that contract.
        val original = Persona(name = "Alice", description = "Bold defector")
        val json1 = Json.encodeToString(original)
        val decoded = Json.decodeFromString<Persona>(json1)
        val json2 = Json.encodeToString(decoded)
        assertEquals(json1, json2)
    }

    @Test
    fun emittedJsonShapeMatchesCamelCaseDefault() {
        // Document the wire shape — kotlinx.serialization default is camelCase
        // property names verbatim, no automatic snake_case conversion.
        // Pastura YAML uses snake_case; this drift surfaces in W2 when the
        // canonicalizer maps Kotlin↔YAML↔Swift Codable. Pinning the default
        // shape here makes the W2 mapping work concrete instead of speculative.
        val p = Persona(name = "X", description = "Y")
        val json = Json.encodeToString(p)
        assertEquals("""{"name":"X","description":"Y"}""", json)
    }

    // MARK: - secret (#914 / #1141, ADR-023 §6 Stage-2 gate slice)

    @Test
    fun secretRoundtripsWhenSet() {
        val original = Persona(
            name = "Alice",
            description = "Bold cooperator",
            secret = "Actually working for the other team.",
        )
        val decoded = Json.decodeFromString<Persona>(Json.encodeToString(original))
        assertEquals(original, decoded)
        assertEquals("Actually working for the other team.", decoded.secret)
    }

    @Test
    fun secretDefaultsToNullAndIsOmittedFromTheWire() {
        // Load-bearing for the ADR-023 §6 Stage-2 gate: `secret` was added to a
        // module that already landed on `main` (Stage 1). kotlinx.serialization
        // omits default values unless `encodeDefaults = true`, so an unset
        // `secret` must leave the wire shape byte-identical to pre-#1141 — that
        // is what keeps this addition purely additive for every existing
        // baseline fixture and roundtrip test. Flipping `encodeDefaults` on
        // would emit `"secret":null` and SHOULD break this test.
        val p = Persona(name = "X", description = "Y")
        assertNull(p.secret)
        assertEquals("""{"name":"X","description":"Y"}""", Json.encodeToString(p))
    }

    @Test
    fun absentSecretDecodesToNull() {
        // The reverse direction: pre-#1141 JSON (no `secret` key) must still
        // decode, or every persisted/baseline payload breaks.
        val decoded = Json.decodeFromString<Persona>("""{"name":"X","description":"Y"}""")
        assertNull(decoded.secret)
    }

    @Test
    fun emptySecretIsPreservedNotNormalized() {
        // Pins the doc's explicit non-claim: the Swift ingest paths normalize
        // empty -> nil, but the TYPE does not enforce it. A direct caller can
        // construct `secret = ""`, and the codec must round-trip it verbatim
        // rather than silently coercing to null. When a Kotlin ingest path
        // lands (ScenarioLoader, Stage 3), the normalization belongs THERE.
        val p = Persona(name = "X", description = "Y", secret = "")
        val decoded = Json.decodeFromString<Persona>(Json.encodeToString(p))
        assertEquals("", decoded.secret)
    }
}
