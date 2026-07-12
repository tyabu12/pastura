package com.pastura.engine

import com.pastura.models.SimulationState
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Cross-language numeric-detection and string-ordering parity for the
 * `ConditionEvaluator` port (#501 Stage 2-pre, critic Axis 3).
 *
 * These have no Swift counterpart — they lock behaviours the ported Swift test
 * set (CJK *equality* + ASCII tie-break) does not exercise, precisely because
 * those cases pass identically in both languages and mask the two primitives
 * that genuinely diverge:
 *
 * 1. **Numeric detection.** Neither raw parser is a stable cross-language
 *    predicate: Kotlin `String.toDoubleOrNull()` accepts `"Infinity"` / `"NaN"` /
 *    type-suffixed literals (`"1f"`) that are not plain decimals, while Swift
 *    `Double(String)` in turn accepts hex-floats (`"0x1p4"`) Kotlin rejects. The
 *    port sidesteps both by matching a fixed decimal-literal regex
 *    (`ConditionEvaluator.numericLiteralRegex`), so a token is numeric iff it is a
 *    plain optionally-signed decimal with optional fraction / exponent — identical
 *    in both languages. The tests below pin: clean decimals / exponents / negatives
 *    ARE numeric; `Infinity` / suffixed literals are NOT (treated as strings —
 *    normalizing Kotlin's laxer acceptance to the strict grammar). Out-of-domain
 *    for real scenario operands, which are integers or names.
 * 2. **String ordering.** Kotlin `String.compareTo` is UTF-16 code-unit order;
 *    Swift `String <` is Unicode-scalar order. They agree across the entire BMP
 *    (all CJK/kana), diverging only on supplementary-plane code points and
 *    canonical-equivalence forms — out-of-domain for agent names. The CJK
 *    ordering tests below lock the in-domain BMP parity.
 */
class ConditionEvaluatorParityTests {
    private val evaluator = ConditionEvaluator()

    // MARK: - Numeric detection — in-domain literals ARE numeric

    @Test
    fun cleanDecimalLiteralComparesNumerically() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B"))
        val state = SimulationState.initial(scenario).copy(variables = mapOf("x" to "3.5"))
        // 3.5 < 4 numerically (string compare would give "3.5" < "4" → also true,
        // so pair it with a case string-compare would get WRONG):
        assertTrue(evaluator.evaluate("x < 4", state, scenario).value)
        // "3.5" > "10" lexicographically ('3' > '1') but 3.5 < 10 numerically.
        val state2 = SimulationState.initial(scenario).copy(variables = mapOf("x" to "3.5"))
        assertTrue(evaluator.evaluate("x < 10", state2, scenario).value)
    }

    @Test
    fun exponentLiteralComparesNumerically() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B"))
        val state = SimulationState.initial(scenario).copy(variables = mapOf("y" to "1e2"))
        // 1e2 == 100 numerically. String compare "1e2" == "100" would be false.
        assertTrue(evaluator.evaluate("y == 100", state, scenario).value)
    }

    @Test
    fun negativeLiteralComparesNumerically() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B"), rounds = 5)
        val state = SimulationState.initial(scenario).copy(currentRound = 0)
        // The literal `-1` on the RHS must tokenize as one operand and compare numerically.
        assertTrue(evaluator.evaluate("current_round > -1", state, scenario).value)
    }

    // MARK: - Numeric detection — accepted divergence: non-decimal → string path

    @Test
    fun infinityLiteralTreatedAsStringNotNumber() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B"))
        val state = SimulationState.initial(scenario).copy(variables = mapOf("v" to "Infinity"))
        // Kotlin's toDoubleOrNull("Infinity") == ∞, but the port's decimal regex
        // rejects it → string path. Equality against the quoted string holds.
        assertTrue(evaluator.evaluate("v == \"Infinity\"", state, scenario).value)
    }

    @Test
    fun typeSuffixedLiteralTreatedAsStringNotNumber() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B"))
        val state = SimulationState.initial(scenario).copy(variables = mapOf("v" to "1f"))
        // Kotlin's `"1f".toDoubleOrNull()` == 1.0 (Java accepts the trailing
        // `f`/`d` suffix), so RAW numeric detection would make `v == 1` TRUE. The
        // port's decimal regex rejects "1f" → string path → `v == 1` is FALSE.
        // This is the regex's core job: normalize Kotlin's laxer `toDoubleOrNull`
        // to a strict decimal grammar. Out-of-domain (real operands are integers
        // or names); pinned so the behaviour is deliberate, not silent.
        assertFalse(evaluator.evaluate("v == 1", state, scenario).value)
        // It IS equal to itself as a string:
        assertTrue(evaluator.evaluate("v == \"1f\"", state, scenario).value)
    }

    // MARK: - String ordering — in-domain BMP parity (UTF-16 == scalar order)

    @Test
    fun cjkTieBreakMatchesScalarOrder() {
        // Tie 1-1: (count desc, name desc) → higher code unit wins.
        // ア U+30A2 < ミ U+30DF, so "ミサキ" is the deterministic winner. UTF-16
        // and Unicode-scalar order agree across the BMP.
        val scenario = makeTestScenario(agentNames = listOf("アキラ", "ミサキ"))
        val state = SimulationState.initial(scenario).copy(voteResults = mapOf("アキラ" to 1, "ミサキ" to 1))
        assertTrue(evaluator.evaluate("vote_winner == \"ミサキ\"", state, scenario).value)
    }

    @Test
    fun cjkStringLessThanMatchesScalarOrder() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B"))
        val state = SimulationState.initial(scenario).copy(variables = mapOf("a" to "アキラ"))
        // "アキラ" < "ミサキ" (ア < ミ). BMP — both orderings agree.
        assertTrue(evaluator.evaluate("a < \"ミサキ\"", state, scenario).value)
    }
}
