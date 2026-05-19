package com.pastura.models

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Stage 2 (numeric) tests for [Canonicalizer] — Issue #220 W2 PR-B Stage 2.
 *
 * Stage 2 is **a no-op transform at the [Canonicalizer] code layer.** This
 * suite documents and guards the contract:
 *
 * - **Int/Long policy**: applies at the Kotlin construction layer (test
 *   fixtures pin to `Long` for portability across Pastura's iOS-only
 *   deployment, where Swift `Int` = `Int64`). At the JSON-text layer
 *   produced by `kotlinx.serialization`, [JsonPrimitive] of `Int` and
 *   `Long` serialize identically because the type is stored as a content
 *   string — no transform is needed.
 * - **Double policy**: IEEE-754 bit-equal after JSON round-trip. Kotlin
 *   and Swift both use IEEE-754 double-precision `toString()` formatting,
 *   so common Pastura values (`0.5`, `0.6` for `event_inject` chance)
 *   serialize identically. Pinned via round-trip tests below.
 *
 * If a future `kotlinx.serialization` release adds type discrimination to
 * [JsonPrimitive] text output, the sanity test fires and forces a
 * canonicalizer-side transform. Until then, no normalization code is
 * required for Pastura's data shapes.
 *
 * Reasoning: Pastura's iOS-only deployment removes the watchOS 32-bit
 * `Int` width concern; iPhone/iPad/Mac Catalyst all use 64-bit Swift `Int`
 * matching Kotlin `Long`. Out-of-band scenarios (Float, very-large Long,
 * scientific notation) get explicit drift-guard tests below.
 */
class CanonicalizerStage2Tests {

    // 5-line sanity guard for the Int/Long no-op contract.
    @Test
    fun intAndLongSerializeToIdenticalText() {
        val asInt = Json.encodeToString(JsonPrimitive.serializer(), JsonPrimitive(42))
        val asLong = Json.encodeToString(JsonPrimitive.serializer(), JsonPrimitive(42L))
        assertEquals(asInt, asLong)
    }

    @Test
    fun intAndLongAreCanonicallyEqual() {
        val intTree = JsonPrimitive(7)
        val longTree = JsonPrimitive(7L)
        assertEquals(
            Canonicalizer.canonicalize(intTree),
            Canonicalizer.canonicalize(longTree),
        )
    }

    @Test
    fun largeLongRoundtripsCleanly() {
        // Long.MAX_VALUE is within Swift Int64 range — production data may
        // hit large counts (epoch ms, scoreboard totals) so guard the
        // boundary.
        val value = Long.MAX_VALUE
        val encoded = Json.encodeToString(JsonPrimitive.serializer(), JsonPrimitive(value))
        assertEquals(value.toString(), encoded)
    }

    @Test
    fun negativeLongRoundtripsCleanly() {
        val value = Long.MIN_VALUE
        val encoded = Json.encodeToString(JsonPrimitive.serializer(), JsonPrimitive(value))
        assertEquals(value.toString(), encoded)
    }

    // -------- Double round-trip --------

    @Test
    fun doubleHalfRoundtripsBitExact() {
        // 0.5 is exactly representable in IEEE-754 binary — primary
        // word_wolf event_inject "chance" value shape.
        val original = 0.5
        val encoded = Json.encodeToString(JsonPrimitive.serializer(), JsonPrimitive(original))
        val decoded = Json.decodeFromString(JsonPrimitive.serializer(), encoded)
        assertEquals(original.toRawBits(), decoded.content.toDouble().toRawBits())
    }

    @Test
    fun doubleSumWithFloatingPointDriftRoundtripsBitExact() {
        // 0.1 + 0.2 famously yields 0.30000000000000004; the bit pattern
        // must survive JSON round-trip in both Kotlin and Swift to claim
        // wire equivalence. This test pins kotlinx's serialize→deserialize.
        val original = 0.1 + 0.2
        val encoded = Json.encodeToString(JsonPrimitive.serializer(), JsonPrimitive(original))
        val decoded = Json.decodeFromString(JsonPrimitive.serializer(), encoded)
        assertEquals(original.toRawBits(), decoded.content.toDouble().toRawBits())
    }

    @Test
    fun doubleNegativeZeroRoundtripsCleanly() {
        // Swift JSONEncoder emits -0.0 as "-0" on some platform builds;
        // kotlinx emits "-0.0". The decoded Double is bit-equal either
        // way; this test pins kotlinx's text shape so any future change
        // surfaces.
        val original = -0.0
        val encoded = Json.encodeToString(JsonPrimitive.serializer(), JsonPrimitive(original))
        val decoded = Json.decodeFromString(JsonPrimitive.serializer(), encoded)
        assertEquals(original.toRawBits(), decoded.content.toDouble().toRawBits())
    }

    @Test
    fun smallScientificNotationRoundtripsBitExact() {
        val original = 1.0e-10
        val encoded = Json.encodeToString(JsonPrimitive.serializer(), JsonPrimitive(original))
        val decoded = Json.decodeFromString(JsonPrimitive.serializer(), encoded)
        assertEquals(original.toRawBits(), decoded.content.toDouble().toRawBits())
    }

    @Test
    fun largeScientificNotationRoundtripsBitExact() {
        val original = 1.0e20
        val encoded = Json.encodeToString(JsonPrimitive.serializer(), JsonPrimitive(original))
        val decoded = Json.decodeFromString(JsonPrimitive.serializer(), encoded)
        assertEquals(original.toRawBits(), decoded.content.toDouble().toRawBits())
    }

    // -------- preservation through Canonicalizer --------

    @Test
    fun canonicalizerLeavesNumericPrimitivesUnchanged() {
        // Stage 1 already passes JsonPrimitive through verbatim; Stage 2
        // does not add any numeric transform. This test pins the no-op
        // so a future code change cannot silently lose numeric precision.
        val cases = listOf(
            JsonPrimitive(0),
            JsonPrimitive(42L),
            JsonPrimitive(-1),
            JsonPrimitive(0.5),
            JsonPrimitive(0.1 + 0.2),
            JsonPrimitive(Long.MAX_VALUE),
        )
        for (case in cases) {
            assertEquals(case, Canonicalizer.canonicalize(case))
        }
    }
}
