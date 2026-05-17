package com.pastura.models

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * JSON roundtrip tests for [AssignTarget].
 *
 * Wire shapes must match Swift's `Codable` default for `enum AssignTarget: String`
 * — each case encodes to its raw value string (`"all"`, `"random_one"`).
 */
class AssignTargetTests {

    @Test
    fun allEncodesToSwiftRawValueString() {
        assertEquals("\"all\"", Json.encodeToString(AssignTarget.ALL))
    }

    @Test
    fun randomOneEncodesToSwiftRawValueString() {
        assertEquals("\"random_one\"", Json.encodeToString(AssignTarget.RANDOM_ONE))
    }

    @Test
    fun allCasesRoundtripPreservesEquality() {
        AssignTarget.entries.forEach { original ->
            val decoded = Json.decodeFromString<AssignTarget>(Json.encodeToString(original))
            assertEquals(original, decoded, "Roundtrip failed for $original")
        }
    }
}
