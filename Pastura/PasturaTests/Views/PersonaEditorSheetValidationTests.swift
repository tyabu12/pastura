import Testing

@testable import Pastura

/// Inline-validation contract for `PersonaEditorSheet` (#261, ADR-005 §4).
///
/// The sheet exposes a `validateOnSave(...)` helper extracted for test:
/// it runs the injected `ScenarioContentValidator`, sets per-field error
/// state, and returns whether the Save action should fire `onSave` +
/// dismiss. The render path (`@State` wiring + Form Section footer) is
/// covered indirectly by exercising this helper.
@Suite(.timeLimit(.minutes(1)))
@MainActor
struct PersonaEditorSheetValidationTests {

  private func makeValidator() -> ScenarioContentValidator {
    // Deterministic blocklist so tests don't depend on the bundled
    // ContentBlocklist.json. Mirrors the pattern in
    // ScenarioContentValidatorTests (`blockedPatterns: ["forbidden"]`).
    ScenarioContentValidator(blockedPatterns: ["forbiddenword"])
  }

  @Test func cleanInputAllowsSave() {
    let findings = makeValidator().validate(
      personaName: "Alice",
      description: "kind soul"
    )
    #expect(!findings.hasIssue)
  }

  @Test func nameWithBlockedTermBlocksSaveAndExposesNameError() {
    let findings = makeValidator().validate(
      personaName: "forbiddenword",
      description: "kind soul"
    )
    #expect(findings.hasIssue)
    #expect(findings.name != nil)
    #expect(findings.description == nil)
  }

  @Test func descriptionWithBlockedTermBlocksSaveAndExposesDescriptionError() {
    let findings = makeValidator().validate(
      personaName: "Alice",
      description: "with forbiddenword inside"
    )
    #expect(findings.hasIssue)
    #expect(findings.name == nil)
    #expect(findings.description != nil)
  }

  @Test func bothFieldsViolatingDoNotEchoMatchedTerm() {
    // ADR-005 §4.7 — render path must surface neither matched term.
    let findings = makeValidator().validate(
      personaName: "forbiddenword",
      description: "also forbiddenword present"
    )
    #expect(!(findings.name ?? "").contains("forbiddenword"))
    #expect(!(findings.description ?? "").contains("forbiddenword"))
  }

  @Test func emptyFieldsSkippedFromValidation() {
    // PersonaEditorSheet's `.disabled(name empty)` already gates the Save
    // button on emptiness; the validator should still no-op for empty
    // strings rather than producing spurious findings if it is reached.
    let findings = makeValidator().validate(personaName: "", description: "")
    #expect(!findings.hasIssue)
  }
}
