package com.pastura.engine

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Pins the ONE deliberate value-normalization divergence from Swift — a Swift
 * bug this port does not copy.
 *
 * ## What Swift does
 *
 * `JSONResponseParser.normalizeValues` checks `value as? Bool` **before**
 * `as? NSNumber`, commented "Check Bool before NSNumber — Bool bridges to
 * NSNumber in ObjC". The intent is to catch JSON `true`/`false`. The effect is
 * wider: `NSNumber` -> `Bool` bridging succeeds for exactly 0 and 1, so numeric
 * `0` and `1` (and `0.0` / `1.0`) are swallowed by the Bool branch.
 *
 * Measured on this branch, replicating Swift's exact branch order:
 *
 * ```
 * 0    -> "false"   (__NSCFNumber)      2    -> "2"
 * 1    -> "true"    (__NSCFNumber)      -1   -> "-1"
 * 0.0  -> "false"   (__NSCFNumber)      0.5  -> "0.5"
 * 1.0  -> "true"    (__NSCFNumber)      true -> "true"   (__NSCFBoolean)
 * ```
 *
 * ## Why Kotlin does not replicate it
 *
 * ADR-023 §6 makes the Swift test files the executable spec — and that spec does
 * **not** pin this. The only numeric case is `{"score": 42, "ratio": 3.14}`,
 * values that (by luck) sidestep the 0/1 range, and no test anywhere passes a
 * numeric 0 or 1 through the parser. The behaviour is untested, incidental, and
 * contradicts its own test's name: "Numeric values normalized to String" is
 * exactly what does *not* happen to `1`.
 *
 * Replicating it would cement an unintended Foundation bridging quirk as a
 * **cross-language contract**, in a language with no `NSNumber` to justify it.
 * Reported on #501 as a suspected Swift-side bug; if Swift is fixed, this
 * divergence closes with no change here.
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

    // MARK: - The divergent range: numeric 0 and 1

    @Test
    fun numericOneStaysNumericUnlikeSwift() {
        // Swift measured: "true".
        assertEquals("1", field("1"))
    }

    @Test
    fun numericZeroStaysNumericUnlikeSwift() {
        // Swift measured: "false".
        assertEquals("0", field("0"))
    }

    @Test
    fun floatOneStaysNumericUnlikeSwift() {
        // Swift measured: "true". Note Kotlin also preserves the literal `.0`,
        // where Swift's NSNumber.stringValue would render "1" for 1.0 had the
        // Bool branch not caught it first.
        assertEquals("1.0", field("1.0"))
    }

    @Test
    fun floatZeroStaysNumericUnlikeSwift() {
        // Swift measured: "false".
        assertEquals("0.0", field("0.0"))
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
        // The branch's actual intent, and the part that is correct on both sides.
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
