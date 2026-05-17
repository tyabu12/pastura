package com.pastura.models

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Kotlin-side JSON roundtrip and behavioral tests for [Phase] (Issue #220 W2 Group A).
 *
 * **Scope:** validates kotlinx.serialization roundtrip for Phase's 16 nullable
 * fields, recursive thenPhases/elsePhases, and the derived [Phase.outputSchemaKeys]
 * property. Does NOT validate Swift↔Kotlin H2 wire-shape equivalence (deferred to
 * W2/W3 canonicalizer). Null-omit divergence from Swift Codable is documented in
 * the `nullFieldsAreOmittedFromJson` test — same contract as PairingSerializationTests.
 */
class PhaseSerializationTests {

    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun llmPhaseRoundtrip() {
        // speak_all with prompt + outputSchema — typical LLM phase shape.
        val original = Phase(
            type = PhaseType.SPEAK_ALL,
            prompt = "You are {name}. Say something about {topic}.",
            outputSchema = mapOf("statement" to "string", "inner_thought" to "string"),
        )
        val encoded = json.encodeToString(original)
        val decoded = json.decodeFromString<Phase>(encoded)
        assertEquals(original, decoded)
        assertEquals(PhaseType.SPEAK_ALL, decoded.type)
        assertEquals("You are {name}. Say something about {topic}.", decoded.prompt)
        assertEquals(mapOf("statement" to "string", "inner_thought" to "string"), decoded.outputSchema)
    }

    @Test
    fun codePhaseRoundtrip() {
        // score_calc with logic = PRISONERS_DILEMMA — typical code phase shape.
        val original = Phase(
            type = PhaseType.SCORE_CALC,
            logic = ScoreCalcLogic.PRISONERS_DILEMMA,
        )
        val encoded = json.encodeToString(original)
        val decoded = json.decodeFromString<Phase>(encoded)
        assertEquals(original, decoded)
        assertEquals(PhaseType.SCORE_CALC, decoded.type)
        assertEquals(ScoreCalcLogic.PRISONERS_DILEMMA, decoded.logic)
        assertNull(decoded.prompt)
        assertNull(decoded.outputSchema)
    }

    @Test
    fun conditionalPhaseRoundtripWithNestedPhase() {
        // conditional phase with condition + thenPhases + elsePhases — recursive structure.
        val innerThen = Phase(
            type = PhaseType.SPEAK_ALL,
            prompt = "Inner then prompt.",
            outputSchema = mapOf("statement" to "string"),
        )
        val innerElse = Phase(
            type = PhaseType.SCORE_CALC,
            logic = ScoreCalcLogic.PRISONERS_DILEMMA,
        )
        val original = Phase(
            type = PhaseType.CONDITIONAL,
            condition = "score.alice > 5",
            thenPhases = listOf(innerThen),
            elsePhases = listOf(innerElse),
        )
        val encoded = json.encodeToString(original)
        val decoded = json.decodeFromString<Phase>(encoded)
        assertEquals(original, decoded)
        assertEquals("score.alice > 5", decoded.condition)
        assertEquals(1, decoded.thenPhases?.size)
        assertEquals(innerThen, decoded.thenPhases?.first())
        assertEquals(1, decoded.elsePhases?.size)
        assertEquals(innerElse, decoded.elsePhases?.first())
    }

    @Test
    fun outputSchemaKeysReturnsEmptySetWhenNull() {
        val phase = Phase(type = PhaseType.SCORE_CALC)
        assertTrue(phase.outputSchemaKeys.isEmpty())
    }

    @Test
    fun outputSchemaKeysReturnsCorrectSetWhenPresent() {
        val phase = Phase(
            type = PhaseType.SPEAK_ALL,
            prompt = "...",
            outputSchema = mapOf("statement" to "string", "inner_thought" to "string"),
        )
        assertEquals(setOf("statement", "inner_thought"), phase.outputSchemaKeys)
    }

    @Test
    fun nullFieldsAreOmittedFromJson() {
        // CANARY for W2 canonicalizer design (null-omit axis) — same divergence
        // as PairingSerializationTests.nullOptionalsAreOmittedByDefault.
        //
        // kotlinx.serialization default: properties at their default value (null)
        // are NOT emitted in JSON. Swift Codable default: nil IS emitted as null.
        //
        // H2 canonicalizer must reconcile via encodeDefaults=true on the Kotlin side
        // OR custom encode(to:) on the Swift side. This test pins the Kotlin default
        // so any behavior change surfaces here first.
        val phase = Phase(type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.PRISONERS_DILEMMA)
        val encoded = json.encodeToString(phase)
        // Only type and logic should appear; all null fields are omitted.
        assertEquals("""{"type":"score_calc","logic":"prisoners_dilemma"}""", encoded)
    }
}
