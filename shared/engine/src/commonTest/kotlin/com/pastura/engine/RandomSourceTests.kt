package com.pastura.engine

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

/**
 * Pins the ADR-023 S3b RNG seam to known-answer vectors shared with the Swift
 * `Pastura/PasturaTests/Engine/RandomSourceTests.swift`. Every vector below is
 * the same literal on both sides: a change to either engine that breaks one is
 * a parity break, whatever the single-language tests say.
 */
class RandomSourceTests {

    @Test
    fun splitMix64MatchesReferenceVectorsForSeedZero() {
        val source = SplitMix64RandomSource(seed = 0uL)
        assertEquals(
            listOf(0xE220A8397B1DCDAFuL, 0x6E789E6AA1B965F4uL, 0x06C45D188009454FuL, 0xF88BB8A8724C81ECuL),
            List(4) { source.nextUInt64() },
        )
    }

    @Test
    fun splitMix64MatchesReferenceVectorsForNonZeroSeed() {
        val source = SplitMix64RandomSource(seed = 0x123456789ABCDEF0uL)
        assertEquals(
            listOf(0x161922C645CE50E8uL, 0xAD760CAFA1697B60uL, 0x3501FF44902CA50DuL, 0x417CB9A826D831DFuL),
            List(4) { source.nextUInt64() },
        )
    }

    /**
     * [index] is `% n` and nothing cleverer — the Swift twin pins the same four
     * indices for the same seed.
     */
    @Test
    fun indexReducesByModulo() {
        val source = SplitMix64RandomSource(seed = 0uL)
        assertEquals(listOf(2, 1, 2, 4), List(4) { source.index(below = 7) })
    }

    /** [unit] takes the top 53 bits, so the doubles are exact and shared. */
    @Test
    fun unitTakesTopFiftyThreeBits() {
        val source = SplitMix64RandomSource(seed = 0uL)
        assertEquals(
            listOf(0.8833108082136426, 0.43152799704850997, 0.026433771592597743, 0.9708819781538285),
            List(4) { source.unit() },
        )
    }

    /** The same seed restarts the same stream; a different seed does not. */
    @Test
    fun seedDeterminesTheStream() {
        val first = SplitMix64RandomSource(seed = 42uL)
        val same = SplitMix64RandomSource(seed = 42uL)
        val other = SplitMix64RandomSource(seed = 43uL)
        val stream = List(8) { first.nextUInt64() }
        assertEquals(stream, List(8) { same.nextUInt64() })
        assertNotEquals(stream, List(8) { other.nextUInt64() })
    }

    /** An empty pool is a handler bug, not a runtime condition to absorb. */
    @Test
    fun indexRejectsAnEmptyPool() {
        assertFailsWith<IllegalArgumentException> {
            SplitMix64RandomSource(seed = 0uL).index(below = 0)
        }
    }

    /**
     * The production source draws from the platform generator: helper values
     * stay in range and the raw stream is not constant.
     */
    @Test
    fun systemSourceHelpersStayInRange() {
        val source = SystemRandomSource()
        repeat(64) {
            assertTrue(source.index(below = 5) in 0..4)
            val unit = source.unit()
            assertTrue(unit >= 0.0 && unit < 1.0)
        }
        assertTrue(List(16) { source.nextUInt64() }.toSet().size > 1)
    }
}
