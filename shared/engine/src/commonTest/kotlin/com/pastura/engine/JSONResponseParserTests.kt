package com.pastura.engine

import com.pastura.models.SimulationError
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertNull

/**
 * Kotlin siblings of the Swift `JSONResponseParserTests` cases the gate slice
 * ports. ADR-023 §6 names those Swift test files as the executable spec, so the
 * section numbering below mirrors theirs.
 *
 * Cases whose subject is a Stage-3 unit (the repair pipeline, multi-object
 * salvage) are absent by scope, not oversight — see the class doc on
 * [JSONResponseParser]. The measured Swift divergence lives in
 * [JSONResponseParserParityTests].
 *
 * Ported for the ADR-023 §6 Stage-2 gate slice (#501).
 */
class JSONResponseParserTests {

    private val parser = JSONResponseParser()

    // MARK: - 1. Plain object

    @Test
    fun parsesPlainObject() {
        val out = parser.parse("""{"statement": "hello", "inner_thought": "hmm"}""")
        assertEquals("hello", out.fields["statement"])
        assertEquals("hmm", out.fields["inner_thought"])
    }

    // MARK: - 2. Thinking tags

    @Test
    fun stripsGemmaChannelThinking() {
        val out = parser.parse("""<|channel>thought I should cooperate<channel|>{"statement": "hi"}""")
        assertEquals("hi", out.fields["statement"])
    }

    @Test
    fun stripsThinkTags() {
        val out = parser.parse("""<think>reasoning
        across lines</think>{"statement": "hi"}""")
        assertEquals("hi", out.fields["statement"])
    }

    // MARK: - 3. Chat-template token

    @Test
    fun truncatesAtChatTemplateToken() {
        // The model hallucinated past its own turn; everything from the token on
        // is fabricated and must not reach the balanced scan.
        val out = parser.parse("""{"statement": "real"}<|im_end|>{"statement": "fabricated"}""")
        assertEquals("real", out.fields["statement"])
    }

    // MARK: - 4. Code fences

    @Test
    fun extractsFromJsonCodeFence() {
        val out = parser.parse("```json\n{\"statement\": \"hi\"}\n```")
        assertEquals("hi", out.fields["statement"])
    }

    @Test
    fun extractsFromBareCodeFence() {
        val out = parser.parse("```\n{\"statement\": \"hi\"}\n```")
        assertEquals("hi", out.fields["statement"])
    }

    // MARK: - 5. Surrounding garbage / balanced scan

    @Test
    fun discardsLeadingAndTrailingProse() {
        val out = parser.parse("""Sure! Here you go: {"statement": "hi"} Hope that helps.""")
        assertEquals("hi", out.fields["statement"])
    }

    @Test
    fun discardsStrayTrailingBrace() {
        // #751 sub-class 1: grammar-constrained generation appending `}`. A greedy
        // `\{.*\}` regex would run to the LAST brace and keep it.
        val out = parser.parse("""{"statement": "hi"}}""")
        assertEquals("hi", out.fields["statement"])
    }

    @Test
    fun braceInsideAStringValueIsNotStructural() {
        // The string-aware scan's reason to exist: the `{` in the value must not
        // start a nested balance count.
        val out = parser.parse("""{"statement": "答えは{\"a\":1}です"}""")
        assertEquals("""答えは{"a":1}です""", out.fields["statement"])
    }

    @Test
    fun escapedQuoteDoesNotCloseTheStringEarly() {
        val out = parser.parse("""{"statement": "he said \"hi\" loudly"}""")
        assertEquals("""he said "hi" loudly""", out.fields["statement"])
    }

    @Test
    fun multiObjectSpanIsRejectedRatherThanSalvaged() {
        // Swift defers this to its schema-guarded salvage (#907, Stage-3 freight).
        // Until then a re-rolled second answer must fail and re-sample, not
        // silently take the first — it may be off-persona.
        val error = assertFailsWith<SimulationException> { parser.parse("""{"a":1}{"b":2}""") }
        assertIs<SimulationError.JsonParseFailed>(error.error)
    }

    // MARK: - 6/7. Value normalization

    @Test
    fun normalizesNumericValues() {
        // The Swift spec's own case, verbatim: {"score": 42, "ratio": 3.14}.
        val out = parser.parse("""{"score": 42, "ratio": 3.14}""")
        assertEquals("42", out.fields["score"])
        assertEquals("3.14", out.fields["ratio"])
    }

    @Test
    fun normalizesBooleanValues() {
        val out = parser.parse("""{"alive": true, "eliminated": false}""")
        assertEquals("true", out.fields["alive"])
        assertEquals("false", out.fields["eliminated"])
    }

    // MARK: - 8. Nulls

    @Test
    fun omitsNullValues() {
        val out = parser.parse("""{"statement": "hello", "extra": null}""")
        assertEquals("hello", out.fields["statement"])
        assertNull(out.fields["extra"])
    }

    // MARK: - 9. Nested values

    @Test
    fun normalizesNestedObjectToSortedJsonString() {
        // Swift passes `.sortedKeys`; kotlinx has no such option, so the sort is
        // explicit. Measured Swift output for this input: {"b":2,"z":1}.
        val out = parser.parse("""{"data": {"z": 1, "b": 2}}""")
        assertEquals("""{"b":2,"z":1}""", out.fields["data"])
    }

    @Test
    fun sortsNestedKeysAtEveryDepth() {
        val out = parser.parse("""{"data": {"z": {"y": 1, "a": 2}, "b": 3}}""")
        assertEquals("""{"b":3,"z":{"a":2,"y":1}}""", out.fields["data"])
    }

    @Test
    fun normalizesNestedArrayToJsonString() {
        val out = parser.parse("""{"data": [1, 2]}""")
        assertEquals("[1,2]", out.fields["data"])
    }

    @Test
    fun arrayElementOrderIsPreservedNotSorted() {
        // Only OBJECT keys are sorted — array order is semantic.
        val out = parser.parse("""{"data": ["z", "a"]}""")
        assertEquals("""["z","a"]""", out.fields["data"])
    }

    // MARK: - Failure

    @Test
    fun throwsJsonParseFailedOnUnparseableInput() {
        val error = assertFailsWith<SimulationException> { parser.parse("not json at all") }
        val failed = assertIs<SimulationError.JsonParseFailed>(error.error)
        assertEquals("not json at all", failed.raw)
    }

    @Test
    fun throwsOnUnclosedObject() {
        // Swift hands this to its repair pipeline (Stage-3 freight); this slice
        // fails the parse instead. Named scope, not an accident.
        assertFailsWith<SimulationException> { parser.parse("""{"statement": "hi""") }
    }

    @Test
    fun throwsOnANonObjectRoot() {
        assertFailsWith<SimulationException> { parser.parse("""["a", "b"]""") }
    }

    // MARK: - expectedKeys guard

    @Test
    fun expectedKeysGuardAcceptsACompleteObject() {
        val (out, repair) = parser.parse("""{"statement": "hi"}""", expectedKeys = setOf("statement"))
        assertEquals("hi", out.fields["statement"])
        assertNull(repair, "the repair pipeline is Stage-3 freight — this must stay null")
    }

    @Test
    fun expectedKeysGuardRejectsAMissingKey() {
        // Preserves the throw rather than fabricating a half-formed TurnOutput.
        assertFailsWith<SimulationException> {
            parser.parse("""{"other": "hi"}""", expectedKeys = setOf("statement"))
        }
    }

    @Test
    fun expectedKeysGuardRejectsAnEmptyValue() {
        assertFailsWith<SimulationException> {
            parser.parse("""{"statement": ""}""", expectedKeys = setOf("statement"))
        }
    }

    @Test
    fun emptyExpectedKeysDisablesTheGuard() {
        val (out, _) = parser.parse("""{"anything": "x"}""", expectedKeys = emptySet())
        assertEquals("x", out.fields["anything"])
    }
}
