// The Config group's ruleID → ScenarioLintMessage pin (ADR-024 D3). Its own
// file for symmetry with ScenarioSemanticLinterTests+OrderingMessages.swift,
// which had to split — `+Payoff.swift` has room for this test, but keeping the
// three group pins shaped alike is worth more than saving a file. Still an
// extension of the existing suite (not a new @Suite) per
// .claude/rules/testing.md.
import Testing

@testable import Pastura

extension ScenarioSemanticLinterTests {

  /// One row of ``configMessagesMapEachRuleIDToItsLintMessageCase``'s pin: a
  /// fixture expected to fire exactly `ruleID`, and the message it must render.
  /// A struct rather than a tuple — SwiftLint caps tuples at two members.
  private struct ConfigMessageCase {
    let ruleID: String
    let scenario: Scenario
    let expected: ScenarioLintMessage
  }

  /// R7/R8/R9/R17 — the four config rules whose fixtures need no `payoff`.
  private var configMessageCasesR7ToR17: [ConfigMessageCase] {
    [
      ConfigMessageCase(
        ruleID: "choose-should-declare-options",
        scenario: makeScenario(agents: 2, rounds: 1, phases: [Phase(type: .choose)]),
        expected: .chooseShouldDeclareOptions),
      ConfigMessageCase(
        ruleID: "assign-source-nonempty",
        scenario: makeEventScenario(
          phases: [Phase(type: .assign, source: "events", target: .all)],
          events: .array([])),
        expected: .assignSourceNonempty),
      ConfigMessageCase(
        ruleID: "summarize-pairing-placeholders",
        scenario: makeScenario(
          agents: 2, rounds: 1,
          phases: [Phase(type: .summarize, template: "{agent1} chose {action1}")]),
        expected: .summarizePairingPlaceholders),
      ConfigMessageCase(
        ruleID: "log-window-below-agent-count",
        scenario: makeLogWindowScenario(
          agents: 3, logWindow: 2, phases: [Phase(type: .speakEach)]),
        expected: .logWindowBelowAgentCount)
    ]
  }

  /// R18/R20a/R20b — the remaining three.
  private var configMessageCasesR18ToR20b: [ConfigMessageCase] {
    [
      ConfigMessageCase(
        ruleID: "max-sentences-no-op",
        scenario: makeScenario(
          agents: 2, rounds: 1,
          phases: [Phase(type: .summarize, template: "Round complete.", maxSentences: 3)]),
        expected: .maxSentencesNoOp),
      ConfigMessageCase(
        ruleID: "pairwise-payoff-no-scorable-row",
        scenario: makeScenario(
          agents: 2, rounds: 1,
          phases: [
            Phase(type: .choose, options: ["cooperate", "betray"], pairing: .roundRobin),
            Phase(
              type: .scoreCalc, logic: .pairwisePayoff,
              payoff: [PayoffRule(when: ["yes", "no"], points: [1, 1])])
          ]),
        expected: .pairwisePayoffNoScorableRow),
      ConfigMessageCase(
        ruleID: "pairwise-payoff-dead-row",
        scenario: makeScenario(
          agents: 2, rounds: 1,
          phases: [
            Phase(type: .choose, options: ["cooperate", "betray"], pairing: .roundRobin),
            Phase(
              type: .scoreCalc, logic: .pairwisePayoff,
              payoff: [
                PayoffRule(when: ["cooperate", "cooperate"], points: [3, 3]),
                PayoffRule(when: ["unclear", "unclear"], points: [0, 0])
              ])
          ]),
        expected: .pairwisePayoffDeadRow)
    ]
  }

  // MARK: - Message mapping (deliberate exception to the one-test-per-rule shape)

  /// The Config-group twin of ``orderingMessagesMapEachRuleIDToItsLintMessageCase``:
  /// no other test in this suite asserts `finding.message` for a config rule,
  /// so a mis-transcribed arm in the private `configMessage(_:)` — a string
  /// switch with a `default:` fallthrough for `log-window-below-agent-count`
  /// — would ship green with nothing to catch it. Each row fires exactly one
  /// config rule and pins its rendered message; `count == 1` and the `ruleID`
  /// are pinned too, so a rule that starts firing first on one of these
  /// fixtures cannot silently change what is measured. Mirrors
  /// `ScenarioSemanticLinterPayoffTests.configMessagesMapEachRuleIdToItsLintMessageCase`.
  ///
  /// Two limits, stated so nobody reads them as proofs: (1) the 7-entry list
  /// is a hand-maintained pin — an eighth config rule must be added here by
  /// hand, nothing reddens otherwise; (2) `log-window-below-agent-count` has
  /// no explicit `configMessage` arm (Swift `default:` / Kotlin `else`), so
  /// its row cannot tell "arm correct" from "fell through".
  @Test func configMessagesMapEachRuleIDToItsLintMessageCase() {
    let cases = configMessageCasesR7ToR17 + configMessageCasesR18ToR20b
    // Pin, not proof: a new config rule must be added to `cases` by hand.
    #expect(cases.count == 7)
    for testCase in cases {
      let findings = linter.lint(testCase.scenario)
      #expect(findings.count == 1, "\(testCase.ruleID)")
      #expect(findings.first?.ruleID == testCase.ruleID, "\(testCase.ruleID)")
      #expect(findings.first?.message == testCase.expected.localized, "\(testCase.ruleID)")
    }
  }
}
