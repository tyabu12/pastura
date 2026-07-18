package com.pastura.models

import kotlinx.serialization.SerializationException
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/**
 * ADR-023 §6 measurement (v) — kotlinx.serialization parity against the **real**
 * Swift wire bytes, frozen in [SwiftGoldenJson] by
 * `swift run pastura-harness emit-golden --write`.
 *
 * This closes the gap [OutputSchemaSerializationTests] declares in its own KDoc
 * ("Does NOT validate Swift↔Kotlin H2 wire-shape equivalence"). That suite pins
 * what Kotlin *emits*; this one pins what Kotlin can *accept* from Swift.
 *
 * **One-sided by construction.** The goldens prove Kotlin decodes what Swift
 * produces. They do not prove the reverse — no build in this repo can link the
 * Swift `Codable` types and Kotlin in one process (SwiftPM forbids a target's
 * sources from escaping its package root, and the conformances live in
 * `Pastura/Pastura/Models/`). Swift-decodes-Kotlin stays unmeasured; Stage 3's
 * parity harness is where it belongs.
 *
 * **Strict decoding on purpose.** These use a default [Json] rather than the
 * `ignoreUnknownKeys = true` instance the sibling suites use. Leniency would
 * silently absorb a field Swift adds and Kotlin does not model — which is
 * precisely the drift this measurement exists to detect.
 */
class SwiftGoldenParityTests {

    private val json = Json

    // ── TurnOutput: parity holds ────────────────────────────────────────────

    @Test
    fun turnOutputSingleFieldDecodesFromSwiftBytes() {
        val decoded = json.decodeFromString<TurnOutput>(SwiftGoldenJson.turnOutputSingleField)
        assertEquals(mapOf("statement" to "Hello."), decoded.fields)
    }

    @Test
    fun turnOutputMultipleFieldsDecodesFromSwiftBytes() {
        val decoded = json.decodeFromString<TurnOutput>(SwiftGoldenJson.turnOutputMultipleFields)
        assertEquals(
            mapOf("statement" to "I agree.", "inner_thought" to "Not really."),
            decoded.fields,
        )
    }

    /**
     * Multi-byte values survive the crossing intact.
     *
     * Not decoration: CJK and emoji are the value class that crashed llama.cpp's
     * sampler (#597/#599) and drove the `.choice` payload removal this file also
     * documents below. A silent transcoding defect here would be the same family
     * of bug arriving by a different route.
     */
    @Test
    fun turnOutputMultibyteValuesSurvive() {
        val decoded = json.decodeFromString<TurnOutput>(SwiftGoldenJson.turnOutputMultibyte)
        assertEquals("こんにちは 🐑", decoded.fields["statement"])
        assertEquals("多バイト値", decoded.fields["reason"])
    }

    @Test
    fun turnOutputEmptyFieldsDecodesToEmptyMap() {
        val decoded = json.decodeFromString<TurnOutput>(SwiftGoldenJson.turnOutputEmptyFields)
        assertTrue(decoded.fields.isEmpty())
    }

    /**
     * Swift's `rawText` never reaches the wire, so Kotlin's lack of the property
     * is a match rather than a hole.
     *
     * The golden was encoded from a Swift value with `rawText` populated. Strict
     * decoding is what gives this teeth: were `rawText` present in the bytes,
     * the default [Json] would reject the unknown key instead of quietly
     * dropping it.
     */
    @Test
    fun turnOutputRawTextIsAbsentFromTheWire() {
        val decoded = json.decodeFromString<TurnOutput>(SwiftGoldenJson.turnOutputWithRawText)
        assertEquals(mapOf("statement" to "provenance"), decoded.fields)
    }

    // ── OutputSchema: parity does NOT hold ──────────────────────────────────

    /**
     * Kotlin cannot decode Swift's `OutputSchema` bytes. This is the measurement's
     * finding, pinned as an executable fact rather than left as prose.
     *
     * Three independent divergences, only the first of which is a serialization
     * detail:
     *
     * 1. **Tagging.** Swift's synthesized enum `Codable` wraps the case name as
     *    the key (`{"string":{}}`); Kotlin's sealed class uses a `type`
     *    discriminator (`{"type":"string"}`).
     * 2. **Case name.** Swift's second case is `choice`; Kotlin's is
     *    `enumeration`. There is no `choice` for Kotlin to resolve.
     * 3. **Payload.** Kotlin's `Enumeration` *requires* `options: List<String>`.
     *    Swift deliberately carries none — enumerating options into the GBNF
     *    grammar crashed llama.cpp's sampler on multi-byte values (#597/#599),
     *    so the payload was removed to make the mistake unrepresentable.
     *
     * (3) is the one that matters beyond wire format: Kotlin still models a
     * concept Swift retired for a runtime-safety reason. Nothing in Kotlin reads
     * `options` today — `PromptBuilder.formatOutputSchema` ignores every [Kind]
     * and emits `"string"`, carrying a comment warning against "improving" it —
     * but that guard is prose, where Swift's is the type system.
     *
     * Asserting the failure rather than skipping the type keeps the finding from
     * decaying: if a future change aligns the two shapes, this test fails and
     * forces the ADR record to be updated rather than silently going stale.
     */
    @Test
    fun outputSchemaStringKindIsRejected() {
        assertSwiftShapeRejected(SwiftGoldenJson.outputSchemaStringKind)
    }

    @Test
    fun outputSchemaChoiceKindIsRejected() {
        assertSwiftShapeRejected(SwiftGoldenJson.outputSchemaChoiceKind)
    }

    /**
     * Asserts the rejection is about the *schema*, not about broken bytes or a
     * broken decoder.
     *
     * A bare `assertFailsWith` would pass just as well against an empty or
     * corrupted constant, which is the failure mode a generated fixture is most
     * exposed to. Two bracketing checks remove that:
     *
     * - the golden must parse as well-formed JSON, so the failure is not lexical;
     * - the same decoder must accept Kotlin's own tagging, so the failure is not
     *   the decoder being broken outright.
     */
    private fun assertSwiftShapeRejected(golden: String) {
        Json.parseToJsonElement(golden)

        assertFailsWith<SerializationException> {
            json.decodeFromString<OutputSchema>(golden)
        }

        val kotlinShaped = """{"fields":[{"name":"statement","kind":{"type":"string"}}]}"""
        assertEquals(
            OutputSchema(listOf(OutputSchema.Field("statement", OutputSchema.Kind.StringKind))),
            json.decodeFromString<OutputSchema>(kotlinShaped),
        )
    }

    /**
     * Records what Kotlin emits for the same schema, so the delta against the
     * Swift golden is readable in one place instead of requiring a reader to
     * hold two files in their head.
     */
    @Test
    fun kotlinEmitsADifferentShapeForTheSameSchema() {
        val schema = OutputSchema(
            fields = listOf(OutputSchema.Field("statement", OutputSchema.Kind.StringKind)),
        )
        assertEquals(
            """{"fields":[{"name":"statement","kind":{"type":"string"}}]}""",
            json.encodeToString(schema),
        )
        // The Swift golden for the same value, for contrast.
        assertTrue(SwiftGoldenJson.outputSchemaStringKind.contains("\"string\" : {"))
    }
}
