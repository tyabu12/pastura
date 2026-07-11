import Foundation
import Testing

@testable import Pastura

// MARK: - Per-phase max_sentences override (#881)
//
// Sibling-file extension per the testing.md split convention — NOT a new
// @Suite (helpers `builder` / `makeScenario` stay internal in the main file).
// The default (no override) byte-identity is pinned by the #877 brevity tests
// in PromptBuilderTests+Hardening.swift; these cover the override paths.
extension PromptBuilderTests {

  private func promptFor(maxSentences: Int?, language: String = "ja") -> String {
    let scenario = makeScenario(language: language)
    let phase = Phase(
      type: .speakAll, prompt: "Speak!",
      outputSchema: ["statement": "string"], maxSentences: maxSentences)
    let state = SimulationState.initial(for: scenario)
    return builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: phase, state: state)
  }

  @Test func maxSentencesOverrideReplacesCapJa() {
    let prompt = promptFor(maxSentences: 6)
    #expect(prompt.contains("6文以内で簡潔に"))
    // REPLACE, not append — the default 3-cap must not survive alongside it.
    #expect(!prompt.contains("3文以内"))
  }

  @Test func maxSentencesOverrideReplacesCapEn() {
    let prompt = promptFor(maxSentences: 6, language: "en")
    #expect(prompt.contains("at most 6 sentences"))
    #expect(!prompt.contains("at most 3 sentences"))
  }

  /// N=1 pluralizes correctly in en ("1 sentence", not "1 sentences") and
  /// reads naturally in ja ("1文以内").
  @Test func maxSentencesOfOneUsesSingularNounEn() {
    let prompt = promptFor(maxSentences: 1, language: "en")
    #expect(prompt.contains("at most 1 sentence,"))
    #expect(!prompt.contains("1 sentences"))
  }

  @Test func maxSentencesOfOneRendersJa() {
    #expect(promptFor(maxSentences: 1).contains("1文以内で簡潔に"))
  }

  /// Absent override falls back to the global default (byte-identical to the
  /// #877 wording — the Hardening suite pins the exact literal).
  @Test func absentMaxSentencesUsesDefaultCap() {
    #expect(promptFor(maxSentences: nil).contains("3文以内で簡潔に"))
  }
}
