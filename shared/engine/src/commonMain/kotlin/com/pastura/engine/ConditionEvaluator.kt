package com.pastura.engine

import com.pastura.models.Scenario
import com.pastura.models.SimulationError
import com.pastura.models.SimulationState

/**
 * Evaluates a boolean condition expression used by the `conditional` phase
 * type. Supports `&&` / `||` combinators and parenthesized grouping on top of a
 * single-comparison primitive.
 *
 * Kotlin port of `Pastura/Pastura/Engine/ConditionEvaluator.swift` +
 * `ConditionEvaluator+Parser.swift` (#501 Stage 2-pre / ADR-023 §6). The Swift
 * original splits tokenizer/parser into a sibling `nonisolated extension` to
 * dodge a default-MainActor isolation trap; Kotlin has no such trap, so the
 * whole grammar (public API, walker, resolver, tokenizer, recursive-descent
 * parser) lives in this one file. The Swift `ConditionEvaluator` is NOT deleted —
 * iOS keeps using it; this port runs in parallel until the Stage-5 consumption
 * switch. `ConditionEvaluatorTests` (commonTest) is the cross-language executable
 * spec.
 *
 * Grammar:
 * ```
 * expression ::= or
 * or         ::= and ('||' and)*
 * and        ::= factor ('&&' factor)*
 * factor     ::= '(' or ')'  |  comparison
 * comparison ::= operand OP operand
 * OP         ::= "==" | "!=" | "<=" | ">=" | "<" | ">"
 * operand    ::= Identifier ("." Identifier)? | NumberLiteral | StringLiteral
 * StringLiteral ::= '"' .* '"'
 * ```
 *
 * Precedence (loosest to tightest): `||` < `&&` < comparison. Both are
 * left-associative. Parens group any boolean sub-expression; an operand itself
 * cannot be parenthesized (`(current_round) == 1` is rejected).
 *
 * Tokenization is quote-aware: operator-like characters inside a quoted string
 * literal (`"a && b"`, `"x>y"`, `"(foo)"`) are literal content, not tokens.
 *
 * Derived read-only variables (either side of a comparison): `current_round`,
 * `total_rounds`, `max_score`, `min_score`, `eliminated_count`, `active_count`,
 * `vote_winner` (most-voted name, ties broken like `EliminateHandler`),
 * `scores.<Name>`. Any other identifier resolves from `state.variables`.
 *
 * **Parse-time errors** (missing operator, empty operand, mismatched/empty
 * parens, dangling `&&`/`||`, unterminated string) throw a [SimulationException]
 * carrying [SimulationError.ScenarioValidationFailed]. (Swift throws the sealed
 * `SimulationError` directly; Kotlin's is not a `Throwable`, so the Engine wraps
 * it — see [SimulationException].) Use [parse] to fail fast at scenario-load time.
 *
 * **Runtime-absent values** (e.g. `vote_winner` pre-vote, `scores.Nobody`) do NOT
 * throw; the comparison returns `value = false` and appends a warning to
 * [EvaluationResult.warnings].
 *
 * **Short-circuit policy** (Swift-style): the dropped side of `false && X` /
 * `true || X` is NOT resolved, so absent-variable warnings on the skipped branch
 * never appear.
 *
 * **Cross-language numeric parity.** Numeric detection uses a fixed decimal-literal
 * regex ([numericLiteralRegex]) rather than raw `String.toDoubleOrNull()`. Neither
 * raw parser is a stable cross-language predicate: Kotlin `toDoubleOrNull` accepts
 * `"Infinity"` / `"NaN"` / type-suffixed literals (`"1f"`) that are not plain
 * decimals, while Swift `Double(String)` accepts hex-floats (`"0x1p4"`) Kotlin
 * rejects. The regex accepts a token iff it is a plain optionally-signed decimal
 * with optional fraction / exponent — identical in Swift and Kotlin on that
 * grammar. Everything else (`Infinity` / `NaN` / suffixed `1f` — normalizing
 * Kotlin's laxer acceptance; hex-floats — the one Swift accepts) takes the string
 * path. All out-of-domain: real operands are integers or names. Pinned by
 * `ConditionEvaluatorParityTests`.
 */
public class ConditionEvaluator {

    /** Result of evaluating a condition expression. */
    public data class EvaluationResult(
        /**
         * The evaluated boolean. `false` when a comparison's operand is
         * runtime-absent, or when the sub-expression's truth value (and
         * short-circuit policy) drives it false.
         */
        public val value: Boolean,
        /**
         * Non-fatal diagnostics (e.g. runtime-absent variables). Warnings from
         * short-circuited sub-expressions are suppressed by design.
         */
        public val warnings: List<String>,
    )

    /** Lexical token classes recognized by the DSL. */
    internal sealed interface Token {
        data object OpenParen : Token
        data object CloseParen : Token
        data object LogicalAnd : Token
        data object LogicalOr : Token
        data class ComparisonOp(val symbol: String) : Token

        /**
         * String preserving its source form: numbers as their digits, bare
         * identifiers as-is (including dotted access like `scores.Alice`), and
         * quoted strings WITH surrounding `"` so the resolver can distinguish
         * `Alice` (identifier) from `"Alice"` (string literal).
         */
        data class Operand(val text: String) : Token
    }

    /** AST node for the parsed expression (Swift's `indirect enum`). */
    internal sealed interface Node {
        data class LogicalOr(val lhs: Node, val rhs: Node) : Node
        data class LogicalAnd(val lhs: Node, val rhs: Node) : Node
        data class Comparison(val lhs: String, val symbol: String, val rhs: String) : Node
    }

    /**
     * Evaluates [expression] against [state] and [scenario].
     *
     * @throws SimulationException carrying [SimulationError.ScenarioValidationFailed]
     *   for parse-time errors.
     */
    public fun evaluate(
        expression: String,
        state: SimulationState,
        scenario: Scenario,
    ): EvaluationResult {
        val ast = parseToAST(expression)
        return walk(ast, state, scenario)
    }

    /**
     * Parses [expression] and discards the AST. Used to surface malformed `if:`
     * strings at scenario-load time, before any `state` exists.
     *
     * @throws SimulationException on syntactic errors. Runtime-absent identifiers
     *   do NOT throw — those only surface during [evaluate] as warnings.
     */
    public fun parse(expression: String) {
        parseToAST(expression)
    }

    // MARK: - AST walker (with short-circuit)

    private fun walk(node: Node, state: SimulationState, scenario: Scenario): EvaluationResult =
        when (node) {
            is Node.Comparison ->
                walkComparison(node.lhs, node.symbol, node.rhs, state, scenario)

            is Node.LogicalAnd -> {
                val lhsResult = walk(node.lhs, state, scenario)
                // Short-circuit: dropped side is NOT resolved, so its warnings
                // never enter the result. Documented Swift-style policy.
                if (!lhsResult.value) {
                    lhsResult
                } else {
                    val rhsResult = walk(node.rhs, state, scenario)
                    EvaluationResult(rhsResult.value, lhsResult.warnings + rhsResult.warnings)
                }
            }

            is Node.LogicalOr -> {
                val lhsResult = walk(node.lhs, state, scenario)
                if (lhsResult.value) {
                    lhsResult
                } else {
                    val rhsResult = walk(node.rhs, state, scenario)
                    EvaluationResult(rhsResult.value, lhsResult.warnings + rhsResult.warnings)
                }
            }
        }

    private fun walkComparison(
        lhs: String,
        symbol: String,
        rhs: String,
        state: SimulationState,
        scenario: Scenario,
    ): EvaluationResult {
        val warnings = mutableListOf<String>()
        val lhsValue = resolve(lhs, state, scenario, warnings)
        val rhsValue = resolve(rhs, state, scenario, warnings)
        if (lhsValue == null || rhsValue == null) {
            return EvaluationResult(false, warnings)
        }
        return EvaluationResult(compare(lhsValue, symbol, rhsValue), warnings)
    }

    // MARK: - Operand resolution

    /**
     * Resolves a token to a string value, or `null` if the identifier refers to
     * data not present at runtime (with a warning appended to [warnings]).
     */
    private fun resolve(
        token: String,
        state: SimulationState,
        scenario: Scenario,
        warnings: MutableList<String>,
    ): String? {
        if (token.length >= 2 && token.startsWith("\"") && token.endsWith("\"")) {
            return token.substring(1, token.length - 1)
        }
        if (isNumericLiteral(token)) {
            return token
        }
        val dotIndex = token.indexOf('.')
        if (dotIndex >= 0) {
            return resolveDotted(token, dotIndex, state, warnings)
        }

        when (val derived = resolveDerived(token, state, scenario, warnings)) {
            is DerivedResolution.Value -> return derived.value
            DerivedResolution.Absent -> return null
            DerivedResolution.NotDerived -> Unit
        }

        state.variables[token]?.let { return it }
        warnings.add("Unknown identifier '$token'")
        return null
    }

    private fun resolveDotted(
        token: String,
        dotIndex: Int,
        state: SimulationState,
        warnings: MutableList<String>,
    ): String? {
        val head = token.substring(0, dotIndex)
        val tail = token.substring(dotIndex + 1)
        if (head == "scores") {
            state.scores[tail]?.let { return it.toString() }
            warnings.add("scores.$tail is not set (agent absent from scores)")
            return null
        }
        warnings.add("Unknown dotted identifier '$token'")
        return null
    }

    /** Tri-state result for derived-variable resolution. */
    private sealed interface DerivedResolution {
        data class Value(val value: String) : DerivedResolution

        /** Recognized as derived but has no runtime value (warning already appended). */
        data object Absent : DerivedResolution

        /** Not a derived variable at all; caller falls through to `state.variables`. */
        data object NotDerived : DerivedResolution
    }

    private fun resolveDerived(
        identifier: String,
        state: SimulationState,
        scenario: Scenario,
        warnings: MutableList<String>,
    ): DerivedResolution {
        resolveAlwaysPresentDerived(identifier, state, scenario)?.let {
            return DerivedResolution.Value(it)
        }
        return resolveMayBeAbsentDerived(identifier, state, warnings)
    }

    private fun resolveAlwaysPresentDerived(
        identifier: String,
        state: SimulationState,
        scenario: Scenario,
    ): String? = when (identifier) {
        "current_round" -> state.currentRound.toString()
        "total_rounds" -> scenario.rounds.toString()
        "eliminated_count" -> state.eliminated.values.count { it }.toString()
        "active_count" -> state.eliminated.values.count { !it }.toString()
        else -> null
    }

    private fun resolveMayBeAbsentDerived(
        identifier: String,
        state: SimulationState,
        warnings: MutableList<String>,
    ): DerivedResolution = when (identifier) {
        "max_score" ->
            resolveScoreExtremum(state.scores.values.maxOrNull(), "max_score", warnings)

        "min_score" ->
            resolveScoreExtremum(state.scores.values.minOrNull(), "min_score", warnings)

        "vote_winner" -> {
            // Deterministic tie-break mirrors EliminateHandler: sort by
            // (count desc, name desc) and take the first. Kotlin string order
            // (UTF-16) matches Swift scalar order across the BMP (agent names);
            // see the port's numeric/ordering-parity doc note and
            // ConditionEvaluatorParityTests. Future parity with a ported
            // EliminateHandler is a Stage-3 concern.
            val top = state.voteResults.entries
                .sortedWith(
                    compareByDescending<Map.Entry<String, Int>> { it.value }
                        .thenByDescending { it.key },
                )
                .firstOrNull()
            if (top != null) {
                DerivedResolution.Value(top.key)
            } else {
                warnings.add("vote_winner has no value (no vote phase has run this round)")
                DerivedResolution.Absent
            }
        }

        else -> DerivedResolution.NotDerived
    }

    private fun resolveScoreExtremum(
        value: Int?,
        label: String,
        warnings: MutableList<String>,
    ): DerivedResolution {
        if (value != null) {
            return DerivedResolution.Value(value.toString())
        }
        warnings.add("$label has no value (scores is empty)")
        return DerivedResolution.Absent
    }

    // MARK: - Comparison

    private fun compare(lhs: String, symbol: String, rhs: String): Boolean {
        val lhsNum = numericValue(lhs)
        val rhsNum = numericValue(rhs)
        if (lhsNum != null && rhsNum != null) {
            return applyOperator(symbol, lhsNum, rhsNum)
        }
        return applyOperator(symbol, lhs, rhs)
    }

    private fun applyOperator(symbol: String, lhs: Double, rhs: Double): Boolean = when (symbol) {
        "==" -> lhs == rhs
        "!=" -> lhs != rhs
        "<" -> lhs < rhs
        "<=" -> lhs <= rhs
        ">" -> lhs > rhs
        ">=" -> lhs >= rhs
        else -> false
    }

    private fun applyOperator(symbol: String, lhs: String, rhs: String): Boolean = when (symbol) {
        "==" -> lhs == rhs
        "!=" -> lhs != rhs
        "<" -> lhs < rhs
        "<=" -> lhs <= rhs
        ">" -> lhs > rhs
        ">=" -> lhs >= rhs
        else -> false
    }

    // MARK: - Tokenizer

    private fun tokenize(expression: String): List<Token> {
        val chars = expression
        val tokens = mutableListOf<Token>()
        var index = 0

        while (index < chars.length) {
            val char = chars[index]
            if (char.isWhitespace()) {
                index += 1
                continue
            }
            // Two-char operators scanned before single-char prefixes so `<=` is
            // not split into `<` + `=`, and `&&` / `||` are not read as bare chars.
            val multi = readMultiCharToken(chars, index)
            if (multi != null) {
                tokens.add(multi.first)
                index += multi.second
                continue
            }
            val single = readSingleCharToken(chars, index)
            if (single != null) {
                tokens.add(single.first)
                index += single.second
                continue
            }
            if (char == '"') {
                val quoted = readQuotedOperand(chars, index, expression)
                tokens.add(quoted.first)
                index = quoted.second
                continue
            }
            val bare = readBareOperand(chars, index, expression)
            tokens.add(bare.first)
            index = bare.second
        }

        return tokens
    }

    /** Two-character operators (`&&`, `||`, `==`, `!=`, `<=`, `>=`); `null` otherwise. */
    private fun readMultiCharToken(chars: String, index: Int): Pair<Token, Int>? {
        if (index + 1 >= chars.length) return null
        val pair = chars.substring(index, index + 2)
        return when (pair) {
            "&&" -> Token.LogicalAnd to 2
            "||" -> Token.LogicalOr to 2
            "==", "!=", "<=", ">=" -> Token.ComparisonOp(pair) to 2
            else -> null
        }
    }

    /** Single-character tokens (`(`, `)`, `<`, `>`); `null` otherwise. */
    private fun readSingleCharToken(chars: String, index: Int): Pair<Token, Int>? =
        when (chars[index]) {
            '(' -> Token.OpenParen to 1
            ')' -> Token.CloseParen to 1
            '<', '>' -> Token.ComparisonOp(chars[index].toString()) to 1
            else -> null
        }

    /** Quoted string operand. Keeps the surrounding `"` so the resolver can tell literals apart. */
    private fun readQuotedOperand(chars: String, index: Int, source: String): Pair<Token, Int> {
        var end = index + 1
        while (end < chars.length && chars[end] != '"') {
            end += 1
        }
        if (end >= chars.length) {
            throw SimulationException(
                SimulationError.ScenarioValidationFailed(
                    "Condition expression '$source' has unterminated string literal",
                ),
            )
        }
        return Token.Operand(chars.substring(index, end + 1)) to (end + 1)
    }

    /**
     * Bare operand: identifier, number, or dotted access. Accumulates until a
     * delimiter (whitespace, paren, quote, operator-prefix) is hit.
     */
    private fun readBareOperand(chars: String, index: Int, source: String): Pair<Token, Int> {
        var end = index
        while (end < chars.length && !isOperandDelimiter(chars, end)) {
            end += 1
        }
        if (end == index) {
            throw SimulationException(
                SimulationError.ScenarioValidationFailed(
                    "Condition expression '$source' contains unexpected character '${chars[index]}'",
                ),
            )
        }
        return Token.Operand(chars.substring(index, end)) to end
    }

    /** True when `chars[end]` starts a delimiter that terminates a bare operand. */
    private fun isOperandDelimiter(chars: String, end: Int): Boolean {
        val next = chars[end]
        if (next.isWhitespace()) return true
        if (next == '(' || next == ')' || next == '"') return true
        if (next == '<' || next == '>') return true
        if (end + 1 < chars.length) {
            val pair = chars.substring(end, end + 2)
            if (pair == "&&" || pair == "||" ||
                pair == "==" || pair == "!=" ||
                pair == "<=" || pair == ">="
            ) {
                return true
            }
        }
        return false
    }

    // MARK: - Parser entry point

    private fun parseToAST(expression: String): Node {
        val tokens = tokenize(expression)
        if (tokens.isEmpty()) {
            throw SimulationException(
                SimulationError.ScenarioValidationFailed(
                    "Condition expression '$expression' is empty",
                ),
            )
        }
        val parser = Parser(tokens, expression)
        val node = parser.parseOr()
        if (parser.position < tokens.size) {
            throw SimulationException(
                SimulationError.ScenarioValidationFailed(
                    "Condition expression '$expression' has unexpected trailing token " +
                        "near position ${parser.position} (likely an unmatched ')' or extra operator)",
                ),
            )
        }
        return node
    }

    /**
     * Recursive-descent parser. [position] is the cursor into [tokens]; each
     * `parseX` advances it past the tokens it consumed.
     */
    private class Parser(
        private val tokens: List<Token>,
        private val source: String,
    ) {
        var position: Int = 0

        private fun peek(): Token? = if (position < tokens.size) tokens[position] else null

        private fun advance() {
            position += 1
        }

        fun parseOr(): Node {
            var lhs = parseAnd()
            while (peek() == Token.LogicalOr) {
                advance()
                val rhs = parseAnd()
                lhs = Node.LogicalOr(lhs, rhs)
            }
            return lhs
        }

        private fun parseAnd(): Node {
            var lhs = parseFactor()
            while (peek() == Token.LogicalAnd) {
                advance()
                val rhs = parseFactor()
                lhs = Node.LogicalAnd(lhs, rhs)
            }
            return lhs
        }

        private fun parseFactor(): Node {
            if (peek() == Token.OpenParen) {
                advance()
                // Empty parens `()` — guard so the message is specific rather than
                // the generic "expected operand (got ')')" from parseComparison.
                if (peek() == Token.CloseParen) {
                    throw SimulationException(
                        SimulationError.ScenarioValidationFailed(
                            "Condition expression '$source' has empty parentheses '()'",
                        ),
                    )
                }
                val inner = parseOr()
                if (peek() != Token.CloseParen) {
                    throw SimulationException(
                        SimulationError.ScenarioValidationFailed(
                            "Condition expression '$source' is missing ')' to close a " +
                                "parenthesized sub-expression",
                        ),
                    )
                }
                advance()
                return inner
            }
            return parseComparison()
        }

        private fun parseComparison(): Node {
            val lhsToken = peek()
            if (lhsToken !is Token.Operand) {
                throw SimulationException(
                    SimulationError.ScenarioValidationFailed(
                        "Condition expression '$source' expected an operand ${describeUnexpected()}",
                    ),
                )
            }
            advance()
            val opToken = peek()
            if (opToken !is Token.ComparisonOp) {
                throw SimulationException(
                    SimulationError.ScenarioValidationFailed(
                        "Condition expression '$source' expected a comparison operator " +
                            "(==, !=, <, <=, >, >=) after '${lhsToken.text}' ${describeUnexpected()}",
                    ),
                )
            }
            advance()
            val rhsToken = peek()
            if (rhsToken !is Token.Operand) {
                throw SimulationException(
                    SimulationError.ScenarioValidationFailed(
                        "Condition expression '$source' expected an operand after " +
                            "'${lhsToken.text} ${opToken.symbol}' ${describeUnexpected()}",
                    ),
                )
            }
            advance()
            return Node.Comparison(lhsToken.text, opToken.symbol, rhsToken.text)
        }

        /** Short " (got 'X')" hint for the current token, or end-of-expression. */
        private fun describeUnexpected(): String =
            when (val token = peek()) {
                null -> "(reached end of expression)"
                Token.OpenParen -> "(got '(')"
                Token.CloseParen -> "(got ')')"
                Token.LogicalAnd -> "(got '&&')"
                Token.LogicalOr -> "(got '||')"
                is Token.ComparisonOp -> "(got '${token.symbol}')"
                is Token.Operand -> "(got '${token.text}')"
            }
    }

    private companion object {
        /**
         * A plain optionally-signed decimal with optional fraction / exponent.
         * Used for numeric detection in both [resolve] and [compare] so the
         * numeric-vs-string branch is identical across Swift and Kotlin — see the
         * class doc note on cross-language numeric parity.
         */
        private val numericLiteralRegex = Regex("^[+-]?[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?$")

        private fun isNumericLiteral(token: String): Boolean = numericLiteralRegex.matches(token)

        private fun numericValue(token: String): Double? =
            if (isNumericLiteral(token)) token.toDouble() else null
    }
}
