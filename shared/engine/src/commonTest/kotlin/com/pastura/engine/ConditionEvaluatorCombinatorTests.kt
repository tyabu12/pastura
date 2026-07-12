package com.pastura.engine

import com.pastura.models.SimulationState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Kotlin port of
 * `Pastura/PasturaTests/Engine/ConditionEvaluatorTests+Combinators.swift` —
 * `&&` / `||` / parens, precedence, left-associativity, short-circuit warning
 * policy, and the parse-only entry point. Separate top-level class (not a Swift
 * "extension") since Kotlin has no cross-file member extension; the two classes
 * share [makeTestScenario].
 */
class ConditionEvaluatorCombinatorTests {
    private val evaluator = ConditionEvaluator()

    // MARK: - Combinators (&& / ||)

    @Test
    fun logicalAndBothTrue() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B", "C"), rounds = 5)
        val state = SimulationState.initial(scenario)
            .copy(currentRound = 3, eliminated = mapOf("A" to false, "B" to false, "C" to false))
        val result = evaluator.evaluate("current_round > 0 && active_count > 1", state, scenario)
        assertTrue(result.value)
    }

    @Test
    fun logicalAndOneFalse() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B"), rounds = 5)
        val state = SimulationState.initial(scenario)
            .copy(currentRound = 3, scores = mapOf("A" to 1, "B" to 0))
        // current_round > 0 (true) && max_score > 5 (false) → false
        assertFalse(evaluator.evaluate("current_round > 0 && max_score > 5", state, scenario).value)
    }

    @Test
    fun logicalOrFirstTrueShortCircuits() {
        val scenario = makeTestScenario(agentNames = listOf("Alice", "Bob"))
        val state = SimulationState.initial(scenario)
            .copy(scores = mapOf("Alice" to 12, "Bob" to 0), voteResults = mapOf("Bob" to 1))
        val result = evaluator.evaluate("max_score >= 10 || vote_winner == \"Alice\"", state, scenario)
        assertTrue(result.value)
    }

    @Test
    fun logicalOrSecondTrue() {
        val scenario = makeTestScenario(agentNames = listOf("Alice", "Bob"))
        val state = SimulationState.initial(scenario)
            .copy(scores = mapOf("Alice" to 5, "Bob" to 0), voteResults = mapOf("Alice" to 2, "Bob" to 1))
        val result = evaluator.evaluate("max_score >= 10 || vote_winner == \"Alice\"", state, scenario)
        assertTrue(result.value)
    }

    // MARK: - Precedence: && binds tighter than ||

    @Test
    fun precedenceAndOverOrTrueViaAnd() {
        // (a > 0 && b > 0) || c > 0  with a=1, b=1, c=0 → true
        val scenario = makeTestScenario(agentNames = listOf("A", "B"), rounds = 5)
        val state = SimulationState.initial(scenario).copy(variables = mapOf("a" to "1", "b" to "1", "c" to "0"))
        assertTrue(evaluator.evaluate("a > 0 && b > 0 || c > 0", state, scenario).value)
    }

    @Test
    fun precedenceAndOverOrTrueViaOr() {
        // (a > 0 && b > 0) || c > 0  with a=0, b=1, c=1 → true (RHS of ||)
        val scenario = makeTestScenario(agentNames = listOf("A", "B"), rounds = 5)
        val state = SimulationState.initial(scenario).copy(variables = mapOf("a" to "0", "b" to "1", "c" to "1"))
        assertTrue(evaluator.evaluate("a > 0 && b > 0 || c > 0", state, scenario).value)
    }

    @Test
    fun precedenceOrAndAndPinsAndTighter() {
        // a > 0 || b > 0 && c > 0  with a=1, b=1, c=0
        // && tighter → a || (b && c) → 1 || (1 && 0) → true
        // Equal-prec left-assoc would parse as (a || b) && c → (1 || 1) && 0 → false.
        val scenario = makeTestScenario(agentNames = listOf("A", "B"), rounds = 5)
        val state = SimulationState.initial(scenario).copy(variables = mapOf("a" to "1", "b" to "1", "c" to "0"))
        assertTrue(evaluator.evaluate("a > 0 || b > 0 && c > 0", state, scenario).value)
    }

    // MARK: - Parentheses

    @Test
    fun parensOverridePrecedence() {
        // (a > 0 || b > 0) && c > 0  with a=1, b=0, c=0 → false
        // Without parens (&& tighter): a || (b && c) → 1 || 0 → true.
        val scenario = makeTestScenario(agentNames = listOf("A", "B"), rounds = 5)
        val state = SimulationState.initial(scenario).copy(variables = mapOf("a" to "1", "b" to "0", "c" to "0"))
        assertFalse(evaluator.evaluate("(a > 0 || b > 0) && c > 0", state, scenario).value)
    }

    @Test
    fun parensWithCombinatorMixingComparisonAndString() {
        val scenario = makeTestScenario(agentNames = listOf("Alice", "Bob"), rounds = 5)
        val state = SimulationState.initial(scenario).copy(
            scores = mapOf("Alice" to 3, "Bob" to 1),
            voteResults = mapOf("Alice" to 2, "Bob" to 0),
            currentRound = 4,
        )
        val result = evaluator.evaluate(
            "(max_score < 5 || vote_winner == \"Alice\") && current_round >= 3",
            state,
            scenario,
        )
        assertTrue(result.value)
    }

    @Test
    fun deeplyNestedParensReduceCorrectly() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B"), rounds = 5)
        val state = SimulationState.initial(scenario).copy(currentRound = 1)
        assertTrue(evaluator.evaluate("(((current_round == 1)))", state, scenario).value)
    }

    // MARK: - Left-associativity

    @Test
    fun leftAssociativeOrChain() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B"), rounds = 5)
        val trueState = SimulationState.initial(scenario).copy(variables = mapOf("a" to "0", "b" to "0", "c" to "1"))
        assertTrue(evaluator.evaluate("a > 0 || b > 0 || c > 0", trueState, scenario).value)
        val falseState = SimulationState.initial(scenario).copy(variables = mapOf("a" to "0", "b" to "0", "c" to "0"))
        assertFalse(evaluator.evaluate("a > 0 || b > 0 || c > 0", falseState, scenario).value)
    }

    @Test
    fun leftAssociativeAndChain() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B"), rounds = 5)
        val trueState = SimulationState.initial(scenario).copy(variables = mapOf("a" to "1", "b" to "1", "c" to "1"))
        assertTrue(evaluator.evaluate("a > 0 && b > 0 && c > 0", trueState, scenario).value)
        val falseState = SimulationState.initial(scenario).copy(variables = mapOf("a" to "1", "b" to "0", "c" to "1"))
        assertFalse(evaluator.evaluate("a > 0 && b > 0 && c > 0", falseState, scenario).value)
    }

    // MARK: - Short-circuit evaluation policy

    @Test
    fun shortCircuitFalseAndAbsentSuppressesWarning() {
        // LHS false; RHS uses runtime-absent vote_winner. Per Swift-style
        // short-circuit policy, RHS is NOT resolved, so its warning never appears.
        val scenario = makeTestScenario(agentNames = listOf("Alice", "Bob"))
        val state = SimulationState.initial(scenario).copy(currentRound = 1)
        val result = evaluator.evaluate(
            "current_round > 999 && vote_winner == \"Alice\"",
            state,
            scenario,
        )
        assertFalse(result.value)
        assertTrue(result.warnings.isEmpty())
    }

    @Test
    fun shortCircuitTrueOrAbsentSuppressesWarning() {
        val scenario = makeTestScenario(agentNames = listOf("Alice", "Bob"))
        val state = SimulationState.initial(scenario).copy(currentRound = 1)
        val result = evaluator.evaluate(
            "current_round == 1 || vote_winner == \"Alice\"",
            state,
            scenario,
        )
        assertTrue(result.value)
        assertTrue(result.warnings.isEmpty())
    }

    @Test
    fun dualAbsentVariablesNoShortCircuitBothWarnings() {
        // LHS false-with-warning (scores.Nobody absent), RHS not short-circuited
        // (|| looks at the right side when LHS is false), RHS also false-with-warning.
        val scenario = makeTestScenario(agentNames = listOf("Alice", "Bob"))
        val state = SimulationState.initial(scenario)
        val result = evaluator.evaluate(
            "scores.Nobody > 0 || vote_winner == \"X\"",
            state,
            scenario,
        )
        assertFalse(result.value)
        assertEquals(2, result.warnings.size)
    }

    // MARK: - Quote awareness across new tokens

    @Test
    fun combinatorInsideQuotedRHSIsNotSplit() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B"))
        val state = SimulationState.initial(scenario).copy(variables = mapOf("topic" to "tea && coffee"))
        val result = evaluator.evaluate("topic == \"tea && coffee\"", state, scenario)
        assertTrue(result.value)
    }

    @Test
    fun parensInsideQuotedRHSIsNotSplit() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B"))
        val state = SimulationState.initial(scenario).copy(variables = mapOf("tag" to "(foo)"))
        val result = evaluator.evaluate("tag == \"(foo)\"", state, scenario)
        assertTrue(result.value)
    }

    // MARK: - Parse errors

    @Test
    fun emptyParensThrows() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B"))
        val state = SimulationState.initial(scenario)
        assertFailsWith<SimulationException> {
            evaluator.evaluate("()", state, scenario)
        }
    }

    @Test
    fun mismatchedOpenParenThrows() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B"))
        val state = SimulationState.initial(scenario)
        assertFailsWith<SimulationException> {
            evaluator.evaluate("(current_round == 1 && max_score > 0", state, scenario)
        }
    }

    @Test
    fun mismatchedCloseParenThrows() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B"))
        val state = SimulationState.initial(scenario)
        assertFailsWith<SimulationException> {
            evaluator.evaluate("current_round == 1) && max_score > 0", state, scenario)
        }
    }

    @Test
    fun danglingAndOperatorThrows() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B"))
        val state = SimulationState.initial(scenario)
        assertFailsWith<SimulationException> {
            evaluator.evaluate("current_round == 1 &&", state, scenario)
        }
    }

    @Test
    fun leadingOrOperatorThrows() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B"))
        val state = SimulationState.initial(scenario)
        assertFailsWith<SimulationException> {
            evaluator.evaluate("|| current_round == 1", state, scenario)
        }
    }

    // MARK: - Parse-only entry point (used by ScenarioValidator)

    @Test
    fun parseAcceptsValidExpression() {
        // No throw = pass.
        evaluator.parse("current_round == 1 && (max_score > 0 || vote_winner == \"X\")")
    }

    @Test
    fun parseRejectsMalformedExpression() {
        assertFailsWith<SimulationException> {
            evaluator.parse("(current_round == 1")
        }
    }
}
