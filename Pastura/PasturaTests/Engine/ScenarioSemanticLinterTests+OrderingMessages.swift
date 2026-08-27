// The Ordering group's ruleID → ScenarioLintMessage pin (ADR-024 D3). Split
// out of ScenarioSemanticLinterTests+Ordering.swift, which is already at the
// 400-line SwiftLint cap; still an extension of the existing suite (not a new
// @Suite) per .claude/rules/testing.md.
import Testing

@testable import Pastura

extension ScenarioSemanticLinterTests {

  /// One row of ``orderingMessagesMapEachRuleIDToItsLintMessageCase``'s pin: a
  /// fixture expected to fire exactly `ruleID`, and the message it must render.
  /// A struct rather than a tuple — SwiftLint caps tuples at two members.
  private struct OrderingMessageCase {
    let ruleID: String
    let scenario: Scenario
    let expected: ScenarioLintMessage
  }

  /// A four-row payoff table over `{cooperate, betray}²`. Inlined rather than
  /// shared with `+Ordering.swift` / `+Payoff.swift`, whose equivalents are
  /// `private` to their own files.
  private var mappingPayoff: [PayoffRule] {
    [
      PayoffRule(when: ["cooperate", "cooperate"], points: [3, 3]),
      PayoffRule(when: ["cooperate", "betray"], points: [0, 5]),
      PayoffRule(when: ["betray", "cooperate"], points: [5, 0]),
      PayoffRule(when: ["betray", "betray"], points: [1, 1])
    ]
  }

  /// R1a/R1b/R2/R19 — the four rules whose fixtures need no `extraData`.
  private var orderingMessageCasesR1ToR19: [OrderingMessageCase] {
    [
      OrderingMessageCase(
        ruleID: "eliminate-needs-vote",
        scenario: makeScenario(agents: 2, rounds: 1, phases: [Phase(type: .eliminate)]),
        expected: .eliminateNeedsVote),
      OrderingMessageCase(
        ruleID: "eliminate-after-vote",
        scenario: makeScenario(
          agents: 2, rounds: 1, phases: [Phase(type: .eliminate), Phase(type: .vote)]),
        expected: .eliminateAfterVote),
      OrderingMessageCase(
        ruleID: "pd-needs-round-robin-choose",
        scenario: makeScenario(
          agents: 2, rounds: 1,
          phases: [
            Phase(type: .choose, options: ["cooperate", "betray"]),
            Phase(type: .scoreCalc, logic: .prisonersDilemma)
          ]),
        expected: .pdNeedsRoundRobinChoose),
      OrderingMessageCase(
        ruleID: "pairwise-payoff-needs-round-robin-choose",
        scenario: makeScenario(
          agents: 2, rounds: 1,
          phases: [
            Phase(type: .choose, options: ["cooperate", "betray"]),
            Phase(type: .scoreCalc, logic: .pairwisePayoff, payoff: mappingPayoff)
          ]),
        expected: .pairwisePayoffNeedsRoundRobinChoose)
    ]
  }

  /// R3/R5/R6 and the `default:`-arm rule — the remaining four.
  private var orderingMessageCasesR3ToVoteTally: [OrderingMessageCase] {
    [
      OrderingMessageCase(
        ruleID: "wordwolf-needs-assign-and-vote",
        scenario: makeScenario(
          agents: 2, rounds: 1, phases: [Phase(type: .scoreCalc, logic: .wordwolfJudge)]),
        expected: .wordwolfNeedsAssignAndVote),
      OrderingMessageCase(
        ruleID: "event-reactive-needs-event-inject",
        scenario: makeEventScenario(
          phases: [
            Phase(type: .eventInject, source: "events"),
            Phase(type: .scoreCalc, logic: .eventReactive)
          ],
          events: .array(["storm", "calm"])),
        expected: .eventReactiveNeedsEventInject),
      OrderingMessageCase(
        ruleID: "relationship-update-placement",
        scenario: makeScenario(
          agents: 2, rounds: 1, phases: [Phase(type: .relationshipUpdate, voteAgainst: -1)]),
        expected: .relationshipUpdatePlacement),
      OrderingMessageCase(
        ruleID: "vote-tally-needs-vote",
        scenario: makeScenario(
          agents: 2, rounds: 1, phases: [Phase(type: .scoreCalc, logic: .voteTally)]),
        expected: .voteTallyNeedsVote)
    ]
  }

  // MARK: - Message mapping (deliberate exception to the one-test-per-rule shape)

  /// The deliberate exception to the one-test-per-rule shape the rest of this
  /// suite keeps: no other test here asserts `finding.message`, so a
  /// mis-transcribed arm in the private
  /// `orderingMessage(_:)` — a string switch with a `default:` fallthrough —
  /// would ship green with nothing to catch it. Each row fires exactly one
  /// ordering rule and pins its rendered message; `count == 1` and the `ruleID`
  /// are pinned too, so a rule that starts firing first on one of these
  /// fixtures cannot silently change what is measured. Mirrors
  /// `ScenarioSemanticLinterOrderingTests.orderingMessagesMapEachRuleIdToItsLintMessageCase`.
  ///
  /// Two limits, stated so nobody reads them as proofs: (1) the 8-entry list is
  /// a hand-maintained pin — a ninth ordering rule must be added here by hand,
  /// nothing reddens otherwise; (2) `vote-tally-needs-vote` has no explicit
  /// `orderingMessage` arm on either side (Swift `default:` / Kotlin `else`),
  /// so its row cannot tell "arm correct" from "fell through".
  @Test func orderingMessagesMapEachRuleIDToItsLintMessageCase() {
    let cases = orderingMessageCasesR1ToR19 + orderingMessageCasesR3ToVoteTally
    // Pin, not proof: a new ordering rule must be added to `cases` by hand.
    #expect(cases.count == 8)
    for testCase in cases {
      let findings = linter.lint(testCase.scenario)
      #expect(findings.count == 1, "\(testCase.ruleID)")
      #expect(findings.first?.ruleID == testCase.ruleID, "\(testCase.ruleID)")
      #expect(findings.first?.message == testCase.expected.localized, "\(testCase.ruleID)")
    }
  }
}
