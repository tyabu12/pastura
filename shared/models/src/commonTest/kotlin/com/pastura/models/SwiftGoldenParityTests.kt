package com.pastura.models

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

/**
 * ADR-023 §6 measurement (v) — kotlinx.serialization parity against the **real**
 * Swift wire bytes, frozen in [SwiftGoldenJson] by
 * `swift run pastura-harness emit-golden --write`.
 *
 * This closes the gap [OutputSchemaSerializationTests] declares in its own KDoc
 * ("Does NOT validate Swift↔Kotlin H2 wire-shape equivalence"). That suite pins
 * what Kotlin *emits*; this one compares it against what Swift produced.
 *
 * **Two different claims, and they must not be confused** (ADR-023 §12
 * condition 1, 2026-07-19):
 *
 * - [TurnOutput] — **decode parity**. Kotlin decodes Swift's bytes directly,
 *   strictly, with no normalization. The strongest available claim.
 * - [OutputSchema] — **shape equivalence under normalization**, and nothing
 *   more. Kotlin does *not* decode Swift's bytes here and is not expected to:
 *   kotlinx.serialization tags sealed classes with a `type` discriminator where
 *   Swift's synthesized `Codable` wraps the case name as the key. That
 *   difference is left standing on purpose — [OutputSchema] is never JSON-
 *   crossed in production, so closing it would mean adding a production
 *   serializer whose stated reason is a wire contract that has no wire. See
 *   [OutputSchema.Kind]'s KDoc, and `check-outputschema-serialization-gate.py`
 *   for the gate that keeps the premise true.
 *
 * **Do not "strengthen" the OutputSchema comparisons to byte equality.** It
 * would fail for reasons unrelated to parity: Swift's encoder sorts keys and
 * pretty-prints, Kotlin emits declaration order compactly, and every constant
 * in [SwiftGoldenJson] is `"\n" + <what Swift emitted> + "\n"` — the raw-string
 * padding `GoldenFixtureEmitter` documents in its own header.
 *
 * **One-sided by construction.** The goldens prove things about Swift-produced
 * bytes. They do not prove the reverse — no build in this repo can link the
 * Swift `Codable` types and Kotlin in one process (SwiftPM forbids a target's
 * sources from escaping its package root, and the conformances live in
 * `Pastura/Pastura/Models/`). Swift-decodes-Kotlin stays unmeasured; Stage 3's
 * parity harness is where it belongs.
 *
 * **Strict decoding on purpose.** The [TurnOutput] cases use a default [Json]
 * rather than the `ignoreUnknownKeys = true` instance the sibling suites use.
 * Leniency would silently absorb a field Swift adds and Kotlin does not model —
 * which is precisely the drift this measurement exists to detect.
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

    // ── OutputSchema: shape equivalence under normalization ─────────────────

    /**
     * The discriminator values [Canonicalizer]'s Stage 3 lifts.
     *
     * **Deliberately a literal, not derived from the sealed class's serial
     * descriptors.** Deriving it would move the set in lockstep with a
     * `@SerialName` rename, so the condition-4 rename perturbation would still
     * redden — but by tree inequality against the Swift golden, never by
     * reaching the lift-misfire path. The lift fires on discriminator *value*
     * membership, so "the lift silently stops firing" is a distinct failure
     * mode, and only a hardcoded set can expose it.
     */
    private val discriminatorValues = setOf("string", "choice")

    private fun canonical(jsonText: String) =
        Canonicalizer.canonicalize(Json.parseToJsonElement(jsonText), discriminatorValues)

    /**
     * Kotlin's encoding of the same schema matches Swift's, once both trees are
     * canonicalized.
     *
     * What normalization absorbs, and why each is legitimate rather than a
     * defect being papered over:
     *
     * - **Tag form** (Stage 3). `{"type":"string"}` → `{"string":{}}`. Left
     *   diverged in production by decision — see the class KDoc.
     * - **Key order** (Stage 1). Swift's encoder emits `.sortedKeys`
     *   (`kind` before `name`); Kotlin emits declaration order (`name` before
     *   `kind`). A property-order difference is not a schema difference.
     *
     * What it does **not** absorb, which is what gives the test teeth: field
     * names, the order of the `fields` array itself (Stage 1 preserves array
     * order, and that order is the primary-first streaming policy), the case
     * name (`choice` vs anything else), and any added or removed property —
     * including a reintroduced `options` payload.
     */
    @Test
    fun outputSchemaStringKindMatchesSwiftUnderNormalization() {
        val schema = OutputSchema(
            fields = listOf(OutputSchema.Field("statement", OutputSchema.Kind.StringKind)),
        )
        assertEquals(
            canonical(SwiftGoldenJson.outputSchemaStringKind),
            canonical(json.encodeToString(schema)),
        )
    }

    @Test
    fun outputSchemaChoiceKindMatchesSwiftUnderNormalization() {
        // Hand-built in the Swift golden's field order rather than via
        // OutputSchema.from(phase): this test targets the tag form and payload,
        // and from()'s ordering policy is exercised in OutputSchemaSerializationTests.
        val schema = OutputSchema(
            fields = listOf(
                OutputSchema.Field("action", OutputSchema.Kind.Choice),
                OutputSchema.Field("reason", OutputSchema.Kind.StringKind),
            ),
        )
        assertEquals(
            canonical(SwiftGoldenJson.outputSchemaChoiceKind),
            canonical(json.encodeToString(schema)),
        )
    }

    /**
     * Pins Kotlin's **native** emission, un-normalized.
     *
     * Without this the tag-form difference would be invisible: the tests above
     * canonicalize it away by design, so a future change that happened to align
     * the wire shapes — or to break Kotlin's own — would pass them silently.
     * This is the tripwire that makes the divergence a recorded decision rather
     * than an unexamined state, and it is the assertion to update (together
     * with [OutputSchema.Kind]'s KDoc and ADR-023 §12 condition 1) if the
     * production shape is ever changed.
     */
    @Test
    fun kotlinEmitsItsOwnTagFormNatively() {
        val schema = OutputSchema(
            fields = listOf(OutputSchema.Field("action", OutputSchema.Kind.Choice)),
        )
        assertEquals(
            """{"fields":[{"name":"action","kind":{"type":"choice"}}]}""",
            json.encodeToString(schema),
        )
        // The Swift golden for the same case, for contrast — outer-wrapped.
        assertTrue(SwiftGoldenJson.outputSchemaChoiceKind.contains("\"choice\" : {"))
    }

    /**
     * The normalization is not vacuous *from already-equal inputs*: the two
     * trees genuinely differ before it runs.
     *
     * A canonicalize-both-sides comparison would pass just as well if the two
     * inputs were already identical and the normalization did nothing — this
     * asserts the pre-normalization inequality to rule that out. It does NOT
     * cover the other vacuity mode (a `Canonicalizer` that collapsed everything
     * to a constant would still leave this green); that is the job of the
     * dedicated `CanonicalizerStage1/2/3Tests`, which pin the transform's actual
     * output shape rather than trusting it here.
     */
    @Test
    fun theTwoShapesDifferBeforeNormalization() {
        val schema = OutputSchema(
            fields = listOf(OutputSchema.Field("statement", OutputSchema.Kind.StringKind)),
        )
        assertNotEquals(
            Json.parseToJsonElement(SwiftGoldenJson.outputSchemaStringKind),
            Json.parseToJsonElement(json.encodeToString(schema)),
        )
    }
}
