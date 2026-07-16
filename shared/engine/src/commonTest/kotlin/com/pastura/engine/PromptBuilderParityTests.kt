package com.pastura.engine

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

/**
 * Cross-language ordering parity for [PromptBuilder.formatScoreboard], following
 * the #1063 Stage-2-pre precedent: normalize what you can, and **pin the accepted
 * divergences with a test** so Stage 4 inherits a known list instead of a
 * surprise.
 *
 * ## How the Swift expectations here were obtained
 *
 * Measured, not recalled — a `swift` script run on this branch sorting the same
 * inputs with `sorted { $0 < $1 }`:
 *
 * ```
 * ["Bob","Alice","carol"]                  -> Alice|Bob|carol
 * ["ボブ","アリス","太郎"]                    -> アリス|ボブ|太郎
 * ["🍎","\u{FFFD}","Zed"]                  -> Zed|\u{FFFD}|🍎
 * ["e\u{0301}clair","\u{00E9}clair","zebra"] -> zebra|éclair|éclair
 * "\u{00E9}" == "e\u{0301}"                -> true
 * ```
 *
 * ## The root cause
 *
 * Swift's `String: Comparable` orders by **Unicode scalar (code point)** and
 * compares under **canonical equivalence**. Kotlin's [String.compareTo] orders by
 * **UTF-16 code unit** with **no normalization**. Two consequences:
 *
 * 1. **Surrogates sort low.** A supplementary-plane character (emoji, U+1F34E)
 *    starts with a high surrogate (U+D83C), which is numerically *below* BMP
 *    characters like U+FFFD — so Kotlin places it first where Swift places it
 *    last.
 * 2. **No canonical equivalence.** Precomposed `é` (U+00E9) and decomposed `e` +
 *    U+0301 are equal to Swift and different to Kotlin.
 *
 * ## Why this is not "fixed" here
 *
 * A code-point comparator would close (1) but not (2) — common Kotlin has no
 * Unicode normalizer — and a half-fix reads as parity while still diverging. The
 * divergence is also **reachable, not theoretical**: persona names carry no
 * charset constraint (`ScenarioConventions.isValidFieldName` gates *output field*
 * names; the validator only checks persona count), so `name: 🍎` is a legal
 * scenario. Recorded on #501 as a Stage-4 landmine.
 *
 * **If a test here starts failing, do not "fix" the expectation** — it means the
 * ordering contract moved, which is exactly the signal Stage 4 needs.
 */
class PromptBuilderParityTests {

    private val builder = PromptBuilder()

    /** Sort keys the way [PromptBuilder.formatScoreboard] does. */
    private fun order(vararg names: String): List<String> =
        builder.formatScoreboard(names.associateWith { 0 })
            .removeSurrounding("{", "}")
            .split(", ")
            .map { it.substringBefore("\": ").removePrefix("\"") }

    // MARK: - Agreement: every realistic persona name

    @Test
    fun asciiNamesOrderIdenticallyToSwift() {
        // Swift measured: Alice|Bob|carol (uppercase before lowercase — code point
        // order, NOT case-insensitive collation).
        assertEquals(listOf("Alice", "Bob", "carol"), order("Bob", "Alice", "carol"))
    }

    @Test
    fun japaneseNamesOrderIdenticallyToSwift() {
        // Swift measured: アリス|ボブ|太郎. Kana and common kanji are BMP, so UTF-16
        // code units and code points coincide — every bundled preset lives here.
        assertEquals(listOf("アリス", "ボブ", "太郎"), order("ボブ", "アリス", "太郎"))
    }

    // MARK: - Accepted divergence 1: supplementary-plane names

    @Test
    fun supplementaryPlaneNamesDivergeFromSwiftAndThatIsPinned() {
        val kotlinOrder = order("🍎", "�", "Zed")
        val swiftMeasured = listOf("Zed", "�", "🍎")

        assertEquals(listOf("Zed", "🍎", "�"), kotlinOrder, "Kotlin sorts by UTF-16 code unit")
        assertNotEquals(swiftMeasured, kotlinOrder, "ACCEPTED divergence — see the class doc")
        // Both agree the BMP letter leads; only the emoji's rank differs.
        assertEquals("Zed", kotlinOrder.first())
    }

    // MARK: - Accepted divergence 2: canonical equivalence

    @Test
    fun decomposedAndPrecomposedAreDistinctToKotlinButEqualToSwift() {
        val precomposed = "éclair"
        val decomposed = "éclair"
        // Swift measured: "\u{00E9}" == "e\u{0301}" -> true.
        assertNotEquals(precomposed, decomposed, "ACCEPTED divergence — Kotlin has no canonical equivalence")

        // Consequence for the scoreboard: Swift collapses these to ONE key with a
        // last-write-wins score; Kotlin keeps TWO. A shared-scenario author who
        // typed one name two ways would get different scoreboards per engine.
        val rendered = builder.formatScoreboard(mapOf(precomposed to 1, decomposed to 2))
        assertEquals(2, rendered.split("\": ").size - 1, "Kotlin keeps both spellings as distinct keys")
    }

    @Test
    fun accentedNamesSortAfterAsciiInBothLanguages() {
        // The one row of divergence 2 that DOES agree, and worth pinning: é
        // (U+00E9 = 233) is above 'z' (122) as both a code point and a UTF-16 code
        // unit, so the precomposed form ranks after ASCII on both sides. Swift
        // measured: zebra|éclair|éclair.
        val kotlinOrder = order("éclair", "zebra")
        assertEquals(listOf("zebra", "éclair"), kotlinOrder)
    }

    // MARK: - The scoreboard's own contract holds regardless

    @Test
    fun renderingStaysDeterministicEvenForDivergentNames() {
        // Determinism is a Kotlin-side contract and is NOT what diverges — the two
        // engines disagree with each other, but each is stable with itself. That is
        // what makes the divergence a Stage-4 transcript-diff finding rather than a
        // flake.
        val a = builder.formatScoreboard(linkedMapOf("🍎" to 1, "�" to 2, "Zed" to 3))
        val b = builder.formatScoreboard(linkedMapOf("Zed" to 3, "🍎" to 1, "�" to 2))
        assertEquals(a, b)
        assertTrue(a.startsWith("""{"Zed": 3"""))
        assertFalse(a.contains("\n"))
    }
}
