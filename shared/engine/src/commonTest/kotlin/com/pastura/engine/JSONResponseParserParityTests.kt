package com.pastura.engine

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Pins the value-normalization contract against Swift — where the two engines
 * agree, and the one place they deliberately still do not.
 *
 * ## The Bool-bridge divergence — closed by #1150
 *
 * Swift's `JSONResponseParser.normalizeValues` used to check `value as? Bool`
 * **before** `as? NSNumber`, intending to catch JSON `true`/`false`. The guard
 * was wider than the intent: `NSNumber` -> `Bool` bridging succeeds for exactly
 * 0 and 1, so the numbers `0` / `1` (and `0.0` / `1.0`) were swallowed and
 * normalized to `"false"` / `"true"`. This port never replicated it —
 * replicating an unintended Foundation bridging quirk would have cemented it as
 * a cross-language contract, in a language with no `NSNumber` to justify it.
 *
 * #1150 fixed the Swift side (discriminate on `CFBooleanGetTypeID` rather than
 * on cast success), so the integer cases agree now and are pinned on both
 * sides — this file is no longer their only coverage.
 *
 * ## The residual divergence — float formatting, still open
 *
 * The fix did NOT make `1.0` / `0.0` agree: Swift yields `"1"` / `"0"` because
 * `NSNumber.stringValue` normalizes the literal, while kotlinx's
 * `JsonPrimitive.content` preserves it. Same number, different text — and
 * `fields` is a `[String: String]`, so the text is what ships. Those two cases
 * only changed divergence *class*, from the Bool bridge to formatting; they
 * live under "Known Kotlin-side literal-preservation differences" below,
 * alongside `1e3`. Out of #1150's scope — ADR-023 Stage 4 should decide the
 * formatting rule once, for both engines.
 *
 * ## Reachability
 *
 * Low but real. `GBNFGrammarBuilder` constrains every field to `string`, so the
 * grammar-constrained path yields string values and never reaches the numeric
 * branch. A number can still arrive from an unconstrained call (`schema == nil`)
 * or a generation that breaks the grammar.
 *
 * **If a test here fails, do not "fix" the expectation** — it means the
 * normalization contract moved.
 */
class JSONResponseParserParityTests {

    private val parser = JSONResponseParser()

    private fun field(raw: String): String? = parser.parse("""{"a":$raw}""").fields["a"]

    // MARK: - The former Bool-bridge window: numeric 0 and 1 (agreeing since #1150)

    @Test
    fun numericOneAgreesWithSwift() {
        // Swift returned "true" before #1150.
        assertEquals("1", field("1"))
    }

    @Test
    fun numericZeroAgreesWithSwift() {
        // Swift returned "false" before #1150.
        assertEquals("0", field("0"))
    }

    // MARK: - The agreeing range — outside the Bool-bridge window

    @Test
    fun numbersOutsideTheZeroOneWindowAgreeWithSwift() {
        assertEquals("2", field("2"))
        assertEquals("-1", field("-1"))
        assertEquals("0.5", field("0.5"))
        assertEquals("42", field("42"))
        assertEquals("3.14", field("3.14"))
    }

    @Test
    fun realBooleansAgreeWithSwift() {
        // The branch's actual intent, and the part that was correct on both sides
        // all along — #1150 preserved it via the CFBooleanGetTypeID check.
        assertEquals("true", field("true"))
        assertEquals("false", field("false"))
    }

    @Test
    fun stringsAgreeWithSwift() {
        assertEquals("hi", field("\"hi\""))
        // A string that LOOKS numeric must stay a string on both sides.
        assertEquals("1", field("\"1\""))
    }

    // MARK: - Known Kotlin-side literal-preservation differences

    @Test
    fun floatOneDivergesInFormattingNotValue() {
        // Swift measured post-#1150: "1" — NSNumber.stringValue drops the `.0`.
        // Before #1150 this case diverged for a different reason (the Bool
        // branch caught it and returned "true"); the fix moved it into the
        // formatting class below, it did not close it.
        assertEquals("1.0", field("1.0"))
    }

    @Test
    fun floatZeroDivergesInFormattingNotValue() {
        // Swift measured post-#1150: "0". Same formatting class as `1.0` above.
        assertEquals("0.0", field("0.0"))
    }

    @Test
    fun exponentNotationDivergesInFormattingNotValue() {
        // Swift's NSNumber.stringValue normalizes `1e3` -> "1000"; kotlinx's
        // JsonPrimitive.content preserves the source literal. Same number, different
        // text — and `fields` is [String: String], so the TEXT is what ships.
        // Pinned as an accepted divergence rather than normalized: parsing to a
        // number and re-rendering would introduce float-formatting drift of its own
        // (Swift measured `1.0e-7` -> "1e-07"), trading one divergence for a subtler
        // one. Stage 4 should decide the rule once, for both engines.
        assertEquals("1e3", field("1e3"))
    }

    @Test
    fun largeIntegersArePreservedExactly() {
        // Swift measured: "10000000000". Agrees — but pinned because a port that
        // routed through Double would silently lose precision past 2^53.
        assertEquals("10000000000", field("10000000000"))
        assertEquals("9007199254740993", field("9007199254740993"))
    }
}
