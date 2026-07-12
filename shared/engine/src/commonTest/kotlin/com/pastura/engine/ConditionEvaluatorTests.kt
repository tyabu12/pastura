package com.pastura.engine

import com.pastura.models.SimulationState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Kotlin port of `Pastura/PasturaTests/Engine/ConditionEvaluatorTests.swift`.
 *
 * This is the cross-language executable spec for the `conditional`-phase `if:`
 * DSL evaluator (#501 Stage 2-pre / ADR-023 §6): the same behaviours the Swift
 * `ConditionEvaluator` guarantees must hold in the Kotlin port. Combinator (`&&`
 * / `||` / parens) coverage lives in [ConditionEvaluatorCombinatorTests]; the
 * cross-language numeric / ordering parity cases live in
 * [ConditionEvaluatorParityTests].
 *
 * Parse-time errors throw [SimulationException] (the Kotlin Engine's `Throwable`
 * carrier for the sealed `SimulationError`), NOT `SimulationError` directly —
 * that type is a non-`Throwable` sealed class in `shared/models`.
 */
class ConditionEvaluatorTests {
    private val evaluator = ConditionEvaluator()

    // MARK: - Numeric comparison — derived variables

    @Test
    fun maxScoreGTE() {
        val scenario = makeTestScenario(agentNames = listOf("Alice", "Bob"))
        val state = SimulationState.initial(scenario).copy(scores = mapOf("Alice" to 10, "Bob" to 3))
        assertTrue(evaluator.evaluate("max_score >= 10", state, scenario).value)
        assertFalse(evaluator.evaluate("max_score >= 11", state, scenario).value)
    }

    @Test
    fun minScoreLT() {
        val scenario = makeTestScenario(agentNames = listOf("Alice", "Bob"))
        val state = SimulationState.initial(scenario).copy(scores = mapOf("Alice" to 10, "Bob" to 3))
        assertTrue(evaluator.evaluate("min_score < 5", state, scenario).value)
    }

    @Test
    fun eliminatedCountEQ() {
        val scenario = makeTestScenario(agentNames = listOf("Alice", "Bob", "Charlie"))
        val state = SimulationState.initial(scenario)
            .copy(eliminated = mapOf("Alice" to false, "Bob" to true, "Charlie" to false))
        assertTrue(evaluator.evaluate("eliminated_count == 1", state, scenario).value)
    }

    @Test
    fun activeCountGT() {
        val scenario = makeTestScenario(agentNames = listOf("Alice", "Bob", "Charlie"))
        val state = SimulationState.initial(scenario)
            .copy(eliminated = mapOf("Alice" to false, "Bob" to true, "Charlie" to false))
        assertTrue(evaluator.evaluate("active_count > 1", state, scenario).value)
    }

    @Test
    fun currentRoundLE() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B"), rounds = 5)
        val state = SimulationState.initial(scenario).copy(currentRound = 3)
        assertTrue(evaluator.evaluate("current_round <= 3", state, scenario).value)
        assertFalse(evaluator.evaluate("current_round <= 2", state, scenario).value)
    }

    @Test
    fun totalRoundsComparison() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B"), rounds = 5)
        val state = SimulationState.initial(scenario)
        assertTrue(evaluator.evaluate("total_rounds == 5", state, scenario).value)
    }

    // MARK: - Dotted access: scores.<Name>

    @Test
    fun scoresDotAccess() {
        val scenario = makeTestScenario(agentNames = listOf("Alice", "Bob"))
        val state = SimulationState.initial(scenario).copy(scores = mapOf("Alice" to 7, "Bob" to 2))
        assertTrue(evaluator.evaluate("scores.Alice >= 5", state, scenario).value)
        assertFalse(evaluator.evaluate("scores.Bob >= 5", state, scenario).value)
    }

    @Test
    fun scoresDotAccessCJK() {
        val scenario = makeTestScenario(agentNames = listOf("アキラ", "ミサキ"))
        val state = SimulationState.initial(scenario).copy(scores = mapOf("アキラ" to 8, "ミサキ" to 1))
        assertTrue(evaluator.evaluate("scores.アキラ > 5", state, scenario).value)
    }

    // MARK: - String comparison (requires double quotes)

    @Test
    fun voteWinnerEQString() {
        val scenario = makeTestScenario(agentNames = listOf("Alice", "Bob"))
        val state = SimulationState.initial(scenario).copy(voteResults = mapOf("Alice" to 2, "Bob" to 1))
        val result = evaluator.evaluate("vote_winner == \"Alice\"", state, scenario)
        assertTrue(result.value)
    }

    @Test
    fun voteWinnerCJK() {
        val scenario = makeTestScenario(agentNames = listOf("アキラ", "ミサキ"))
        val state = SimulationState.initial(scenario).copy(voteResults = mapOf("アキラ" to 2, "ミサキ" to 0))
        val result = evaluator.evaluate("vote_winner == \"アキラ\"", state, scenario)
        assertTrue(result.value)
    }

    @Test
    fun voteWinnerTieBreaksDeterministically() {
        // Two-way tie: deterministic per spec — same (count desc, name desc)
        // sort as EliminateHandler; higher name wins. Alice vs Bob 2-2 → Bob.
        val scenario = makeTestScenario(agentNames = listOf("Alice", "Bob"))
        val state = SimulationState.initial(scenario).copy(voteResults = mapOf("Alice" to 2, "Bob" to 2))
        val result = evaluator.evaluate("vote_winner == \"Bob\"", state, scenario)
        assertTrue(result.value)
    }

    // MARK: - Template-variable side (state.variables)

    @Test
    fun stateVariableAccess() {
        val scenario = makeTestScenario(agentNames = listOf("Alice", "Bob"))
        val state = SimulationState.initial(scenario).copy(variables = mapOf("assigned_topic" to "cats"))
        val result = evaluator.evaluate("assigned_topic == \"cats\"", state, scenario)
        assertTrue(result.value)
    }

    // MARK: - Runtime-absent: returns false + warning, no throw

    @Test
    fun voteWinnerPreVoteReturnsFalseWithWarning() {
        val scenario = makeTestScenario(agentNames = listOf("Alice", "Bob"))
        val state = SimulationState.initial(scenario) // empty voteResults
        val result = evaluator.evaluate("vote_winner == \"Alice\"", state, scenario)
        assertFalse(result.value)
        assertTrue(result.warnings.isNotEmpty())
    }

    @Test
    fun unknownScoresNameReturnsFalseWithWarning() {
        val scenario = makeTestScenario(agentNames = listOf("Alice", "Bob"))
        val state = SimulationState.initial(scenario)
        // scores.Nobody is not an agent; value is absent at runtime.
        val result = evaluator.evaluate("scores.Nobody > 0", state, scenario)
        assertFalse(result.value)
        assertTrue(result.warnings.isNotEmpty())
    }

    // MARK: - Parse-time errors: throw

    @Test
    fun missingOperatorThrows() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B"))
        val state = SimulationState.initial(scenario)
        assertFailsWith<SimulationException> {
            evaluator.evaluate("max_score", state, scenario)
        }
    }

    @Test
    fun emptyLHSThrows() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B"))
        val state = SimulationState.initial(scenario)
        assertFailsWith<SimulationException> {
            evaluator.evaluate(" == 5", state, scenario)
        }
    }

    @Test
    fun emptyRHSThrows() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B"))
        val state = SimulationState.initial(scenario)
        assertFailsWith<SimulationException> {
            evaluator.evaluate("max_score ==", state, scenario)
        }
    }

    @Test
    fun emptyExpressionThrows() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B"))
        val state = SimulationState.initial(scenario)
        assertFailsWith<SimulationException> {
            evaluator.evaluate("", state, scenario)
        }
    }

    // MARK: - Tokenize-before-expand: operator inside quoted RHS is preserved

    @Test
    fun operatorInsideQuotedRHSIsNotAmbiguous() {
        val scenario = makeTestScenario(agentNames = listOf("Alice", "Bob"))
        val state = SimulationState.initial(scenario).copy(variables = mapOf("tag" to "A>B"))
        // The '>' inside "A>B" must not split the expression.
        val result = evaluator.evaluate("tag == \"A>B\"", state, scenario)
        assertTrue(result.value)
    }

    // MARK: - Operator priority: <= / >= before < / >

    @Test
    fun lessThanOrEqualScannedBeforeLessThan() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B"))
        val state = SimulationState.initial(scenario).copy(currentRound = 5)
        // Must tokenize as `current_round <= 5`, not `current_round < = 5`.
        assertTrue(evaluator.evaluate("current_round <= 5", state, scenario).value)
    }

    @Test
    fun notEqualOperator() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B"))
        val state = SimulationState.initial(scenario).copy(scores = mapOf("A" to 3, "B" to 0))
        assertTrue(evaluator.evaluate("max_score != 0", state, scenario).value)
    }

    // MARK: - Error carries the wrapped SimulationError

    @Test
    fun parseErrorCarriesScenarioValidationFailed() {
        val scenario = makeTestScenario(agentNames = listOf("A", "B"))
        val state = SimulationState.initial(scenario)
        val caught = assertFailsWith<SimulationException> {
            evaluator.evaluate("max_score", state, scenario)
        }
        assertEquals(
            true,
            caught.error is com.pastura.models.SimulationError.ScenarioValidationFailed,
        )
    }
}
