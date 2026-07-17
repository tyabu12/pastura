// R20a/R20b options ↔ payoff.when token rules (ADR-024 § Amendment 2026-07-17).
// Extension of the existing suite (not a new @Suite) per .claude/rules/testing.md
// — reuses `linter` / `makeScenario` from the base file.
import Testing

@testable import Pastura

extension ScenarioSemanticLinterTests {

  /// A four-row payoff table over `{cooperate, betray}²` — fully satisfiable by
  /// the `["cooperate", "betray"]` option set.
  private var satisfiablePayoff: [PayoffRule] {
    [
      PayoffRule(when: ["cooperate", "cooperate"], points: [3, 3]),
      PayoffRule(when: ["cooperate", "betray"], points: [0, 5]),
      PayoffRule(when: ["betray", "cooperate"], points: [5, 0]),
      PayoffRule(when: ["betray", "betray"], points: [1, 1])
    ]
  }

  private func roundRobinChoose(options: [String] = ["cooperate", "betray"]) -> Phase {
    Phase(type: .choose, options: options, pairing: .roundRobin)
  }

  // MARK: - R20a pairwise-payoff-no-scorable-row (error)

  @Test func payoffAllRowsOutsideOptionsFiresError() {
    // Every `when` token is outside the option set → no pairing ever scores.
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        roundRobinChoose(),
        Phase(
          type: .scoreCalc, logic: .pairwisePayoff,
          payoff: [PayoffRule(when: ["yes", "no"], points: [1, 1])])
      ])
    let findings = linter.lint(scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "pairwise-payoff-no-scorable-row")
    #expect(findings.first?.severity == .error)
    #expect(findings.first?.phaseIndex == 1)
  }

  @Test func absentPayoffWithValidChooseFiresError() {
    // A properly-wired pairwise_payoff with no `payoff:` table → guaranteed no-op.
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [roundRobinChoose(), Phase(type: .scoreCalc, logic: .pairwisePayoff)])
    let findings = linter.lint(scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "pairwise-payoff-no-scorable-row")
    #expect(findings.first?.severity == .error)
  }

  // MARK: - R20b pairwise-payoff-dead-row (warning)

  @Test func payoffSomeRowsDeadFiresWarning() {
    // One satisfiable row + one dead row (`unclear` isn't an option) → the phase
    // still scores, so a warning, not an error.
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        roundRobinChoose(),
        Phase(
          type: .scoreCalc, logic: .pairwisePayoff,
          payoff: [
            PayoffRule(when: ["cooperate", "cooperate"], points: [3, 3]),
            PayoffRule(when: ["unclear", "unclear"], points: [0, 0])
          ])
      ])
    let findings = linter.lint(scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "pairwise-payoff-dead-row")
    #expect(findings.first?.severity == .warning)
    #expect(findings.first?.phaseIndex == 1)
  }

  // MARK: - Passes

  @Test func payoffAllRowsSatisfiablePasses() {
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        roundRobinChoose(),
        Phase(type: .scoreCalc, logic: .pairwisePayoff, payoff: satisfiablePayoff)
      ])
    #expect(linter.lint(scenario).isEmpty)
  }

  // MARK: - R20 defers to R19 / R7 (no double-report)

  @Test func payoffWithoutRoundRobinChooseDefersToR19() {
    // Individual (non-round-robin) choose → R19 owns the empty-pairings case;
    // R20 must not also fire (no closed option set for the pairings).
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        Phase(type: .choose, options: ["cooperate", "betray"]),
        Phase(type: .scoreCalc, logic: .pairwisePayoff, payoff: satisfiablePayoff)
      ])
    let findings = linter.lint(scenario)
    #expect(findings.contains { $0.ruleID == "pairwise-payoff-needs-round-robin-choose" })
    #expect(!findings.contains { $0.ruleID == "pairwise-payoff-no-scorable-row" })
    #expect(!findings.contains { $0.ruleID == "pairwise-payoff-dead-row" })
  }

  @Test func payoffWithOptionlessRoundRobinChooseDefersToR7() {
    // A round-robin choose with no options → R7 owns the missing-options case;
    // R20 has no set to check against and must not fire.
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        Phase(type: .choose, pairing: .roundRobin),
        Phase(type: .scoreCalc, logic: .pairwisePayoff, payoff: satisfiablePayoff)
      ])
    let findings = linter.lint(scenario)
    #expect(findings.contains { $0.ruleID == "choose-should-declare-options" })
    #expect(!findings.contains { $0.ruleID == "pairwise-payoff-no-scorable-row" })
    #expect(!findings.contains { $0.ruleID == "pairwise-payoff-dead-row" })
  }
}
