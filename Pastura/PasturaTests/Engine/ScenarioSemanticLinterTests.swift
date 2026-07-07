// One @Test per lint rule (added by later plan items) keeps the
// finding-mode mapping legible. This file starts with the core-type
// contract (skeleton) — rule-specific tests land as R1–R17 are filled in.
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct ScenarioSemanticLinterTests {
  let linter = ScenarioSemanticLinter()

  // MARK: - Core contract

  @Test func minimalValidScenarioHasNoFindings() {
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [Phase(type: .speakAll)])
    #expect(linter.lint(scenario).isEmpty)
  }

  @Test func findingEqualityHoldsForIdenticalFields() {
    let lhs = LintFinding(
      ruleID: "example-rule", severity: .warning, message: "msg", phaseIndex: 2)
    let rhs = LintFinding(
      ruleID: "example-rule", severity: .warning, message: "msg", phaseIndex: 2)
    #expect(lhs == rhs)
  }

  @Test func findingEqualityDistinguishesEachField() {
    let base = LintFinding(
      ruleID: "example-rule", severity: .warning, message: "msg", phaseIndex: 2)
    #expect(
      base
        != LintFinding(
          ruleID: "other-rule", severity: .warning, message: "msg", phaseIndex: 2))
    #expect(
      base
        != LintFinding(
          ruleID: "example-rule", severity: .error, message: "msg", phaseIndex: 2))
    #expect(
      base
        != LintFinding(
          ruleID: "example-rule", severity: .warning, message: "other", phaseIndex: 2))
    #expect(
      base
        != LintFinding(
          ruleID: "example-rule", severity: .warning, message: "msg", phaseIndex: nil))
  }

  @Test func scenarioLevelFindingUsesNilPhaseIndex() {
    let finding = LintFinding(
      ruleID: "scenario-rule", severity: .info, message: "msg", phaseIndex: nil)
    #expect(finding.phaseIndex == nil)
  }

  // MARK: - Severity

  @Test func severityCasesAreDistinct() {
    #expect(LintSeverity.error != LintSeverity.warning)
    #expect(LintSeverity.warning != LintSeverity.info)
    #expect(LintSeverity.error != LintSeverity.info)
  }

  @Test func severityOrdersErrorAboveWarningAboveInfo() {
    // Comparable is by blocking-strength: error is the most severe.
    #expect(LintSeverity.info < LintSeverity.warning)
    #expect(LintSeverity.warning < LintSeverity.error)
    #expect(LintSeverity.info < LintSeverity.error)
  }

  // MARK: - Helpers

  // Internal (not private) so later sibling-file extensions can build the
  // many phase-list permutations rule tests need from one factory.
  func makeScenario(agents: Int, rounds: Int, phases: [Phase]) -> Scenario {
    Scenario(
      id: "test", name: "Test", description: "Test",
      language: "ja",
      agentCount: agents, rounds: rounds, context: "Context",
      personas: (0..<agents).map { Persona(name: "A\($0)", description: "D") },
      phases: phases
    )
  }
}
