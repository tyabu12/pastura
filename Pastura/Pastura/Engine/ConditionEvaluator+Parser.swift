import Foundation

// Tokenizer + recursive-descent parser internals for the
// `ConditionEvaluator` DSL. Public surface, AST walker, and operand
// resolution live in `ConditionEvaluator.swift`.
//
// Token / Node types are nested on `ConditionEvaluator` (default
// internal access) so this sibling extension can reference them
// without widening visibility further. Sibling-file `private` would
// make the parser inaccessible from the main file.

// `nonisolated` at extension scope: under
// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, an unmarked extension on a
// `nonisolated public struct` would still infer MainActor for its
// members, breaking the call from the main file's nonisolated public
// `evaluate(_:state:scenario:)` / `parse(_:)` API. See `.claude/rules/llm.md`
// and the memory note on `nonisolated` for the same trap.
nonisolated extension ConditionEvaluator {

  // MARK: - Tokenizer

  func tokenize(_ expression: String) throws -> [Token] {
    let chars = Array(expression)
    var tokens: [Token] = []
    var index = 0

    while index < chars.count {
      let char = chars[index]
      if char.isWhitespace {
        index += 1
        continue
      }
      // Two-char operators scanned before single-char prefixes so that
      // `<=` is not split into `<` + `=`, and `&&` / `||` are not read
      // as bare-identifier characters.
      if let consumed = readMultiCharToken(chars, at: index) {
        tokens.append(consumed.token)
        index += consumed.advance
        continue
      }
      if let consumed = readSingleCharToken(chars, at: index) {
        tokens.append(consumed.token)
        index += consumed.advance
        continue
      }
      if char == "\"" {
        let consumed = try readQuotedOperand(chars, from: index, source: expression)
        tokens.append(consumed.token)
        index = consumed.endIndex
        continue
      }
      let consumed = try readBareOperand(chars, from: index, source: expression)
      tokens.append(consumed.token)
      index = consumed.endIndex
    }

    return tokens
  }

  /// Two-character operators (`&&`, `||`, `==`, `!=`, `<=`, `>=`).
  /// Returns `nil` when the next two chars are not a recognized pair.
  private func readMultiCharToken(
    _ chars: [Character], at index: Int
  ) -> (token: Token, advance: Int)? {
    guard index + 1 < chars.count else { return nil }
    let pair = String([chars[index], chars[index + 1]])
    switch pair {
    case "&&": return (.logicalAnd, 2)
    case "||": return (.logicalOr, 2)
    case "==", "!=", "<=", ">=": return (.comparisonOp(pair), 2)
    default: return nil
    }
  }

  /// Single-character tokens (`(`, `)`, `<`, `>`).
  private func readSingleCharToken(
    _ chars: [Character], at index: Int
  ) -> (token: Token, advance: Int)? {
    switch chars[index] {
    case "(": return (.openParen, 1)
    case ")": return (.closeParen, 1)
    case "<", ">": return (.comparisonOp(String(chars[index])), 1)
    default: return nil
    }
  }

  /// Quoted string operand. The token keeps the surrounding `"` so the
  /// resolver can distinguish string literals from identifiers.
  private func readQuotedOperand(
    _ chars: [Character], from index: Int, source: String
  ) throws -> (token: Token, endIndex: Int) {
    var end = index + 1
    while end < chars.count && chars[end] != "\"" {
      end += 1
    }
    if end >= chars.count {
      throw SimulationError.scenarioValidationFailed(
        "Condition expression '\(source)' has unterminated string literal"
      )
    }
    return (.operand(String(chars[index...end])), end + 1)
  }

  /// Bare operand: identifier, number, or dotted access. Accumulates
  /// until a delimiter (whitespace, paren, quote, operator-prefix) is
  /// hit. Returns the read range as a single `.operand` token.
  private func readBareOperand(
    _ chars: [Character], from index: Int, source: String
  ) throws -> (token: Token, endIndex: Int) {
    var end = index
    while end < chars.count, !isOperandDelimiter(chars, at: end) {
      end += 1
    }
    if end == index {
      throw SimulationError.scenarioValidationFailed(
        "Condition expression '\(source)' contains unexpected character "
          + "'\(chars[index])'"
      )
    }
    return (.operand(String(chars[index..<end])), end)
  }

  /// True when `chars[end]` (and possibly `chars[end+1]`) starts a
  /// delimiter that should terminate a bare-operand accumulation.
  private func isOperandDelimiter(_ chars: [Character], at end: Int) -> Bool {
    let next = chars[end]
    if next.isWhitespace { return true }
    if next == "(" || next == ")" || next == "\"" { return true }
    if next == "<" || next == ">" { return true }
    if end + 1 < chars.count {
      let pair = String([next, chars[end + 1]])
      if pair == "&&" || pair == "||"
        || pair == "==" || pair == "!="
        || pair == "<=" || pair == ">=" {
        return true
      }
    }
    return false
  }

  // MARK: - Parser entry point

  func parseToAST(_ expression: String) throws -> Node {
    let tokens = try tokenize(expression)
    if tokens.isEmpty {
      throw SimulationError.scenarioValidationFailed(
        "Condition expression '\(expression)' is empty"
      )
    }
    var parser = Parser(tokens: tokens, source: expression)
    let node = try parser.parseOr()
    if parser.position < tokens.count {
      throw SimulationError.scenarioValidationFailed(
        "Condition expression '\(expression)' has unexpected trailing token "
          + "near position \(parser.position) (likely an unmatched ')' or extra operator)"
      )
    }
    return node
  }

  /// Recursive-descent parser. `position` is the cursor into `tokens`;
  /// each `parseX` advances it past the tokens it consumed.
  struct Parser {
    let tokens: [Token]
    let source: String
    var position: Int = 0

    func peek() -> Token? {
      position < tokens.count ? tokens[position] : nil
    }

    mutating func advance() {
      position += 1
    }

    mutating func parseOr() throws -> Node {
      var lhs = try parseAnd()
      while case .logicalOr = peek() {
        advance()
        let rhs = try parseAnd()
        lhs = .logicalOr(lhs, rhs)
      }
      return lhs
    }

    mutating func parseAnd() throws -> Node {
      var lhs = try parseFactor()
      while case .logicalAnd = peek() {
        advance()
        let rhs = try parseFactor()
        lhs = .logicalAnd(lhs, rhs)
      }
      return lhs
    }

    mutating func parseFactor() throws -> Node {
      if case .openParen = peek() {
        advance()
        // Empty parens `()` — without this guard, the recursive parseOr
        // would fall through to parseFactor again and see `)`, throwing
        // a less-specific "expected operand (got ')')" message.
        if case .closeParen = peek() {
          throw SimulationError.scenarioValidationFailed(
            "Condition expression '\(source)' has empty parentheses '()'"
          )
        }
        let inner = try parseOr()
        guard case .closeParen = peek() else {
          throw SimulationError.scenarioValidationFailed(
            "Condition expression '\(source)' is missing ')' to close a "
              + "parenthesized sub-expression"
          )
        }
        advance()
        return inner
      }
      return try parseComparison()
    }

    mutating func parseComparison() throws -> Node {
      guard case .operand(let lhs) = peek() else {
        let hint = describeUnexpected()
        throw SimulationError.scenarioValidationFailed(
          "Condition expression '\(source)' expected an operand \(hint)"
        )
      }
      advance()
      guard case .comparisonOp(let symbol) = peek() else {
        let hint = describeUnexpected()
        throw SimulationError.scenarioValidationFailed(
          "Condition expression '\(source)' expected a comparison operator "
            + "(==, !=, <, <=, >, >=) after '\(lhs)' \(hint)"
        )
      }
      advance()
      guard case .operand(let rhs) = peek() else {
        let hint = describeUnexpected()
        throw SimulationError.scenarioValidationFailed(
          "Condition expression '\(source)' expected an operand after "
            + "'\(lhs) \(symbol)' \(hint)"
        )
      }
      advance()
      return .comparison(lhs: lhs, symbol: symbol, rhs: rhs)
    }

    /// Renders a short " (got 'X')" hint for the current token, or
    /// "(reached end of expression)" if exhausted.
    private func describeUnexpected() -> String {
      guard let token = peek() else {
        return "(reached end of expression)"
      }
      switch token {
      case .openParen: return "(got '(')"
      case .closeParen: return "(got ')')"
      case .logicalAnd: return "(got '&&')"
      case .logicalOr: return "(got '||')"
      case .comparisonOp(let symbol): return "(got '\(symbol)')"
      case .operand(let value): return "(got '\(value)')"
      }
    }
  }
}
