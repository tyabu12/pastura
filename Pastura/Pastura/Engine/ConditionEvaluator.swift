import Foundation

/// Evaluates a boolean condition expression used by the `conditional` phase
/// type. Supports `&&` / `||` combinators and parenthesized grouping on top
/// of a single-comparison primitive.
///
/// Grammar:
///
///     expression ::= or
///     or         ::= and ('||' and)*
///     and        ::= factor ('&&' factor)*
///     factor     ::= '(' or ')'  |  comparison
///     comparison ::= operand OP operand
///     OP         ::= "==" | "!=" | "<=" | ">=" | "<" | ">"
///     operand    ::= Identifier ("." Identifier)?
///                    | NumberLiteral
///                    | StringLiteral
///     StringLiteral ::= '"' .* '"'
///
/// Precedence (loosest to tightest): `||` < `&&` < comparison. Both `&&`
/// and `||` are left-associative — `a || b || c` evaluates as
/// `(a || b) || c`. Parens may group any boolean sub-expression and
/// override precedence; an operand itself cannot be parenthesized
/// (`(current_round) == 1` is rejected).
///
/// Tokenization is quote-aware: operator-like characters inside a quoted
/// string literal (e.g. `"a && b"`, `"x>y"`, `"(foo)"`) are treated as
/// literal content rather than tokens.
///
/// Derived read-only variables available on either side of a comparison:
///
/// | Identifier         | Source                                      |
/// |--------------------|---------------------------------------------|
/// | `current_round`    | `state.currentRound`                        |
/// | `total_rounds`     | `scenario.rounds`                           |
/// | `max_score`        | `state.scores.values.max()`                 |
/// | `min_score`        | `state.scores.values.min()`                 |
/// | `eliminated_count` | count of `state.eliminated.values == true`  |
/// | `active_count`     | count of `state.eliminated.values == false` |
/// | `vote_winner`      | most-voted name in `state.voteResults` (ties broken by count desc, name desc) |
/// | `scores.<Name>`    | `state.scores["<Name>"]`                    |
///
/// Any other identifier is resolved from `state.variables`.
///
/// **Parse-time errors** (missing operator, empty operand, mismatched
/// parens, dangling `&&` / `||`, empty `()`) throw
/// `SimulationError.scenarioValidationFailed`. Use ``parse(_:)`` to fail
/// fast at scenario-load time rather than waiting for handler dispatch
/// — `ScenarioValidator.validateConditionalPhase` does this.
///
/// **Runtime-absent values** (e.g. `vote_winner` before any vote this
/// round, `scores.Nobody`) do not throw; the comparison they appear in
/// returns `value: false` and a warning string is appended to
/// ``EvaluationResult/warnings`` so the caller can surface it via the
/// normal `.summary` warning channel.
///
/// **Short-circuit policy** (Swift-style): the dropped side of `false &&
/// X` / `true || X` is **not** resolved, so absent-variable warnings on
/// the skipped branch never appear. Trade-off: a typo in a never-evaluated
/// sub-expression (e.g. `current_round > 999 && scores.Aliec > 5` with
/// `Alice` typo'd) stays hidden because the always-false LHS short-
/// circuits before the parser ever asks the resolver about `Aliec`.
/// Authors debugging an always-same-branch condition should temporarily
/// flip operands or remove the combinator to surface warnings on both
/// sides.
///
/// This type is the sole owner of the expression grammar — callers pass an
/// expression string only. Tokenizer + recursive-descent parser internals
/// live in `ConditionEvaluator+Parser.swift`.
nonisolated public struct ConditionEvaluator: Sendable {

  /// Result of evaluating a condition expression.
  public struct EvaluationResult: Sendable, Equatable {
    /// The evaluated boolean. `false` when a comparison's operand is
    /// runtime-absent, or when a sub-expression's truth value (and short-
    /// circuit policy) drives it false.
    public let value: Bool

    /// Non-fatal diagnostics (e.g. runtime-absent variables). Callers
    /// should forward these to the `.summary` event so users can debug
    /// their DSL. Warnings from short-circuited sub-expressions are
    /// suppressed by design — see the type-level doc comment.
    public let warnings: [String]
  }

  /// Lexical token classes recognized by the DSL. Defined as a nested
  /// type so the parser file (a sibling extension) can reference it
  /// without widening visibility module-internal-or-tighter.
  enum Token: Equatable {
    case openParen
    case closeParen
    case logicalAnd
    case logicalOr
    case comparisonOp(String)
    /// String preserving its source form: numbers as their digits, bare
    /// identifiers as-is (including dotted access like `scores.Alice`),
    /// and quoted strings WITH surrounding `"` so the resolver can
    /// distinguish `Alice` (identifier) from `"Alice"` (string literal).
    case operand(String)
  }

  /// AST node for the parsed expression. Walker lives in this file;
  /// builder lives in `ConditionEvaluator+Parser.swift`.
  indirect enum Node: Equatable {
    case logicalOr(Node, Node)
    case logicalAnd(Node, Node)
    case comparison(lhs: String, symbol: String, rhs: String)
  }

  public init() {}

  /// Evaluates `expression` against `state` and `scenario`.
  ///
  /// - Throws: `SimulationError.scenarioValidationFailed` for parse-time
  ///   errors (missing operator, empty operand, mismatched parens,
  ///   dangling combinator, empty parens).
  public func evaluate(
    _ expression: String,
    state: SimulationState,
    scenario: Scenario
  ) throws -> EvaluationResult {
    let ast = try parseToAST(expression)
    return walk(ast, state: state, scenario: scenario)
  }

  /// Parses `expression` and discards the AST. Used by
  /// `ScenarioValidator.validateConditionalPhase` to surface malformed
  /// `if:` strings at scenario-load time, before any `state` exists.
  ///
  /// - Throws: `SimulationError.scenarioValidationFailed` on syntactic
  ///   errors. Runtime-absent identifiers do not throw — those only
  ///   surface during ``evaluate(_:state:scenario:)`` as warnings.
  public func parse(_ expression: String) throws {
    _ = try parseToAST(expression)
  }

  // MARK: - AST walker (with short-circuit)

  private func walk(
    _ node: Node, state: SimulationState, scenario: Scenario
  ) -> EvaluationResult {
    switch node {
    case .comparison(let lhs, let symbol, let rhs):
      return walkComparison(
        lhs: lhs, symbol: symbol, rhs: rhs, state: state, scenario: scenario)
    case .logicalAnd(let lhs, let rhs):
      let lhsResult = walk(lhs, state: state, scenario: scenario)
      // Short-circuit: dropped side is NOT resolved, so its warnings
      // never enter the result. Documented Swift-style policy.
      if !lhsResult.value { return lhsResult }
      let rhsResult = walk(rhs, state: state, scenario: scenario)
      return EvaluationResult(
        value: rhsResult.value,
        warnings: lhsResult.warnings + rhsResult.warnings)
    case .logicalOr(let lhs, let rhs):
      let lhsResult = walk(lhs, state: state, scenario: scenario)
      if lhsResult.value { return lhsResult }
      let rhsResult = walk(rhs, state: state, scenario: scenario)
      return EvaluationResult(
        value: rhsResult.value,
        warnings: lhsResult.warnings + rhsResult.warnings)
    }
  }

  private func walkComparison(
    lhs: String, symbol: String, rhs: String,
    state: SimulationState, scenario: Scenario
  ) -> EvaluationResult {
    var warnings: [String] = []
    let lhsValue = resolve(
      token: lhs, state: state, scenario: scenario, warnings: &warnings)
    let rhsValue = resolve(
      token: rhs, state: state, scenario: scenario, warnings: &warnings)
    guard let left = lhsValue, let right = rhsValue else {
      return EvaluationResult(value: false, warnings: warnings)
    }
    return EvaluationResult(
      value: compare(left, symbol, right), warnings: warnings)
  }

  // MARK: - Operand resolution

  /// Resolves a token to a string value, or returns `nil` if the
  /// identifier refers to data not present at runtime (with a warning
  /// appended to `warnings`).
  private func resolve(
    token: String,
    state: SimulationState,
    scenario: Scenario,
    warnings: inout [String]
  ) -> String? {
    if token.hasPrefix("\"") && token.hasSuffix("\"") && token.count >= 2 {
      return String(token.dropFirst().dropLast())
    }
    if Double(token) != nil {
      return token
    }
    if let dotIndex = token.firstIndex(of: ".") {
      return resolveDotted(token, dotIndex: dotIndex, state: state, warnings: &warnings)
    }

    switch resolveDerived(token, state: state, scenario: scenario, warnings: &warnings) {
    case .value(let resolved):
      return resolved
    case .absent:
      return nil
    case .notDerived:
      break
    }

    if let fromVariables = state.variables[token] {
      return fromVariables
    }
    warnings.append("Unknown identifier '\(token)'")
    return nil
  }

  private func resolveDotted(
    _ token: String,
    dotIndex: String.Index,
    state: SimulationState,
    warnings: inout [String]
  ) -> String? {
    let head = String(token[..<dotIndex])
    let tail = String(token[token.index(after: dotIndex)...])
    if head == "scores" {
      if let score = state.scores[tail] {
        return String(score)
      }
      warnings.append("scores.\(tail) is not set (agent absent from scores)")
      return nil
    }
    warnings.append("Unknown dotted identifier '\(token)'")
    return nil
  }

  /// Tri-state result for derived-variable resolution.
  private enum DerivedResolution {
    case value(String)
    /// Recognized as derived but has no runtime value. A warning has
    /// already been appended by the producer.
    case absent
    /// Not a derived variable at all; caller should fall through to
    /// `state.variables`.
    case notDerived
  }

  private func resolveDerived(
    _ identifier: String,
    state: SimulationState,
    scenario: Scenario,
    warnings: inout [String]
  ) -> DerivedResolution {
    if let value = resolveAlwaysPresentDerived(identifier, state: state, scenario: scenario) {
      return .value(value)
    }
    return resolveMayBeAbsentDerived(identifier, state: state, warnings: &warnings)
  }

  private func resolveAlwaysPresentDerived(
    _ identifier: String, state: SimulationState, scenario: Scenario
  ) -> String? {
    switch identifier {
    case "current_round": return String(state.currentRound)
    case "total_rounds": return String(scenario.rounds)
    case "eliminated_count": return String(state.eliminated.values.filter { $0 }.count)
    case "active_count": return String(state.eliminated.values.filter { !$0 }.count)
    default: return nil
    }
  }

  private func resolveMayBeAbsentDerived(
    _ identifier: String, state: SimulationState, warnings: inout [String]
  ) -> DerivedResolution {
    switch identifier {
    case "max_score":
      return resolveScoreExtremum(
        state.scores.values.max(), label: "max_score", warnings: &warnings)
    case "min_score":
      return resolveScoreExtremum(
        state.scores.values.min(), label: "min_score", warnings: &warnings)
    case "vote_winner":
      // Shared canonical tie-break (count desc, name desc). EliminateHandler
      // and WordwolfJudgeLogic resolve the same winner (#1056).
      if let winner = VoteTally.winner(state.voteResults) {
        return .value(winner.key)
      }
      warnings.append("vote_winner has no value (no vote phase has run this round)")
      return .absent
    default:
      return .notDerived
    }
  }

  private func resolveScoreExtremum(
    _ value: Int?, label: String, warnings: inout [String]
  ) -> DerivedResolution {
    if let value = value {
      return .value(String(value))
    }
    warnings.append("\(label) has no value (scores is empty)")
    return .absent
  }

  // MARK: - Comparison

  private func compare(_ lhs: String, _ symbol: String, _ rhs: String) -> Bool {
    if let lhsNum = Double(lhs), let rhsNum = Double(rhs) {
      return applyOperator(symbol, lhsNum, rhsNum)
    }
    return applyOperator(symbol, lhs, rhs)
  }

  private func applyOperator<T: Comparable>(_ symbol: String, _ lhs: T, _ rhs: T) -> Bool {
    switch symbol {
    case "==": return lhs == rhs
    case "!=": return lhs != rhs
    case "<": return lhs < rhs
    case "<=": return lhs <= rhs
    case ">": return lhs > rhs
    case ">=": return lhs >= rhs
    default: return false
    }
  }
}
