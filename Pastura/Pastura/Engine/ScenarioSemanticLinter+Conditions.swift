import Foundation

/// Condition-expression rules R13/R14/R15/R16 (ADR-022 D3), applied to every
/// `conditional` phase's **parsed** `if:` string (`phase.condition`) — never
/// raw YAML, whose scalar quoting (`if: 'current_event != ""'`) is already
/// stripped by the loader. Every finding anchors to the conditional's
/// top-level phase-list index (conditionals are depth-1, always top-level).
///
/// The rules reuse `ConditionEvaluator`'s own parser (``ConditionEvaluator/parseToAST(_:)``,
/// same module) rather than re-tokenizing, so operand semantics match the real
/// evaluator exactly. Each comparison node yields its `lhs` / `rhs` operand
/// strings in source form (identifiers as-is, dotted access like `scores.Alice`
/// whole, string literals *with* their surrounding `"`), which is precisely what
/// classification needs. Operands are deduped per condition, so one token yields
/// at most one finding:
///
/// - **R13 `single-quoted-literal-in-condition`** (error) — an operand wrapped
///   in single quotes (`'Alice'`). The evaluator's tokenizer treats only `"` as
///   a string delimiter, so `'Alice'` becomes a never-defined identifier and the
///   comparison silently yields false.
/// - **R14 `bare-identifier-looks-like-literal`** (error) — an unquoted `==`/`!=`
///   operand that is an unknown identifier AND exactly matches a persona name
///   (`vote_winner == Alice`): the author certainly meant a string literal.
///   R14 is the persona-name match only.
/// - **R15 `unknown-condition-identifier`** (warning) — any other identifier not
///   in the known set (below) — a typo (`max_scores`) or a stray name
///   (`scores.NotAPersona`) — that resolves absent at runtime.
/// - **R16 `short-circuit-hidden-typo`** (info) — implemented as a **no-op** (see
///   ``conditionFindings(in:)``).
///
/// **Known-identifier set** (getting this wrong false-positives shipped
/// `word_wolf` — `vote_winner == wolf_name`, `current_event != ""`):
/// the derived read-only variables `ConditionEvaluator` resolves
/// (`current_round`, `total_rounds`, `eliminated_count`, `active_count`,
/// `max_score`, `min_score`, `vote_winner`) ∪ `scores.<PersonaName>` for
/// declared personas ∪ scenario `extraData` keys ∪ engine-injected reserved
/// state-variable names (`wolf_name`, `vote_results`, `assigned_topic`, the
/// per-persona `assigned_<name>` / `notes_<name>` / `whispers_<name>` /
/// `relationships_<name>` forms, and each `event_inject` event variable —
/// default `current_event` or a custom `as:` — plus its `__favors` companion).
/// Prompt-only tokens (`{my_notes}`, `{assigned}`, …) are deliberately absent:
/// they are never written to `state.variables`, so as condition identifiers they
/// resolve absent and are correctly R15.
nonisolated extension ScenarioSemanticLinter {

  /// The derived read-only variables `ConditionEvaluator` resolves on either
  /// side of a comparison (`resolveAlwaysPresentDerived` + `resolveMayBeAbsentDerived`).
  /// Kept in lockstep with that resolver — a divergence here false-positives.
  static let conditionDerivedVariables: Set<String> = [
    "current_round", "total_rounds", "eliminated_count", "active_count",
    "max_score", "min_score", "vote_winner"
  ]

  /// Condition-expression findings (R13/R14/R15).
  ///
  /// R16 (`short-circuit-hidden-typo`, info) is a deliberate **no-op**: R13–R15
  /// walk the *full* AST, so they already statically resolve BOTH sides of every
  /// `&&`/`||` — unlike the runtime's short-circuit walker, which never asks the
  /// resolver about a skipped sub-expression. A typo in a never-evaluated branch
  /// is therefore already surfaced by R13–R15, delivering R16's value. Firing a
  /// *separate* info finding would require constant-folding operand values to
  /// decide which side the runtime would skip, but those values depend on runtime
  /// state (`current_round`, scores) absent at lint time — so no cheap, clean
  /// derivation exists, and the ADR ships "at most one info rule". Hence R16
  /// emits nothing on its own.
  func conditionFindings(in scenario: Scenario) -> [LintFinding] {
    let known = knownConditionIdentifiers(in: scenario)
    let personaNames = Set(scenario.personas.map(\.name))
    var findings: [LintFinding] = []
    // Conditionals are depth-1, so a top-level scan reaches every one.
    for (index, phase) in scenario.phases.enumerated() where phase.type == .conditional {
      guard let condition = phase.condition,
        let ast = try? ConditionEvaluator().parseToAST(condition)
      else {
        // A malformed `if:` is ScenarioValidator's gate, not the linter's — skip.
        continue
      }
      var equalityContext: [String: Bool] = [:]
      operandEqualityContext(ast, into: &equalityContext)
      for text in equalityContext.keys.sorted() {
        if let finding = classifyOperand(
          text, isEquality: equalityContext[text] ?? false, index: index,
          known: known, personaNames: personaNames) {
          findings.append(finding)
        }
      }
    }
    return findings
  }

  // MARK: - Operand collection

  /// Walks the parsed AST, recording each distinct operand string and whether
  /// it ever appears as an `==`/`!=` side (R14 applies only in equality context).
  private func operandEqualityContext(
    _ node: ConditionEvaluator.Node, into context: inout [String: Bool]
  ) {
    switch node {
    case .comparison(let lhs, let symbol, let rhs):
      let isEquality = symbol == "==" || symbol == "!="
      context[lhs, default: false] = context[lhs, default: false] || isEquality
      context[rhs, default: false] = context[rhs, default: false] || isEquality
    case .logicalAnd(let lhs, let rhs), .logicalOr(let lhs, let rhs):
      operandEqualityContext(lhs, into: &context)
      operandEqualityContext(rhs, into: &context)
    }
  }

  // MARK: - Classification (single-fire per token)

  /// Classifies one distinct operand into at most one finding (R13/R14/R15), or
  /// `nil` when it is a valid operand (number, double-quoted literal, or known
  /// identifier). Dedup contract: a persona-name match yields R14 and nothing
  /// else; any other unknown yields R15 — never both.
  private func classifyOperand(
    _ text: String, isEquality: Bool, index: Int,
    known: Set<String>, personaNames: Set<String>
  ) -> LintFinding? {
    if Double(text) != nil { return nil }
    if text.hasPrefix("\"") && text.hasSuffix("\"") && text.count >= 2 { return nil }
    if text.hasPrefix("'") || text.hasSuffix("'") {
      return conditionFinding("single-quoted-literal-in-condition", .error, text, index)
    }
    if let dotIndex = text.firstIndex(of: ".") {
      let head = String(text[..<dotIndex])
      let tail = String(text[text.index(after: dotIndex)...])
      if head == "scores" && personaNames.contains(tail) { return nil }
      return conditionFinding("unknown-condition-identifier", .warning, text, index)
    }
    if known.contains(text) { return nil }
    if isEquality && personaNames.contains(text) {
      return conditionFinding("bare-identifier-looks-like-literal", .error, text, index)
    }
    return conditionFinding("unknown-condition-identifier", .warning, text, index)
  }

  // MARK: - Known-identifier set

  /// The bare identifiers that resolve to a runtime value in a condition — the
  /// derived variables ∪ engine-injected reserved `state.variables` names ∪
  /// per-persona reserved forms ∪ `extraData` keys ∪ each `event_inject`
  /// variable and its `__favors` companion. `scores.<persona>` is dotted and
  /// handled in ``classifyOperand(_:isEquality:index:known:personaNames:)``.
  private func knownConditionIdentifiers(in scenario: Scenario) -> Set<String> {
    var known = Self.conditionDerivedVariables
    known.insert("wolf_name")
    known.insert("vote_results")
    known.insert("assigned_topic")
    known.formUnion(scenario.extraData.keys)
    for persona in scenario.personas {
      known.insert("assigned_\(persona.name)")
      known.insert("notes_\(persona.name)")
      known.insert("whispers_\(persona.name)")
      known.insert("relationships_\(persona.name)")
    }
    for ref in phaseRefs(in: scenario.phases, where: { $0.type == .eventInject }) {
      let name = ref.phase.eventVariable ?? EventInjectHandler.defaultVariableName
      known.insert(name)
      known.insert(EventInjectHandler.favoredVariableName(for: name))
    }
    return known
  }

  // MARK: - Findings

  /// Builds a condition finding with its token-interpolated fix-hint message.
  private func conditionFinding(
    _ ruleID: String, _ severity: LintSeverity, _ token: String, _ index: Int
  ) -> LintFinding {
    LintFinding(
      ruleID: ruleID, severity: severity,
      message: conditionMessage(ruleID, token: token), phaseIndex: index)
  }

  /// The user-facing fix-hint message for a condition `ruleID`, naming the
  /// offending operand. Catalog `ja` fill is a later item.
  private func conditionMessage(_ ruleID: String, token: String) -> String {
    switch ruleID {
    case "single-quoted-literal-in-condition":
      return String(
        format: String(
          localized:
            "single-quoted-literal-in-condition: the operand %@ is single-quoted, but the condition evaluator treats only double quotes as string literals — it is read as an undefined identifier and the comparison is always false. Use double quotes instead."
        ), token)
    case "bare-identifier-looks-like-literal":
      return String(
        format: String(
          localized:
            "bare-identifier-looks-like-literal: the operand '%@' matches a persona name but is unquoted, so the condition evaluator reads it as an undefined identifier and the comparison is always false — wrap it in double quotes to compare against the name."
        ), token)
    default:
      return String(
        format: String(
          localized:
            "unknown-condition-identifier: '%@' is not a known condition variable (a derived variable, score, persona, extraData key, or engine-injected name), so it resolves to no value at runtime — check for a typo."
        ), token)
    }
  }
}
