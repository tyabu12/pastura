package com.pastura.models

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals

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
}
