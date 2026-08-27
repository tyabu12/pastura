// The Placeholder group's ruleID → ScenarioLintMessage pin (ADR-024 D3).
// Split into its own file for the same three SwiftLint reasons as
// ScenarioSemanticLinterTests+OrderingMessages.swift and
// +ConfigMessages.swift (file_length, function_body_length, large_tuple);
// still an extension of the existing suite (not a new @Suite) per
// .claude/rules/testing.md.
import Testing

@testable import Pastura

extension ScenarioSemanticLinterTests {

  /// One row of ``placeholderMessagesMapEachRuleIDToItsLintMessageCase``'s
  /// pin: a fixture expected to fire exactly `ruleID`, and the message it
  /// must render. A struct rather than a tuple — SwiftLint caps tuples at two
  /// members.
  private struct PlaceholderMessageCase {
    let ruleID: String
    let scenario: Scenario
    let expected: ScenarioLintMessage
  }

  /// R10/R11/R12 — the three placeholder rules, one offending token each.
  private var placeholderMessageCases: [PlaceholderMessageCase] {
    [
      PlaceholderMessageCase(
        ruleID: "unresolvable-placeholder",
        scenario: makeScenario(
          agents: 2, rounds: 1,
          phases: [Phase(type: .speakAll, prompt: "Scores: {scorebord}")]),
        expected: .unresolvablePlaceholder(token: "scorebord")),
      PlaceholderMessageCase(
        ruleID: "placeholder-phase-availability",
        scenario: makeScenario(
          agents: 2, rounds: 1,
          phases: [
            Phase(type: .speakAll, prompt: "The wolf is {wolf_name}"),
            Phase(type: .assign, target: .randomOne)
          ]),
        expected: .placeholderPhaseAvailability(token: "wolf_name")),
      PlaceholderMessageCase(
        ruleID: "per-persona-placeholder-in-summarize",
        scenario: makeScenario(
          agents: 2, rounds: 1,
          phases: [Phase(type: .summarize, template: "Your notes: {my_notes}")]),
        expected: .perPersonaPlaceholderInSummarize(token: "my_notes"))
    ]
  }

  // MARK: - Message mapping (deliberate exception to the one-test-per-rule shape)

  /// The Placeholder-group twin of
  /// ``orderingMessagesMapEachRuleIDToItsLintMessageCase`` /
  /// ``configMessagesMapEachRuleIDToItsLintMessageCase``: no other test in
  /// this suite asserts `finding.message` for a placeholder rule, so a
  /// mis-transcribed arm in the private `placeholderMessage(_:token:)` — a
  /// string switch with a `default:` fallthrough for
  /// `per-persona-placeholder-in-summarize` — would ship green with nothing
  /// to catch it. Each row fires exactly one placeholder rule and pins its
  /// rendered message, token interpolation included; `count == 1` and the
  /// `ruleID` are pinned too, so a rule that starts firing first on one of
  /// these fixtures cannot silently change what is measured. Mirrors
  /// `ScenarioSemanticLinterPlaceholdersTests.placeholderMessagesMapEachRuleIdToItsLintMessageCase`.
  ///
  /// Limit, stated so nobody reads it as a proof: the 3-entry list is a
  /// hand-maintained pin — a fourth placeholder rule must be added here by
  /// hand, nothing reddens otherwise.
  @Test func placeholderMessagesMapEachRuleIDToItsLintMessageCase() {
    let cases = placeholderMessageCases
    // Pin, not proof: a new placeholder rule must be added to `cases` by hand.
    #expect(cases.count == 3)
    for testCase in cases {
      let findings = linter.lint(testCase.scenario)
      #expect(findings.count == 1, "\(testCase.ruleID)")
      #expect(findings.first?.ruleID == testCase.ruleID, "\(testCase.ruleID)")
      #expect(findings.first?.message == testCase.expected.localized, "\(testCase.ruleID)")
    }
  }
}
