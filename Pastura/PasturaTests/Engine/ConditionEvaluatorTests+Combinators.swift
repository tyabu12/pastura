import Foundation
import Testing

@testable import Pastura

// Combinator-DSL coverage for ConditionEvaluator (`&&` / `||` / parens,
// short-circuit warning policy, parse-only entry point). Sibling extension
// of `ConditionEvaluatorTests` per `.claude/rules/testing.md` — keeping a
// single `@Suite` avoids the parallel-suites race against shared state.

extension ConditionEvaluatorTests {
  // MARK: - Combinators (&& / ||)

  @Test func logicalAndBothTrue() throws {
    let scenario = makeTestScenario(agentNames: ["A", "B", "C"], rounds: 5)
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 3
    state.eliminated = ["A": false, "B": false, "C": false]
    let result = try evaluator.evaluate(
      "current_round > 0 && active_count > 1", state: state, scenario: scenario)
    #expect(result.value)
  }

  @Test func logicalAndOneFalse() throws {
    let scenario = makeTestScenario(agentNames: ["A", "B"], rounds: 5)
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 3
    state.scores = ["A": 1, "B": 0]
    // current_round > 0 (true) && max_score > 5 (false) → false
    #expect(
      !(try evaluator.evaluate(
        "current_round > 0 && max_score > 5", state: state, scenario: scenario
      ).value))
  }

  @Test func logicalOrFirstTrueShortCircuits() throws {
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"])
    var state = SimulationState.initial(for: scenario)
    state.scores = ["Alice": 12, "Bob": 0]
    state.voteResults = ["Bob": 1]
    let result = try evaluator.evaluate(
      "max_score >= 10 || vote_winner == \"Alice\"", state: state, scenario: scenario)
    #expect(result.value)
  }

  @Test func logicalOrSecondTrue() throws {
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"])
    var state = SimulationState.initial(for: scenario)
    state.scores = ["Alice": 5, "Bob": 0]
    state.voteResults = ["Alice": 2, "Bob": 1]
    let result = try evaluator.evaluate(
      "max_score >= 10 || vote_winner == \"Alice\"", state: state, scenario: scenario)
    #expect(result.value)
  }

  // MARK: - Precedence: && binds tighter than ||

  @Test func precedenceAndOverOrTrueViaAnd() throws {
    // (a > 0 && b > 0) || c > 0  with a=1, b=1, c=0 → true
    let scenario = makeTestScenario(agentNames: ["A", "B"], rounds: 5)
    var state = SimulationState.initial(for: scenario)
    state.variables = ["a": "1", "b": "1", "c": "0"]
    #expect(
      try evaluator.evaluate(
        "a > 0 && b > 0 || c > 0", state: state, scenario: scenario
      ).value)
  }

  @Test func precedenceAndOverOrTrueViaOr() throws {
    // (a > 0 && b > 0) || c > 0  with a=0, b=1, c=1 → true (RHS of ||)
    let scenario = makeTestScenario(agentNames: ["A", "B"], rounds: 5)
    var state = SimulationState.initial(for: scenario)
    state.variables = ["a": "0", "b": "1", "c": "1"]
    #expect(
      try evaluator.evaluate(
        "a > 0 && b > 0 || c > 0", state: state, scenario: scenario
      ).value)
  }

  @Test func precedenceOrAndAndPinsAndTighter() throws {
    // a > 0 || b > 0 && c > 0  with a=1, b=1, c=0
    // && tighter → a || (b && c) → 1 || (1 && 0) → true
    // Equal-prec left-assoc would parse as (a || b) && c → (1 || 1) && 0 → false.
    // Result divergence pins the precedence direction.
    let scenario = makeTestScenario(agentNames: ["A", "B"], rounds: 5)
    var state = SimulationState.initial(for: scenario)
    state.variables = ["a": "1", "b": "1", "c": "0"]
    #expect(
      try evaluator.evaluate(
        "a > 0 || b > 0 && c > 0", state: state, scenario: scenario
      ).value)
  }

  // MARK: - Parentheses

  @Test func parensOverridePrecedence() throws {
    // (a > 0 || b > 0) && c > 0  with a=1, b=0, c=0 → false
    // Without parens (&& tighter): a || (b && c) → 1 || 0 → true.
    // Result divergence pins paren grouping.
    let scenario = makeTestScenario(agentNames: ["A", "B"], rounds: 5)
    var state = SimulationState.initial(for: scenario)
    state.variables = ["a": "1", "b": "0", "c": "0"]
    #expect(
      !(try evaluator.evaluate(
        "(a > 0 || b > 0) && c > 0", state: state, scenario: scenario
      ).value))
  }

  @Test func parensWithCombinatorMixingComparisonAndString() throws {
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"], rounds: 5)
    var state = SimulationState.initial(for: scenario)
    state.scores = ["Alice": 3, "Bob": 1]
    state.voteResults = ["Alice": 2, "Bob": 0]
    state.currentRound = 4
    let result = try evaluator.evaluate(
      "(max_score < 5 || vote_winner == \"Alice\") && current_round >= 3",
      state: state, scenario: scenario)
    #expect(result.value)
  }

  @Test func deeplyNestedParensReduceCorrectly() throws {
    let scenario = makeTestScenario(agentNames: ["A", "B"], rounds: 5)
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    #expect(
      try evaluator.evaluate(
        "(((current_round == 1)))", state: state, scenario: scenario
      ).value)
  }

  // MARK: - Left-associativity

  @Test func leftAssociativeOrChain() throws {
    let scenario = makeTestScenario(agentNames: ["A", "B"], rounds: 5)
    var state = SimulationState.initial(for: scenario)
    state.variables = ["a": "0", "b": "0", "c": "1"]
    #expect(
      try evaluator.evaluate(
        "a > 0 || b > 0 || c > 0", state: state, scenario: scenario
      ).value)
    state.variables = ["a": "0", "b": "0", "c": "0"]
    #expect(
      !(try evaluator.evaluate(
        "a > 0 || b > 0 || c > 0", state: state, scenario: scenario
      ).value))
  }

  @Test func leftAssociativeAndChain() throws {
    let scenario = makeTestScenario(agentNames: ["A", "B"], rounds: 5)
    var state = SimulationState.initial(for: scenario)
    state.variables = ["a": "1", "b": "1", "c": "1"]
    #expect(
      try evaluator.evaluate(
        "a > 0 && b > 0 && c > 0", state: state, scenario: scenario
      ).value)
    state.variables = ["a": "1", "b": "0", "c": "1"]
    #expect(
      !(try evaluator.evaluate(
        "a > 0 && b > 0 && c > 0", state: state, scenario: scenario
      ).value))
  }

  // MARK: - Short-circuit evaluation policy

  @Test func shortCircuitFalseAndAbsentSuppressesWarning() throws {
    // LHS evaluates to false; RHS uses runtime-absent vote_winner. Per
    // Swift-style short-circuit policy, RHS must NOT be resolved, so its
    // warning never appears.
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"])
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let result = try evaluator.evaluate(
      "current_round > 999 && vote_winner == \"Alice\"",
      state: state, scenario: scenario)
    #expect(!result.value)
    #expect(result.warnings.isEmpty)
  }

  @Test func shortCircuitTrueOrAbsentSuppressesWarning() throws {
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"])
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let result = try evaluator.evaluate(
      "current_round == 1 || vote_winner == \"Alice\"",
      state: state, scenario: scenario)
    #expect(result.value)
    #expect(result.warnings.isEmpty)
  }

  @Test func dualAbsentVariablesNoShortCircuitBothWarnings() throws {
    // LHS evaluates to false-with-warning (scores.Nobody absent), RHS not
    // short-circuited (|| needs to look at the right side when LHS is
    // false), RHS also false-with-warning. Both warnings surface.
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"])
    let state = SimulationState.initial(for: scenario)
    let result = try evaluator.evaluate(
      "scores.Nobody > 0 || vote_winner == \"X\"",
      state: state, scenario: scenario)
    #expect(!result.value)
    #expect(result.warnings.count == 2)
  }

  // MARK: - Quote awareness across new tokens

  @Test func combinatorInsideQuotedRHSIsNotSplit() throws {
    let scenario = makeTestScenario(agentNames: ["A", "B"])
    var state = SimulationState.initial(for: scenario)
    state.variables = ["topic": "tea && coffee"]
    let result = try evaluator.evaluate(
      "topic == \"tea && coffee\"", state: state, scenario: scenario)
    #expect(result.value)
  }

  @Test func parensInsideQuotedRHSIsNotSplit() throws {
    let scenario = makeTestScenario(agentNames: ["A", "B"])
    var state = SimulationState.initial(for: scenario)
    state.variables = ["tag": "(foo)"]
    let result = try evaluator.evaluate(
      "tag == \"(foo)\"", state: state, scenario: scenario)
    #expect(result.value)
  }

  // MARK: - Parse errors

  @Test func emptyParensThrows() {
    let scenario = makeTestScenario(agentNames: ["A", "B"])
    let state = SimulationState.initial(for: scenario)
    #expect(throws: SimulationError.self) {
      _ = try evaluator.evaluate("()", state: state, scenario: scenario)
    }
  }

  @Test func mismatchedOpenParenThrows() {
    let scenario = makeTestScenario(agentNames: ["A", "B"])
    let state = SimulationState.initial(for: scenario)
    #expect(throws: SimulationError.self) {
      _ = try evaluator.evaluate(
        "(current_round == 1 && max_score > 0", state: state, scenario: scenario)
    }
  }

  @Test func mismatchedCloseParenThrows() {
    let scenario = makeTestScenario(agentNames: ["A", "B"])
    let state = SimulationState.initial(for: scenario)
    #expect(throws: SimulationError.self) {
      _ = try evaluator.evaluate(
        "current_round == 1) && max_score > 0", state: state, scenario: scenario)
    }
  }

  @Test func danglingAndOperatorThrows() {
    let scenario = makeTestScenario(agentNames: ["A", "B"])
    let state = SimulationState.initial(for: scenario)
    #expect(throws: SimulationError.self) {
      _ = try evaluator.evaluate(
        "current_round == 1 &&", state: state, scenario: scenario)
    }
  }

  @Test func leadingOrOperatorThrows() {
    let scenario = makeTestScenario(agentNames: ["A", "B"])
    let state = SimulationState.initial(for: scenario)
    #expect(throws: SimulationError.self) {
      _ = try evaluator.evaluate(
        "|| current_round == 1", state: state, scenario: scenario)
    }
  }

  // MARK: - Parse-only entry point (used by ScenarioValidator)

  @Test func parseAcceptsValidExpression() throws {
    try evaluator.parse(
      "current_round == 1 && (max_score > 0 || vote_winner == \"X\")")
  }

  @Test func parseRejectsMalformedExpression() {
    #expect(throws: SimulationError.self) {
      try evaluator.parse("(current_round == 1")
    }
  }
}
