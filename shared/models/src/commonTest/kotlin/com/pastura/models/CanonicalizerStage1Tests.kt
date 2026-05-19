package com.pastura.models

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs

/**
 * Stage 1 (structural) tests for [Canonicalizer] — Issue #220 W2 PR-B Stage 1.
 *
 * Rules under test:
 * - Key sort (recursive) on every [JsonObject], including nested objects.
 * - Array order is preserved; inner objects within arrays still get key-sorted.
 * - Null-omit: every `key: JsonNull` entry is dropped from [JsonObject].
 *   Top-level [JsonNull] and [JsonNull] elements inside arrays are preserved
 *   (only object-key-level nulls are dropped).
 *
 * Numeric normalization (Stage 2) and tag-form adapter (Stage 3) land in
 * sibling test files; this suite asserts Stage 1 in isolation.
 */
class CanonicalizerStage1Tests {

    // -------- key sort --------

    @Test
    fun emptyObjectStaysEmpty() {
        val input = buildJsonObject {}
        val output = Canonicalizer.canonicalize(input)
        assertEquals(buildJsonObject {}, output)
    }

    @Test
    fun objectKeysSortedAlphabetically() {
        val input = buildJsonObject {
            put("zebra", JsonPrimitive(1))
            put("apple", JsonPrimitive(2))
            put("mango", JsonPrimitive(3))
        }
        val output = Canonicalizer.canonicalize(input) as JsonObject
        assertEquals(listOf("apple", "mango", "zebra"), output.keys.toList())
    }

    @Test
    fun nestedObjectKeysAlsoSorted() {
        val input = buildJsonObject {
            put("outer", buildJsonObject {
                put("zebra", JsonPrimitive(1))
                put("apple", JsonPrimitive(2))
            })
        }
        val output = Canonicalizer.canonicalize(input) as JsonObject
        val inner = output["outer"] as JsonObject
        assertEquals(listOf("apple", "zebra"), inner.keys.toList())
    }

    // -------- array semantics --------

    @Test
    fun arrayOrderPreserved() {
        val input = buildJsonArray {
            add(JsonPrimitive(3))
            add(JsonPrimitive(1))
            add(JsonPrimitive(2))
        }
        val output = Canonicalizer.canonicalize(input) as JsonArray
        assertEquals(listOf(JsonPrimitive(3), JsonPrimitive(1), JsonPrimitive(2)), output.toList())
    }

    @Test
    fun objectsInsideArrayHaveKeysSorted() {
        val input = buildJsonArray {
            add(buildJsonObject {
                put("zebra", JsonPrimitive(1))
                put("apple", JsonPrimitive(2))
            })
            add(buildJsonObject {
                put("mango", JsonPrimitive(3))
                put("banana", JsonPrimitive(4))
            })
        }
        val output = Canonicalizer.canonicalize(input) as JsonArray
        val first = output[0] as JsonObject
        val second = output[1] as JsonObject
        assertEquals(listOf("apple", "zebra"), first.keys.toList())
        assertEquals(listOf("banana", "mango"), second.keys.toList())
    }

    // -------- null-omit policy --------

    @Test
    fun objectKeyWithNullValueIsDropped() {
        val input = buildJsonObject {
            put("present", JsonPrimitive(1))
            put("absent", JsonNull)
        }
        val output = Canonicalizer.canonicalize(input) as JsonObject
        assertEquals(setOf("present"), output.keys)
    }

    @Test
    fun topLevelNullIsPreserved() {
        val output = Canonicalizer.canonicalize(JsonNull)
        assertEquals(JsonNull, output)
    }

    @Test
    fun nullsInsideArraysArePreserved() {
        // Array nulls carry positional meaning (e.g., "this slot was empty");
        // dropping them would shift indices. Only key-level nulls in objects
        // are normalized away.
        val input = buildJsonArray {
            add(JsonPrimitive(1))
            add(JsonNull)
            add(JsonPrimitive(2))
        }
        val output = Canonicalizer.canonicalize(input) as JsonArray
        assertEquals(3, output.size)
        assertEquals(JsonNull, output[1])
    }

    @Test
    fun nullsInsideArrayElementObjectsAreDropped() {
        val input = buildJsonArray {
            add(buildJsonObject {
                put("kept", JsonPrimitive(1))
                put("nulled", JsonNull)
            })
        }
        val output = Canonicalizer.canonicalize(input) as JsonArray
        val first = output[0] as JsonObject
        assertEquals(setOf("kept"), first.keys)
    }

    @Test
    fun objectBecomingEmptyAfterNullOmitIsStillEmptyObject() {
        // An object whose only entries are all nulls collapses to {} —
        // it does NOT itself become JsonNull. The caller can still
        // distinguish "explicit empty container" from "absent value".
        val input = buildJsonObject {
            put("a", JsonNull)
            put("b", JsonNull)
        }
        val output = Canonicalizer.canonicalize(input)
        assertIs<JsonObject>(output)
        assertEquals(0, output.size)
    }

    // -------- composite scenarios --------

    @Test
    fun deeplyNestedStructureCanonicalizes() {
        val input = buildJsonObject {
            put("outerZ", buildJsonArray {
                add(buildJsonObject {
                    put("inner2", JsonPrimitive("b"))
                    put("inner1", JsonNull)
                })
            })
            put("outerA", buildJsonObject {
                put("alpha", buildJsonArray {
                    add(JsonPrimitive(1))
                    add(JsonNull)
                })
            })
        }
        val output = Canonicalizer.canonicalize(input) as JsonObject
        assertEquals(listOf("outerA", "outerZ"), output.keys.toList())

        val outerA = output["outerA"] as JsonObject
        val alphaArr = outerA["alpha"] as JsonArray
        assertEquals(2, alphaArr.size)
        assertEquals(JsonNull, alphaArr[1])

        val outerZ = output["outerZ"] as JsonArray
        val first = outerZ[0] as JsonObject
        assertEquals(setOf("inner2"), first.keys)
    }

    @Test
    fun encodedJsonTextIsStableForSortedInput() {
        // Composition with kotlinx.serialization's Json encoder: the
        // sorted-key insertion order must survive Json.encodeToString.
        val input = buildJsonObject {
            put("z", JsonPrimitive(1))
            put("a", JsonPrimitive(2))
            put("m", JsonPrimitive(3))
        }
        val output = Canonicalizer.canonicalize(input)
        val encoded = Json.encodeToString(JsonObject.serializer(), output as JsonObject)
        assertEquals("""{"a":2,"m":3,"z":1}""", encoded)
    }
}
