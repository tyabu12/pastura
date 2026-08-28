// The Condition group's ruleID → ScenarioLintMessage pin (ADR-024 D3). Its
// own file for symmetry with ScenarioSemanticLinterTests+OrderingMessages.swift,
// +ConfigMessages.swift, and +PlaceholderMessages.swift — kept apart so the
// four group pins read alike. Still an extension of the existing suite (not a
// new @Suite) per .claude/rules/testing.md.
import Testing

@testable import Pastura

extension ScenarioSemanticLinterTests {

  /// One row of ``conditionMessagesMapEachRuleIDToItsLintMessageCase``'s pin:
  /// a fixture expected to fire exactly `ruleID`, and the message it must
  /// render. A struct rather than a tuple — SwiftLint caps tuples at two
  /// members.
  private struct ConditionMessageCase {
    let ruleID: String
    let scenario: Scenario
    let expected: ScenarioLintMessage
  }

  /// R13/R14/R15 — the three condition rules, one offending token each.
  private var conditionMessageCases: [ConditionMessageCase] {
    [
      ConditionMessageCase(
        ruleID: "single-quoted-literal-in-condition",
        scenario: makeScenario(
          agents: 2, rounds: 1,
          phases: [conditionMessagePhase("vote_winner == 'Alice'")]),
        expected: .singleQuotedLiteralInCondition(token: "'Alice'")),
      ConditionMessageCase(
        ruleID: "bare-identifier-looks-like-literal",
        scenario: makeScenario(
          agents: 2, rounds: 1,
          phases: [conditionMessagePhase("vote_winner == A0")]),
        expected: .bareIdentifierLooksLikeLiteral(token: "A0")),
      ConditionMessageCase(
        ruleID: "unknown-condition-identifier",
        scenario: makeScenario(
          agents: 2, rounds: 1,
          phases: [conditionMessagePhase("max_scores > 5")]),
        expected: .unknownConditionIdentifier(token: "max_scores"))
    ]
  }

  // MARK: - Message mapping (deliberate exception to the one-test-per-rule shape)

  /// The Condition-group twin of
  /// ``placeholderMessagesMapEachRuleIDToItsLintMessageCase`` /
  /// ``configMessagesMapEachRuleIDToItsLintMessageCase`` /
  /// ``orderingMessagesMapEachRuleIDToItsLintMessageCase``: no other test in
  /// this suite asserts `finding.message` for a condition rule, so a
  /// mis-transcribed arm in the private `conditionMessage(_:token:)` — a
  /// string switch with a `default:` fallthrough for
  /// `unknown-condition-identifier` — would ship green with nothing to catch
  /// it. Each row fires exactly one condition rule and pins its rendered
  /// message, token interpolation included; `count == 1` and the `ruleID` are
  /// pinned too, so a rule that starts firing first on one of these fixtures
  /// cannot silently change what is measured. Findings are read through
  /// `conditionFindings(in:)`, isolating the pin from the
  /// ordering/config/placeholder groups. Mirrors
  /// `ScenarioSemanticLinterConditionsTests.conditionMessagesMapEachRuleIdToItsLintMessageCase`.
  ///
  /// Limit, stated so nobody reads it as a proof: the 3-entry list is a
  /// hand-maintained pin — a fourth condition rule must be added here by
  /// hand, nothing reddens otherwise.
  @Test func conditionMessagesMapEachRuleIDToItsLintMessageCase() {
    let cases = conditionMessageCases
    // Pin, not proof: a new condition rule must be added to `cases` by hand.
    #expect(cases.count == 3)
    for testCase in cases {
      let findings = linter.conditionFindings(in: testCase.scenario)
      #expect(findings.count == 1, "\(testCase.ruleID)")
      #expect(findings.first?.ruleID == testCase.ruleID, "\(testCase.ruleID)")
      #expect(findings.first?.message == testCase.expected.localized, "\(testCase.ruleID)")
    }
  }
}

// A depth-1 `conditional` phase carrying `ifExpr`, with a trivial then-branch
// (a `summarize` with a placeholder-free template so no other rule fires).
// Duplicated from `ScenarioSemanticLinterTests+Conditions.swift`'s
// file-private `conditionalPhase(_:)` — that helper is private to its own
// file, so this file carries its own copy under a name that doesn't collide.
private func conditionMessagePhase(_ ifExpr: String) -> Phase {
  Phase(
    type: .conditional, condition: ifExpr,
    thenPhases: [Phase(type: .summarize, template: "done")])
}
