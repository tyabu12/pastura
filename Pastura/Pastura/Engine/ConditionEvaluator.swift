import Foundation

/// Evaluates a single-comparison condition expression used by the
/// `conditional` phase type.
///
/// Grammar (v1):
///
///     expression ::= lhs OP rhs
///     OP         ::= "==" | "!=" | "<=" | ">=" | "<" | ">"
///     lhs, rhs   ::= Identifier ("." Identifier)?  |  NumberLiteral  |  StringLiteral
///     StringLiteral ::= '"' .* '"'
///
/// Tokenization is "scan for operator first, then expand each side", so an
/// operator character inside a quoted RHS (e.g. `"A>B"`) does not split the
/// expression. `&&` / `||` combinators are deliberately not supported in v1
/// — see the follow-up issue on the PR description.
///
/// Derived read-only variables available on the LHS (or RHS as an identifier):
///
/// | Identifier         | Source                                      |
/// |--------------------|---------------------------------------------|
/// | `current_round`    | `state.currentRound`                        |
/// | `total_rounds`     | `scenario.rounds`                           |
/// | `max_score`        | `state.scores.values.max()`                 |
/// | `min_score`        | `state.scores.values.min()`                 |
/// | `eliminated_count` | count of `state.eliminated.values == true`  |
/// | `active_count`     | count of `state.eliminated.values == false` |
/// | `vote_winner`      | most-voted name in `state.voteResults` (ties broken like `EliminateHandler`) |
/// | `scores.<Name>`    | `state.scores["<Name>"]`                    |
///
/// Any other identifier is resolved from `state.variables`.
///
/// Parse-time errors (missing operator, empty LHS / RHS) throw
/// `SimulationError.scenarioValidationFailed`. Runtime-absent values (e.g.
/// `vote_winner` before any vote this round, `scores.Nobody`) do **not**
/// throw; they return `value: false` and attach a warning string to
/// `EvaluationResult.warnings` so the caller can surface it via the normal
/// `.summary` warning channel.
///
/// This type is the sole owner of the expression grammar — callers pass an
/// expression string only. Future upgrades (e.g. adding `&&`/`||`) replace
/// the internals without changing the call site.
nonisolated public struct ConditionEvaluator: Sendable {

  /// Result of evaluating a condition expression.
  public struct EvaluationResult: Sendable, Equatable {
    /// The evaluated boolean. `false` when either side is runtime-absent.
    public let value: Bool

    /// Non-fatal diagnostics (e.g. runtime-absent variables). Callers should
    /// forward these to the `.summary` event so users can debug their DSL.
    public let warnings: [String]
  }

  /// Operators scanned in priority order. Two-character operators appear
  /// before their one-character prefixes so `<=` is not broken into `<` + `=`.
  private static let operatorsByPriority: [String] = [
    "<=", ">=", "==", "!=", "<", ">"
  ]

  public init() {}

  /// Evaluates `expression` against `state` and `scenario`.
  ///
  /// - Throws: `SimulationError.scenarioValidationFailed` for parse-time
  ///   errors (missing operator, empty side).
  public func evaluate(
    _ expression: String,
    state: SimulationState,
    scenario: Scenario
  ) throws -> EvaluationResult {
    let split = try splitByOperator(expression)

    var warnings: [String] = []
    let lhsValue = resolve(
      token: split.lhs, state: state, scenario: scenario, warnings: &warnings)
    let rhsValue = resolve(
      token: split.rhs, state: state, scenario: scenario, warnings: &warnings)

    guard let left = lhsValue, let right = rhsValue else {
      return EvaluationResult(value: false, warnings: warnings)
    }

    return EvaluationResult(value: compare(left, split.symbol, right), warnings: warnings)
  }

  // MARK: - Tokenization

  /// Parsed operands + operator symbol from the expression.
  private struct Split {
    let lhs: String
    let symbol: String
    let rhs: String
  }

  /// Splits the expression into its three parts.
  ///
  /// Walks left-to-right, tracking whether we are inside a double-quoted
  /// literal, and returns the position of the first operator found outside
  /// quotes. Two-character operators are tried before one-character so that
  /// `<=` is never read as `<` + `=`.
  private func splitByOperator(_ expression: String) throws -> Split {
    let chars = Array(expression)
    var inQuote = false
    var index = 0

    while index < chars.count {
      let char = chars[index]
      if char == "\"" {
        inQuote.toggle()
        index += 1
        continue
      }
      if !inQuote {
        // Try operators in priority order (longest first).
        for symbol in Self.operatorsByPriority {
          let symbolChars = Array(symbol)
          if index + symbolChars.count <= chars.count
            && Array(chars[index..<index + symbolChars.count]) == symbolChars {
            let lhs = String(chars[0..<index]).trimmingCharacters(in: .whitespaces)
            let rhs = String(chars[index + symbolChars.count..<chars.count])
              .trimmingCharacters(in: .whitespaces)
            guard !lhs.isEmpty, !rhs.isEmpty else {
              throw SimulationError.scenarioValidationFailed(
                "Condition expression '\(expression)' has empty operand for operator '\(symbol)'"
              )
            }
            return Split(lhs: lhs, symbol: symbol, rhs: rhs)
          }
        }
      }
      index += 1
    }

    throw SimulationError.scenarioValidationFailed(
      "Condition expression '\(expression)' contains no comparison operator "
        + "(one of \(Self.operatorsByPriority.joined(separator: ", ")))"
    )
  }

  // MARK: - Resolution

  /// Resolves a token to a string value, or returns `nil` if the identifier
  /// refers to data that is not present at runtime (with a warning appended).
  private func resolve(
    token: String,
    state: SimulationState,
    scenario: Scenario,
    warnings: inout [String]
  ) -> String? {
    // Double-quoted string literal: strip quotes and return content verbatim.
    if token.hasPrefix("\"") && token.hasSuffix("\"") && token.count >= 2 {
      return String(token.dropFirst().dropLast())
    }

    // Numeric literal: accept as-is (Int or Double). Comparison decides type.
    if Double(token) != nil {
      return token
    }

    // Dotted access: only `scores.<Name>` is valid in v1.
    if let dotIndex = token.firstIndex(of: ".") {
      let head = String(token[..<dotIndex])
      let tail = String(token[token.index(after: dotIndex)...])
      if head == "scores" {
        if let score = state.scores[tail] {
          return String(score)
        }
        warnings.append("scores.\(tail) is not set (agent absent from scores)")
        return nil
      }
      // Any other dotted identifier is unknown — treat as absent.
      warnings.append("Unknown dotted identifier '\(token)'")
      return nil
    }

    // Bare identifier: try derived vars first, then state.variables.
    switch resolveDerived(token, state: state, scenario: scenario, warnings: &warnings) {
    case .value(let resolved):
      return resolved
    case .absent:
      // Recognized as derived but has no runtime value; warning already
      // appended by resolveDerived.
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

  /// Tri-state result for derived-variable resolution.
  private enum DerivedResolution {
    /// Identifier is derived and resolved to a value.
    case value(String)
    /// Identifier is recognized as derived but has no runtime value.
    /// A warning has already been appended by the producer.
    case absent
    /// Identifier is not a derived variable at all; caller should fall
    /// through to `state.variables`.
    case notDerived
  }

  private func resolveDerived(
    _ identifier: String,
    state: SimulationState,
    scenario: Scenario,
    warnings: inout [String]
  ) -> DerivedResolution {
    // "Always present" derived variables resolve without possibly being absent.
    if let value = resolveAlwaysPresentDerived(identifier, state: state, scenario: scenario) {
      return .value(value)
    }
    // "May be absent" derived variables — some depend on runtime-populated
    // state (scores, voteResults) and can be unavailable mid-simulation.
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
      // Deterministic tie-break mirrors EliminateHandler: sort by
      // (count desc, name desc) and take the first.
      let top =
        state.voteResults
        .sorted(by: { ($0.value, $0.key) > ($1.value, $1.key) })
        .first
      if let winner = top {
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

  /// Compares two resolved string values. If both parse as `Double`, compares
  /// numerically; otherwise compares as strings. Dispatching through a
  /// Comparable-generic helper keeps the operator table in one place.
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
