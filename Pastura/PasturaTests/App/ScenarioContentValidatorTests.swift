import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ScenarioContentValidatorTests {
  private func makeScenario(
    name: String = "ok",
    description: String = "ok",
    personas: [Persona] = [Persona(name: "Alice", description: "ok")],
    phases: [Phase] = []
  ) -> Scenario {
    Scenario(
      id: "test",
      name: name,
      description: description,
      agentCount: personas.count,
      rounds: 1,
      context: "",
      personas: personas,
      phases: phases
    )
  }

  // MARK: - Baseline

  @Test func cleanScenarioProducesNoFindings() {
    let validator = ScenarioContentValidator(blockedPatterns: ["forbidden"])
    #expect(validator.validate(makeScenario()).isEmpty)
  }

  @Test func emptyBlocklistNeverProducesFindings() {
    let validator = ScenarioContentValidator(blockedPatterns: [])
    let scenario = makeScenario(
      name: "killer",
      description: "殺す fuck",
      personas: [Persona(name: "bad", description: "also bad")],
      phases: [Phase(type: .speakAll, prompt: "bad things")]
    )
    #expect(validator.validate(scenario).isEmpty)
  }

  // MARK: - Scenario-level fields

  @Test func scenarioNameBlockedTermDetected() {
    let validator = ScenarioContentValidator(blockedPatterns: ["forbidden"])
    let findings = validator.validate(makeScenario(name: "totally forbidden"))
    #expect(findings.count == 1)
    #expect(findings[0].contains("Scenario name"))
  }

  @Test func scenarioDescriptionBlockedTermDetected() {
    let validator = ScenarioContentValidator(blockedPatterns: ["forbidden"])
    let findings = validator.validate(makeScenario(description: "very forbidden"))
    #expect(findings.count == 1)
    #expect(findings[0].contains("Scenario description"))
  }

  // MARK: - Persona fields

  @Test func personaNameBlockedTermDetectedWithoutEchoingMatch() {
    let validator = ScenarioContentValidator(blockedPatterns: ["forbiddenname"])
    let findings = validator.validate(
      makeScenario(personas: [Persona(name: "forbiddenname", description: "ok")])
    )
    #expect(findings.count == 1)
    #expect(findings[0].contains("Persona 1 name"))
    #expect(!findings[0].contains("forbiddenname"))
  }

  @Test func personaDescriptionUsesNameWhenNameIsClean() {
    let validator = ScenarioContentValidator(blockedPatterns: ["forbidden"])
    let findings = validator.validate(
      makeScenario(personas: [Persona(name: "Alice", description: "forbidden vibes")])
    )
    #expect(findings.count == 1)
    #expect(findings[0].contains("Alice"))
    #expect(findings[0].contains("description"))
  }

  @Test func personaDescriptionFallsBackToPositionWhenNameAlsoMatches() {
    let validator = ScenarioContentValidator(blockedPatterns: ["forbidden"])
    let findings = validator.validate(
      makeScenario(personas: [Persona(name: "forbidden", description: "also forbidden")])
    )
    // Two findings — one for name, one for description
    #expect(findings.count == 2)
    for message in findings {
      #expect(!message.contains("forbidden"), "Finding leaked matched term: '\(message)'")
    }
  }

  // MARK: - Phase fields

  @Test func phasePromptBlockedTermDetected() {
    let validator = ScenarioContentValidator(blockedPatterns: ["forbidden"])
    let phase = Phase(type: .speakAll, prompt: "do forbidden things")
    let findings = validator.validate(makeScenario(phases: [phase]))
    #expect(findings.count == 1)
    #expect(findings[0].contains("Phase 1"))
    #expect(findings[0].contains("prompt"))
  }

  @Test func phaseTemplateBlockedTermDetected() {
    let validator = ScenarioContentValidator(blockedPatterns: ["forbidden"])
    let phase = Phase(type: .summarize, template: "summary: forbidden content")
    let findings = validator.validate(makeScenario(phases: [phase]))
    #expect(findings.count == 1)
    #expect(findings[0].contains("template"))
  }

  @Test func phaseConditionBlockedTermDetected() {
    let validator = ScenarioContentValidator(blockedPatterns: ["forbidden"])
    let phase = Phase(type: .conditional, condition: "score.forbidden == 1")
    let findings = validator.validate(makeScenario(phases: [phase]))
    #expect(findings.count == 1)
    #expect(findings[0].contains("condition"))
  }

  // MARK: - Conditional sub-phase recursion (ADR-005 §4.3)

  @Test func conditionalSubPhaseThenBranchDetected() {
    let validator = ScenarioContentValidator(blockedPatterns: ["forbidden"])
    let subPhase = Phase(type: .speakAll, prompt: "do forbidden things")
    let outer = Phase(
      type: .conditional,
      condition: "cleanCondition",
      thenPhases: [subPhase]
    )
    let findings = validator.validate(makeScenario(phases: [outer]))
    #expect(findings.count == 1)
    #expect(findings[0].contains("Phase 1.then.1"))
    #expect(findings[0].contains("prompt"))
  }

  @Test func conditionalSubPhaseElseBranchDetected() {
    let validator = ScenarioContentValidator(blockedPatterns: ["forbidden"])
    let subPhase = Phase(type: .speakAll, prompt: "do forbidden things")
    let outer = Phase(
      type: .conditional,
      condition: "cleanCondition",
      elsePhases: [subPhase]
    )
    let findings = validator.validate(makeScenario(phases: [outer]))
    #expect(findings.count == 1)
    #expect(findings[0].contains("Phase 1.else.1"))
  }

  @Test func conditionalBothBranchesDetectedIndependently() {
    let validator = ScenarioContentValidator(blockedPatterns: ["forbidden"])
    let outer = Phase(
      type: .conditional,
      condition: "cleanCondition",
      thenPhases: [Phase(type: .speakAll, prompt: "forbidden then")],
      elsePhases: [Phase(type: .speakAll, prompt: "forbidden else")]
    )
    let findings = validator.validate(makeScenario(phases: [outer]))
    #expect(findings.count == 2)
    #expect(findings.contains { $0.contains("then.1") })
    #expect(findings.contains { $0.contains("else.1") })
  }

  @Test func conditionalSubPhaseTemplateAndConditionAlsoWalked() {
    let validator = ScenarioContentValidator(blockedPatterns: ["forbidden"])
    let outer = Phase(
      type: .conditional,
      condition: "cleanCondition",
      thenPhases: [
        Phase(type: .summarize, template: "forbidden template"),
        Phase(type: .conditional, condition: "forbidden condition")
      ]
    )
    let findings = validator.validate(makeScenario(phases: [outer]))
    #expect(findings.count == 2)
    #expect(findings.contains { $0.contains("Phase 1.then.1") && $0.contains("template") })
    #expect(findings.contains { $0.contains("Phase 1.then.2") && $0.contains("condition") })
  }

  // MARK: - Matching semantics

  @Test func caseInsensitiveMatching() {
    let validator = ScenarioContentValidator(blockedPatterns: ["forbidden"])
    let findings = validator.validate(makeScenario(name: "TOTALLY FORBIDDEN"))
    #expect(findings.count == 1)
  }

  @Test func diacriticInsensitiveMatching() {
    let validator = ScenarioContentValidator(blockedPatterns: ["café"])
    let findings = validator.validate(makeScenario(name: "I like CAFE"))
    #expect(findings.count == 1)
  }

  @Test func diacriticInsensitiveMatchingReverseDirection() {
    // Symmetric case: blocklist pattern without diacritics, input with them.
    // The bundled .txt may or may not be NFC-normalised and user input is
    // independent of that — matching must fold both directions.
    let validator = ScenarioContentValidator(blockedPatterns: ["naive"])
    let findings = validator.validate(makeScenario(name: "How NAÏVE"))
    #expect(findings.count == 1)
  }

  // MARK: - Invariant: no matched-term echo

  @Test func findingsNeverEchoTheMatchedPattern() {
    let badWord = "forbiddenword"
    let validator = ScenarioContentValidator(blockedPatterns: [badWord])
    let scenario = makeScenario(
      name: "a forbiddenword is here",
      description: "forbiddenword in description",
      personas: [Persona(name: "Alice", description: "with forbiddenword inside")],
      phases: [
        Phase(type: .speakAll, prompt: "says forbiddenword"),
        Phase(
          type: .conditional,
          condition: "cleanCondition",
          thenPhases: [Phase(type: .speakAll, prompt: "nested forbiddenword")]
        )
      ]
    )
    let findings = validator.validate(scenario)
    #expect(!findings.isEmpty)
    for finding in findings {
      #expect(
        !finding.contains(badWord),
        "Finding leaked matched term: '\(finding)'"
      )
    }
  }
}
