import Testing

@testable import Pastura

/// Guards that the copyable "Copy Gen Prompt" text stays in sync with the
/// canonical DSL enums. The no-default switches in `ScenarioGenerationPrompt`
/// already force a new arm per case at compile time; these tests additionally
/// assert each `rawValue` and canonical field name actually reaches the emitted
/// string, so a future edit that drops a `rawValue` from a generated line is
/// caught (ADR-022 projection). Web `format.md` coverage is gated separately by
/// a CI grep.
@Suite(.timeLimit(.minutes(1)))
struct ScenarioGenerationPromptTests {

  @Test func mentionsEveryPhaseType() {
    let text = ScenarioGenerationPrompt.text
    for phase in PhaseType.allCases {
      #expect(text.contains(phase.rawValue), "gen prompt is missing phase type \(phase.rawValue)")
    }
  }

  @Test func mentionsEveryScoreCalcLogic() {
    let text = ScenarioGenerationPrompt.text
    for logic in ScoreCalcLogic.allCases {
      #expect(
        text.contains(logic.rawValue), "gen prompt is missing score_calc logic \(logic.rawValue)")
    }
  }

  @Test func mentionsCanonicalPrimaryFields() {
    let text = ScenarioGenerationPrompt.text
    for phase in PhaseType.allCases {
      guard let primary = ScenarioConventions.primaryField(for: phase) else { continue }
      #expect(
        text.contains(primary),
        "gen prompt is missing canonical primary field \(primary) for \(phase.rawValue)")
    }
  }

  @Test func mentionsCanonicalThoughtFields() {
    let text = ScenarioGenerationPrompt.text
    for phase in PhaseType.allCases {
      guard let thought = ScenarioConventions.thoughtField(for: phase) else { continue }
      #expect(
        text.contains(thought),
        "gen prompt is missing canonical thought field \(thought) for \(phase.rawValue)")
    }
  }

  @Test func referencesFullFormatSpec() {
    #expect(ScenarioGenerationPrompt.text.contains("pastura.app/docs/scenario/format.md"))
  }

  @Test func isNotEmpty() {
    #expect(!ScenarioGenerationPrompt.text.isEmpty)
  }
}
