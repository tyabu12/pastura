import Foundation
import Testing

@testable import Pastura

// Per-field API tests for inline editor sheets (#261). Sibling extension
// of the original suite per testing.md's split convention — keeps the
// suite struct under swiftlint's `type_body_length` cap (250 lines)
// while inheriting `.timeLimit(.minutes(1))` and `@MainActor` from the
// primary `@Suite` declaration.
extension ScenarioContentValidatorTests {

  @Test func personaPerFieldCleanProducesNoFindings() {
    let validator = ScenarioContentValidator(blockedPatterns: ["forbidden"])
    let findings = validator.validate(personaName: "Alice", description: "kind soul")
    #expect(!findings.hasIssue)
    #expect(findings.name == nil)
    #expect(findings.description == nil)
  }

  @Test func personaPerFieldEmptyStringsAreSkipped() {
    // Mirrors the empty→nil convention authors see in the engine; avoids
    // surfacing errors for fields the user never typed in.
    let validator = ScenarioContentValidator(blockedPatterns: ["forbidden"])
    let findings = validator.validate(personaName: "", description: "")
    #expect(!findings.hasIssue)
  }

  @Test func personaPerFieldNameOnlyBlocked() {
    let validator = ScenarioContentValidator(blockedPatterns: ["forbiddenword"])
    let findings = validator.validate(
      personaName: "forbiddenword",
      description: "kind soul"
    )
    #expect(findings.hasIssue)
    #expect(findings.name != nil)
    #expect(findings.description == nil)
    #expect(!(findings.name ?? "").contains("forbiddenword"))
  }

  @Test func personaPerFieldDescriptionOnlyBlocked() {
    let validator = ScenarioContentValidator(blockedPatterns: ["forbiddenword"])
    let findings = validator.validate(
      personaName: "Alice",
      description: "forbiddenword vibes"
    )
    #expect(findings.hasIssue)
    #expect(findings.name == nil)
    #expect(findings.description != nil)
    #expect(!(findings.description ?? "").contains("forbiddenword"))
  }

  @Test func personaPerFieldBothBlockedNeitherEchoesMatchedTerm() {
    // ADR-005 §4.7 — when both fields contain the blocked term, the
    // per-field messages must remain context-free. Sibling-field
    // interpolation would leak the term via the description message.
    let validator = ScenarioContentValidator(blockedPatterns: ["forbiddenword"])
    let findings = validator.validate(
      personaName: "forbiddenword",
      description: "also forbiddenword here"
    )
    #expect(findings.name != nil)
    #expect(findings.description != nil)
    #expect(!(findings.name ?? "").contains("forbiddenword"))
    #expect(!(findings.description ?? "").contains("forbiddenword"))
  }

  @Test func phasePerFieldCleanProducesNoFindings() {
    let validator = ScenarioContentValidator(blockedPatterns: ["forbidden"])
    let findings = validator.validate(
      phasePrompt: "do good",
      template: "summary",
      condition: "x == 1"
    )
    #expect(!findings.hasIssue)
  }

  @Test func phasePerFieldEmptyStringsAreSkipped() {
    let validator = ScenarioContentValidator(blockedPatterns: ["forbidden"])
    let findings = validator.validate(phasePrompt: "", template: "", condition: "")
    #expect(!findings.hasIssue)
  }

  @Test func phasePerFieldPromptOnlyBlocked() {
    let validator = ScenarioContentValidator(blockedPatterns: ["forbiddenword"])
    let findings = validator.validate(
      phasePrompt: "do forbiddenword things",
      template: "",
      condition: ""
    )
    #expect(findings.prompt != nil)
    #expect(findings.template == nil)
    #expect(findings.condition == nil)
    #expect(!(findings.prompt ?? "").contains("forbiddenword"))
  }

  @Test func phasePerFieldTemplateOnlyBlocked() {
    let validator = ScenarioContentValidator(blockedPatterns: ["forbiddenword"])
    let findings = validator.validate(
      phasePrompt: "",
      template: "summary: forbiddenword bits",
      condition: ""
    )
    #expect(findings.template != nil)
    #expect(findings.prompt == nil)
    #expect(findings.condition == nil)
  }

  @Test func phasePerFieldConditionOnlyBlocked() {
    let validator = ScenarioContentValidator(blockedPatterns: ["forbiddenword"])
    let findings = validator.validate(
      phasePrompt: "",
      template: "",
      condition: "score.forbiddenword == 1"
    )
    #expect(findings.condition != nil)
    #expect(findings.prompt == nil)
    #expect(findings.template == nil)
  }

  @Test func phasePerFieldAllBlockedNoneEchoMatchedTerm() {
    // ADR-005 §4.7 across all three phase content fields.
    let validator = ScenarioContentValidator(blockedPatterns: ["forbiddenword"])
    let findings = validator.validate(
      phasePrompt: "forbiddenword",
      template: "forbiddenword",
      condition: "forbiddenword"
    )
    #expect(findings.prompt != nil)
    #expect(findings.template != nil)
    #expect(findings.condition != nil)
    #expect(!(findings.prompt ?? "").contains("forbiddenword"))
    #expect(!(findings.template ?? "").contains("forbiddenword"))
    #expect(!(findings.condition ?? "").contains("forbiddenword"))
  }
}
