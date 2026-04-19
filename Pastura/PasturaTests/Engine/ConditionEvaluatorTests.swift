import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct ConditionEvaluatorTests {
  let evaluator = ConditionEvaluator()

  // MARK: - Numeric comparison — derived variables

  @Test func maxScoreGTE() throws {
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"])
    var state = SimulationState.initial(for: scenario)
    state.scores = ["Alice": 10, "Bob": 3]
    #expect(try evaluator.evaluate("max_score >= 10", state: state, scenario: scenario).value)
    #expect(!(try evaluator.evaluate("max_score >= 11", state: state, scenario: scenario).value))
  }

  @Test func minScoreLT() throws {
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"])
    var state = SimulationState.initial(for: scenario)
    state.scores = ["Alice": 10, "Bob": 3]
    #expect(try evaluator.evaluate("min_score < 5", state: state, scenario: scenario).value)
  }

  @Test func eliminatedCountEQ() throws {
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob", "Charlie"])
    var state = SimulationState.initial(for: scenario)
    state.eliminated = ["Alice": false, "Bob": true, "Charlie": false]
    #expect(try evaluator.evaluate("eliminated_count == 1", state: state, scenario: scenario).value)
  }

  @Test func activeCountGT() throws {
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob", "Charlie"])
    var state = SimulationState.initial(for: scenario)
    state.eliminated = ["Alice": false, "Bob": true, "Charlie": false]
    #expect(try evaluator.evaluate("active_count > 1", state: state, scenario: scenario).value)
  }

  @Test func currentRoundLE() throws {
    let scenario = makeTestScenario(agentNames: ["A", "B"], rounds: 5)
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 3
    #expect(try evaluator.evaluate("current_round <= 3", state: state, scenario: scenario).value)
    #expect(!(try evaluator.evaluate("current_round <= 2", state: state, scenario: scenario).value))
  }

  @Test func totalRoundsComparison() throws {
    let scenario = makeTestScenario(agentNames: ["A", "B"], rounds: 5)
    let state = SimulationState.initial(for: scenario)
    #expect(try evaluator.evaluate("total_rounds == 5", state: state, scenario: scenario).value)
  }

  // MARK: - Dotted access: scores.<Name>

  @Test func scoresDotAccess() throws {
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"])
    var state = SimulationState.initial(for: scenario)
    state.scores = ["Alice": 7, "Bob": 2]
    #expect(try evaluator.evaluate("scores.Alice >= 5", state: state, scenario: scenario).value)
    #expect(!(try evaluator.evaluate("scores.Bob >= 5", state: state, scenario: scenario).value))
  }

  @Test func scoresDotAccessCJK() throws {
    let scenario = makeTestScenario(agentNames: ["アキラ", "ミサキ"])
    var state = SimulationState.initial(for: scenario)
    state.scores = ["アキラ": 8, "ミサキ": 1]
    #expect(try evaluator.evaluate("scores.アキラ > 5", state: state, scenario: scenario).value)
  }

  // MARK: - String comparison (requires double quotes)

  @Test func voteWinnerEQString() throws {
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"])
    var state = SimulationState.initial(for: scenario)
    state.voteResults = ["Alice": 2, "Bob": 1]
    let result = try evaluator.evaluate(
      "vote_winner == \"Alice\"", state: state, scenario: scenario)
    #expect(result.value)
  }

  @Test func voteWinnerCJK() throws {
    let scenario = makeTestScenario(agentNames: ["アキラ", "ミサキ"])
    var state = SimulationState.initial(for: scenario)
    state.voteResults = ["アキラ": 2, "ミサキ": 0]
    let result = try evaluator.evaluate(
      "vote_winner == \"アキラ\"", state: state, scenario: scenario)
    #expect(result.value)
  }

  @Test func voteWinnerTieBreaksDeterministically() throws {
    // Two-way tie: 仕様上は決定的 (EliminateHandler と同じ sorted-by-name 逆順で
    // higher name wins). ここではルールを固定する: Alice vs Bob 同票なら Bob.
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"])
    var state = SimulationState.initial(for: scenario)
    state.voteResults = ["Alice": 2, "Bob": 2]
    let result = try evaluator.evaluate(
      "vote_winner == \"Bob\"", state: state, scenario: scenario)
    #expect(result.value)
  }

  // MARK: - Template-variable side (state.variables)

  @Test func stateVariableAccess() throws {
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"])
    var state = SimulationState.initial(for: scenario)
    state.variables["assigned_topic"] = "cats"
    let result = try evaluator.evaluate(
      "assigned_topic == \"cats\"", state: state, scenario: scenario)
    #expect(result.value)
  }

  // MARK: - Runtime-absent: returns false + warning, no throw

  @Test func voteWinnerPreVoteReturnsFalseWithWarning() throws {
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"])
    let state = SimulationState.initial(for: scenario)  // empty voteResults
    let result = try evaluator.evaluate(
      "vote_winner == \"Alice\"", state: state, scenario: scenario)
    #expect(!result.value)
    #expect(!result.warnings.isEmpty)
  }

  @Test func unknownScoresNameReturnsFalseWithWarning() throws {
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"])
    let state = SimulationState.initial(for: scenario)
    // scores.Nobody is not an agent; value is absent at runtime.
    let result = try evaluator.evaluate(
      "scores.Nobody > 0", state: state, scenario: scenario)
    #expect(!result.value)
    #expect(!result.warnings.isEmpty)
  }

  // MARK: - Parse-time errors: throw

  @Test func missingOperatorThrows() {
    let scenario = makeTestScenario(agentNames: ["A", "B"])
    let state = SimulationState.initial(for: scenario)
    #expect(throws: SimulationError.self) {
      _ = try evaluator.evaluate("max_score", state: state, scenario: scenario)
    }
  }

  @Test func emptyLHSThrows() {
    let scenario = makeTestScenario(agentNames: ["A", "B"])
    let state = SimulationState.initial(for: scenario)
    #expect(throws: SimulationError.self) {
      _ = try evaluator.evaluate(" == 5", state: state, scenario: scenario)
    }
  }

  @Test func emptyRHSThrows() {
    let scenario = makeTestScenario(agentNames: ["A", "B"])
    let state = SimulationState.initial(for: scenario)
    #expect(throws: SimulationError.self) {
      _ = try evaluator.evaluate("max_score ==", state: state, scenario: scenario)
    }
  }

  @Test func emptyExpressionThrows() {
    let scenario = makeTestScenario(agentNames: ["A", "B"])
    let state = SimulationState.initial(for: scenario)
    #expect(throws: SimulationError.self) {
      _ = try evaluator.evaluate("", state: state, scenario: scenario)
    }
  }

  // MARK: - Tokenize-before-expand: operator inside quoted RHS is preserved

  @Test func operatorInsideQuotedRHSIsNotAmbiguous() throws {
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"])
    var state = SimulationState.initial(for: scenario)
    state.variables["tag"] = "A>B"
    // The '>' inside "A>B" must not split the expression.
    let result = try evaluator.evaluate(
      "tag == \"A>B\"", state: state, scenario: scenario)
    #expect(result.value)
  }

  // MARK: - Operator priority: <= / >= before < / >

  @Test func lessThanOrEqualScannedBeforeLessThan() throws {
    let scenario = makeTestScenario(agentNames: ["A", "B"])
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 5
    // Must tokenize as `current_round <= 5`, not `current_round < = 5`.
    #expect(try evaluator.evaluate("current_round <= 5", state: state, scenario: scenario).value)
  }

  @Test func notEqualOperator() throws {
    let scenario = makeTestScenario(agentNames: ["A", "B"])
    var state = SimulationState.initial(for: scenario)
    state.scores = ["A": 3, "B": 0]
    #expect(try evaluator.evaluate("max_score != 0", state: state, scenario: scenario).value)
  }
}
