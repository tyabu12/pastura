package com.pastura.models

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs

/**
 * JSON roundtrip and disambiguation tests for [AnyCodableValue].
 *
 * The critical invariant is the **arrayOfDicts-before-array disambiguation**:
 * a JSON array whose first element is an object must decode as
 * [AnyCodableValue.ArrayOfDictionariesValue], never [AnyCodableValue.ArrayValue].
 */
class AnyCodableValueSerializationTests {

    @Test
    fun stringValueRoundtrip() {
        val original: AnyCodableValue = AnyCodableValue.StringValue("hello")
        val json = Json.encodeToString(original)
        assertEquals("\"hello\"", json)
        val decoded = Json.decodeFromString<AnyCodableValue>(json)
        assertEquals(original, decoded)
    }

    @Test
    fun arrayValueRoundtrip() {
        val original: AnyCodableValue = AnyCodableValue.ArrayValue(listOf("apple", "banana", "cherry"))
        val json = Json.encodeToString(original)
        assertEquals("""["apple","banana","cherry"]""", json)
        val decoded = Json.decodeFromString<AnyCodableValue>(json)
        assertEquals(original, decoded)
    }

    @Test
    fun dictionaryValueRoundtrip() {
        // Use a single-key map to avoid key-order ambiguity in the JSON comparison.
        val original: AnyCodableValue = AnyCodableValue.DictionaryValue(mapOf("key" to "value"))
        val json = Json.encodeToString(original)
        val decoded = Json.decodeFromString<AnyCodableValue>(json)
        assertEquals(original, decoded)
    }

    @Test
    fun arrayOfDictionariesValueRoundtrip() {
        val original: AnyCodableValue = AnyCodableValue.ArrayOfDictionariesValue(
            listOf(
                mapOf("majority" to "りんご", "minority" to "みかん"),
                mapOf("majority" to "犬", "minority" to "猫"),
            )
        )
        val json = Json.encodeToString(original)
        val decoded = Json.decodeFromString<AnyCodableValue>(json)
        assertEquals(original, decoded)
    }

    /**
     * Disambiguation test: encoding an [AnyCodableValue.ArrayOfDictionariesValue]
     * produces a JSON array of objects; decoding that JSON must yield
     * [AnyCodableValue.ArrayOfDictionariesValue], NOT [AnyCodableValue.ArrayValue].
     *
     * This is the critical port correctness invariant — if the serializer checks
     * array-before-arrayOfDicts, this test fails.
     */
    @Test
    fun arrayOfDictsDecode_notDecodedAsArrayValue() {
        val original: AnyCodableValue = AnyCodableValue.ArrayOfDictionariesValue(
            listOf(mapOf("k" to "v"))
        )
        val json = Json.encodeToString(original)
        assertEquals("""[{"k":"v"}]""", json)
        val decoded = Json.decodeFromString<AnyCodableValue>(json)
        assertIs<AnyCodableValue.ArrayOfDictionariesValue>(decoded)
        assertEquals(original, decoded)
    }

    /** Empty array decodes as [AnyCodableValue.ArrayValue] (no object elements to inspect). */
    @Test
    fun emptyArrayDecodesAsArrayValue() {
        val decoded = Json.decodeFromString<AnyCodableValue>("[]")
        assertIs<AnyCodableValue.ArrayValue>(decoded)
        // assertIs smart-casts `decoded` to ArrayValue — no cast needed.
        assertEquals(emptyList<String>(), decoded.value)
    }
}
