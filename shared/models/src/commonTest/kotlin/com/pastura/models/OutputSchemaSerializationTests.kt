package com.pastura.models

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertNotNull

/**
 * Kotlin-side JSON roundtrip and behavioral tests for [OutputSchema], [OutputSchema.Field],
 * and [OutputSchema.Kind] (Issue #220 W2 Group A).
 *
 * **Scope:** validates Field/Kind serialization, the `OutputSchema.from(phase)` factory,
 * and `orderKeys` primary-first invariant. Does NOT validate Swift↔Kotlin H2 wire-shape
 * equivalence — wire shape divergence is documented in [OutputSchema.Kind]'s KDoc.
 */
class OutputSchemaSerializationTests {

    private val json = Json { ignoreUnknownKeys = true }

    // ── Field / Kind serialization ──────────────────────────────────────────

    @Test
    fun stringKindFieldRoundtrip() {
        val field = OutputSchema.Field(name = "statement", kind = OutputSchema.Kind.StringKind)
        val encoded = json.encodeToString(field)
        val decoded = json.decodeFromString<OutputSchema.Field>(encoded)
        assertEquals(field, decoded)
        assertEquals(OutputSchema.Kind.StringKind, decoded.kind)
    }

    @Test
    fun enumerationKindFieldRoundtrip() {
        val field = OutputSchema.Field(
            name = "action",
            kind = OutputSchema.Kind.Enumeration(listOf("cooperate", "betray")),
        )
        val encoded = json.encodeToString(field)
        val decoded = json.decodeFromString<OutputSchema.Field>(encoded)
        assertEquals(field, decoded)
        val enumKind = decoded.kind as OutputSchema.Kind.Enumeration
        assertEquals(listOf("cooperate", "betray"), enumKind.options)
    }

    @Test
    fun outputSchemaRoundtrip() {
        val schema = OutputSchema(
            fields = listOf(
                OutputSchema.Field("statement", OutputSchema.Kind.StringKind),
                OutputSchema.Field("inner_thought", OutputSchema.Kind.StringKind),
            ),
        )
        val encoded = json.encodeToString(schema)
        val decoded = json.decodeFromString<OutputSchema>(encoded)
        assertEquals(schema, decoded)
    }

    // ── OutputSchema.from(phase) factory ───────────────────────────────────

    @Test
    fun fromPhaseChooseWithOptionsProducesEnumerationKind() {
        // For choose phases with options, the "action" field becomes Enumeration.
        val phase = Phase(
            type = PhaseType.CHOOSE,
            outputSchema = mapOf("action" to "string"),
            options = listOf("cooperate", "betray"),
        )
        val schema = OutputSchema.from(phase)
        assertNotNull(schema)
        assertEquals(1, schema.fields.size)
        val field = schema.fields.first()
        assertEquals("action", field.name)
        val enumKind = field.kind as? OutputSchema.Kind.Enumeration
        assertNotNull(enumKind)
        assertEquals(listOf("cooperate", "betray"), enumKind.options)
    }

    @Test
    fun fromPhaseChooseWithoutOptionsProducesStringKind() {
        // choose phase with no options → action gets StringKind (no enumeration constraint).
        val phase = Phase(
            type = PhaseType.CHOOSE,
            outputSchema = mapOf("action" to "string"),
            options = null,
        )
        val schema = OutputSchema.from(phase)
        assertNotNull(schema)
        val field = schema.fields.first()
        assertEquals(OutputSchema.Kind.StringKind, field.kind)
    }

    @Test
    fun fromPhaseSpeakAllProducesStringKindForStatement() {
        val phase = Phase(
            type = PhaseType.SPEAK_ALL,
            outputSchema = mapOf("statement" to "string", "inner_thought" to "string"),
        )
        val schema = OutputSchema.from(phase)
        assertNotNull(schema)
        // All fields should be StringKind for speak_all.
        schema.fields.forEach { field ->
            assertEquals(OutputSchema.Kind.StringKind, field.kind)
        }
        // Primary-first: statement before inner_thought.
        assertEquals("statement", schema.fields[0].name)
        assertEquals("inner_thought", schema.fields[1].name)
    }

    @Test
    fun fromPhaseCodePhaseReturnsNull() {
        // Code phases have no outputSchema → factory returns null.
        val phase = Phase(
            type = PhaseType.SCORE_CALC,
            logic = ScoreCalcLogic.PRISONERS_DILEMMA,
        )
        assertNull(OutputSchema.from(phase))
    }

    @Test
    fun fromPhaseNullOutputSchemaReturnsNull() {
        val phase = Phase(type = PhaseType.SPEAK_ALL, outputSchema = null)
        assertNull(OutputSchema.from(phase))
    }

    @Test
    fun fromPhaseEmptyOutputSchemaReturnsNull() {
        val phase = Phase(type = PhaseType.SPEAK_ALL, outputSchema = emptyMap())
        assertNull(OutputSchema.from(phase))
    }

    // ── orderKeys primary-first invariant ──────────────────────────────────

    @Test
    fun orderKeysPrimaryFirstWithKnownKeys() {
        // Input: mixed order of primary + secondary keys.
        // Expected: primaries in knownPrimaryKeys order, then secondaries.
        val input = listOf("reason", "statement", "inner_thought", "action")
        val result = OutputSchema.orderKeys(input)
        assertEquals(listOf("statement", "action", "inner_thought", "reason"), result)
    }

    @Test
    fun orderKeysWithUnknownKeys() {
        // Unknown keys sorted alphabetically at end, after primaries.
        val input = listOf("xyz", "statement", "abc")
        val result = OutputSchema.orderKeys(input)
        assertEquals(listOf("statement", "abc", "xyz"), result)
    }

    @Test
    fun orderKeysSkipsAbsentPrimaryKeys() {
        // Only "vote" is present from primaries; "statement" and "action" are absent.
        val input = listOf("reason", "vote")
        val result = OutputSchema.orderKeys(input)
        assertEquals(listOf("vote", "reason"), result)
    }
}
