package com.pastura.engine

import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * Parity spec for [RelationshipVerbalizer] — the raw-affinity-matrix → prose
 * renderer injected into `relationship_update` agent prompts (#910). Mirrors
 * the Swift `RelationshipVerbalizerTests`; assertions use partial `contains`
 * matching so future phrasing tweaks don't break on exact wording.
 */
class RelationshipVerbalizerTests {

    @Test
    fun emptyMatrixProducesEmptyString() {
        assertTrue(RelationshipVerbalizer.summarize(emptyMap(), language = "ja").isEmpty())
        assertTrue(RelationshipVerbalizer.summarize(emptyMap(), language = "en").isEmpty())
    }

    @Test
    fun belowThresholdIsOmitted() {
        // |1| < mentionThreshold (2), so nothing is verbalized.
        assertTrue(RelationshipVerbalizer.summarize(mapOf("Bob" to 1), language = "en").isEmpty())
        assertTrue(RelationshipVerbalizer.summarize(mapOf("Bob" to -1), language = "en").isEmpty())
        assertTrue(RelationshipVerbalizer.summarize(mapOf("Bob" to 0), language = "ja").isEmpty())
    }

    @Test
    fun atThresholdIsMentioned() {
        // |2| == mentionThreshold, so it surfaces (inclusive boundary).
        assertTrue(RelationshipVerbalizer.summarize(mapOf("Bob" to 2), language = "en").isNotEmpty())
        assertTrue(RelationshipVerbalizer.summarize(mapOf("Bob" to -2), language = "en").isNotEmpty())
    }

    @Test
    fun positiveScoreReadsAsWarmth() {
        val en = RelationshipVerbalizer.summarize(mapOf("Bob" to 3), language = "en")
        assertTrue(en.contains("Bob"))
        assertTrue(en.contains("warmly"))
        val ja = RelationshipVerbalizer.summarize(mapOf("Bob" to 3), language = "ja")
        assertTrue(ja.contains("Bob"))
        assertTrue(ja.contains("好感"))
    }

    @Test
    fun negativeScoreReadsAsWariness() {
        val en = RelationshipVerbalizer.summarize(mapOf("Ryuji" to -3), language = "en")
        assertTrue(en.contains("Ryuji"))
        assertTrue(en.contains("wary"))
        val ja = RelationshipVerbalizer.summarize(mapOf("Ryuji" to -3), language = "ja")
        assertTrue(ja.contains("Ryuji"))
        assertTrue(ja.contains("警戒"))
    }

    @Test
    fun mentionsAreSortedByNameForDeterminism() {
        // Zoe warm (+2), Ada wary (-2). Deterministic output orders by name,
        // so "Ada" must precede "Zoe" regardless of map iteration order.
        val summary = RelationshipVerbalizer.summarize(mapOf("Zoe" to 2, "Ada" to -2), language = "en")
        val adaIndex = summary.indexOf("Ada")
        val zoeIndex = summary.indexOf("Zoe")
        assertTrue(adaIndex >= 0 && zoeIndex >= 0)
        assertTrue(adaIndex < zoeIndex)
    }

    @Test
    fun mixesThresholdAndBelowThresholdEntries() {
        // Only the two notable entries appear; the |1| entry is dropped.
        val summary = RelationshipVerbalizer.summarize(
            mapOf("Ada" to 2, "Bob" to 1, "Zoe" to -4),
            language = "en",
        )
        assertTrue(summary.contains("Ada"))
        assertTrue(summary.contains("Zoe"))
        assertTrue(!summary.contains("Bob"))
    }
}
