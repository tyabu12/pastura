package com.pastura.models

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Pins the format-substitution contract of [substitute] and [Rendering].
 *
 * These run on the `jvmTest` and `macosArm64Test` rungs, where
 * [localizedFormat] is identity (no catalog is present in either), so
 * `Rendering.render()` is observably `substitute(format, args)` here. The
 * catalog-resolving behaviour of the `appleMain` actual can only be observed
 * inside the iOS app bundle and is therefore out of scope for this suite.
 */
class MessageRenderingTests {

    @Test
    fun bareSpecifiersConsumeArgumentsInOrder() {
        assertEquals(
            "Scenario: 'a' has 3 items",
            substitute("Scenario: '%@' has %lld items", listOf("a", 3)),
        )
    }

    @Test
    fun positionalSpecifiersReadTheirIndex() {
        assertEquals(
            "a 3",
            substitute("%1\$@ %2\$lld", listOf("a", 3)),
        )
    }

    @Test
    fun positionalSpecifiersMayReorderArguments() {
        // The `ja` catalog values reorder arguments; this is the shape that
        // makes localization possible at all.
        assertEquals(
            "second first",
            substitute("%2\$@ %1\$@", listOf("first", "second")),
        )
    }

    @Test
    fun substitutedArgumentTextIsNotRescanned() {
        // Scenario text is user-supplied and may itself contain `%@`.
        assertEquals(
            "value=%@ rest=x",
            substitute("value=%@ rest=%@", listOf("%@", "x")),
        )
        assertEquals(
            "value=%1\$@ rest=x",
            substitute("value=%@ rest=%@", listOf("%1\$@", "x")),
        )
    }

    @Test
    fun outOfRangePositionalIndexIsLeftLiteral() {
        assertEquals(
            "a %2\$@",
            substitute("%1\$@ %2\$@", listOf("a")),
        )
    }

    @Test
    fun leftoverSpecifiersAreLeftLiteral() {
        assertEquals(
            "a %@",
            substitute("%@ %@", listOf("a")),
        )
    }

    @Test
    fun surplusArgumentsAreIgnored() {
        assertEquals(
            "a",
            substitute("%@", listOf("a", "b", 7)),
        )
    }

    @Test
    fun unrecognisedSpecifiersAreLeftLiteral() {
        assertEquals(
            "%d a",
            substitute("%d %@", listOf("a")),
        )
        assertEquals(
            "100% done a",
            substitute("100% done %@", listOf("a")),
        )
        assertEquals(
            "trailing %",
            substitute("trailing %", emptyList()),
        )
    }

    @Test
    fun bareAndPositionalCountersAreIndependent() {
        // Mixing is unspecified in `String(format:)`; the rule here is that a
        // bare specifier advances only its own sequential counter.
        assertEquals(
            "a a",
            substitute("%@ %1\$@", listOf("a", "b")),
        )
    }

    @Test
    fun renderDelegatesToSubstituteWhereNoCatalogExists() {
        val rendering = Rendering("%@ needs %lld", listOf("phase", 2))
        assertEquals(substitute(rendering.format, rendering.args), rendering.render())
        assertEquals("phase needs 2", rendering.render())
    }

    @Test
    fun emptyFormatAndArgumentsRenderEmpty() {
        assertEquals("", substitute("", emptyList()))
        assertEquals("", Rendering("", emptyList()).render())
        assertEquals("literal", substitute("literal", emptyList()))
    }
}
