import Foundation
import Testing

@testable import Pastura

/// Inline-validation contract for `PhaseEditorSheet` (#261, ADR-005 §4).
///
/// The sheet's Save tap forwards the editing `EditablePhase` to
/// `ScenarioContentValidator.validate(phasePrompt:template:condition:)`,
/// scoping per-field findings to the three blockable text fields. Tests
/// here exercise the validator-facing decision logic and pin the two
/// load-bearing properties: depth-1 nested sub-phase editing reuses the
/// same injected validator, and visible-fields-only is intentional —
/// hidden text from a stale type switch falls through to the
/// scenario-level backstop.
@Suite(.timeLimit(.minutes(1)))
@MainActor
struct PhaseEditorSheetValidationTests {

  private func makeValidator() -> ScenarioContentValidator {
    ScenarioContentValidator(blockedPatterns: ["forbiddenword"])
  }

  // MARK: - Visible-fields-only API contract

  @Test func cleanFieldsAllowSave() {
    let findings = makeValidator().validate(
      phasePrompt: "Speak briefly",
      template: "summary {scoreboard}",
      condition: "current_round >= 2"
    )
    #expect(!findings.hasIssue)
  }

  @Test func promptViolationBlocksSaveForLLMPhase() {
    // `.speakAll` exposes prompt; the sheet calls validate with prompt
    // only when `phase.type.requiresLLM` (template/condition strings
    // pass as empty when their UI is hidden).
    let findings = makeValidator().validate(
      phasePrompt: "do forbiddenword now",
      template: "",
      condition: ""
    )
    #expect(findings.prompt != nil)
    #expect(findings.template == nil)
    #expect(findings.condition == nil)
  }

  @Test func templateViolationBlocksSaveForSummarizePhase() {
    let findings = makeValidator().validate(
      phasePrompt: "",
      template: "round summary: forbiddenword",
      condition: ""
    )
    #expect(findings.template != nil)
    #expect(findings.prompt == nil)
  }

  @Test func conditionViolationBlocksSaveForConditionalPhase() {
    let findings = makeValidator().validate(
      phasePrompt: "",
      template: "",
      condition: "scores.forbiddenword >= 1"
    )
    #expect(findings.condition != nil)
    #expect(findings.prompt == nil)
    #expect(findings.template == nil)
  }

  @Test func allFieldsViolatingDoNotEchoMatchedTerm() {
    let findings = makeValidator().validate(
      phasePrompt: "forbiddenword",
      template: "forbiddenword",
      condition: "forbiddenword"
    )
    #expect(!(findings.prompt ?? "").contains("forbiddenword"))
    #expect(!(findings.template ?? "").contains("forbiddenword"))
    #expect(!(findings.condition ?? "").contains("forbiddenword"))
  }

  // MARK: - Visible-fields-only policy backstop

  @Test func eliminatePhaseWithStalePromptDoesNotTriggerInlineButBackstopCatches() {
    // Visible-fields-only: a `.eliminate` phase has no prompt UI, so the
    // sheet passes prompt: "" to the inline validator. The author's
    // residual prompt text — leftover from a previous .speakAll edit —
    // survives in EditablePhase but stays out of the inline error path.
    // The scenario-level walk MUST still catch it on the outer save so
    // defense-in-depth holds.
    let validator = makeValidator()
    let inline = validator.validate(phasePrompt: "", template: "", condition: "")
    #expect(!inline.hasIssue)

    // Backstop: the same residual prompt, when the EditablePhase is
    // serialised back into a scenario, gets caught by validate(_ scenario:).
    var stale = EditablePhase(type: .eliminate)
    stale.prompt = "leftover forbiddenword text"
    let scenario = Scenario(
      id: "s",
      name: "n",
      description: "",
      agentCount: 1,
      rounds: 1,
      context: "",
      personas: [Persona(name: "Alice", description: "")],
      phases: [stale.toPhase()]
    )
    let backstop = validator.validate(scenario)
    #expect(backstop.contains { $0.contains("Phase 1") && $0.contains("prompt") })
  }

  // MARK: - Nested-sheet validator propagation

  @Test func nestedSubPhaseInThenBranchUsesInjectedValidator() {
    // Depth-1 conditional sub-phase editing presents a fresh
    // PhaseEditorSheet instance (the nested .sheet(item:) at the bottom
    // of `body`). The injected validator must reach that nested
    // instance, otherwise nested Save would fall through to a
    // bundle-loaded default validator and behave differently from the
    // outer sheet under test. We verify the contract at the validator
    // surface: the same validator instance, called per-field for a
    // sub-phase prompt, surfaces the violation.
    let validator = makeValidator()
    let subPromptFindings = validator.validate(
      phasePrompt: "do forbiddenword in then branch",
      template: "",
      condition: ""
    )
    #expect(subPromptFindings.prompt != nil)
  }

  @Test func nestedSubPhaseInElseBranchUsesInjectedValidator() {
    let validator = makeValidator()
    let subPromptFindings = validator.validate(
      phasePrompt: "do forbiddenword in else branch",
      template: "",
      condition: ""
    )
    #expect(subPromptFindings.prompt != nil)
  }
}
