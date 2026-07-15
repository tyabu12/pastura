import Foundation
import Testing

@testable import Pastura

// MARK: - Mood output-field injection / capture (#913)
//
// Sibling-file extension per the testing.md split convention — NOT a new
// @Suite (a second suite would run in parallel against the same shared state
// class; see PR #157). Helpers (`builder`, `makeScenario`) stay at internal
// access in PromptBuilderTests.swift so this file can see them.
extension PromptBuilderTests {

  private func moodSpeakPhase() -> Phase {
    Phase(
      type: .speakAll, prompt: "Speak!",
      outputSchema: ["statement": "string", "mood": "string"])
  }

  // MARK: - injectMood

  @Test func injectMoodSetsMyMoodFromNamespacedKey() {
    var variables = ["mood_Alice": "苛立ち"]
    builder.injectMood(into: &variables, personaName: "Alice")
    #expect(variables["my_mood"] == "苛立ち")
  }

  @Test func injectMoodSetsEmptyStringOnMiss() {
    var variables: [String: String] = [:]
    builder.injectMood(into: &variables, personaName: "Alice")
    #expect(variables["my_mood"] == "")
  }

  // MARK: - captureMood

  @Test func captureMoodPersistsNonEmptyMood() {
    var variables: [String: String] = [:]
    let output = TurnOutput(fields: ["statement": "hi", "mood": "わくわく"])
    builder.captureMood(from: output, into: &variables, personaName: "Alice")
    #expect(variables["mood_Alice"] == "わくわく")
  }

  // A failed/empty inference must NOT erase the prior mood — the non-empty
  // guard mirrors ReflectHandler's note save.
  @Test func captureMoodEmptyDoesNotErasePrior() {
    var variables = ["mood_Alice": "不安"]
    let emptyOutput = TurnOutput(fields: ["statement": "hi", "mood": ""])
    builder.captureMood(from: emptyOutput, into: &variables, personaName: "Alice")
    #expect(variables["mood_Alice"] == "不安")
  }

  // A phase that never declares mood produces no key → no-op capture.
  @Test func captureMoodNoOpWhenAbsent() {
    var variables: [String: String] = [:]
    let output = TurnOutput(fields: ["statement": "hi"])
    builder.captureMood(from: output, into: &variables, personaName: "Alice")
    #expect(variables["mood_Alice"] == nil)
  }

  // MARK: - System-prompt mood section

  @Test func systemPromptContainsMoodSectionWhenSet() {
    let scenario = makeScenario()
    var state = SimulationState.initial(for: scenario)
    state.variables["mood_Alice"] = "MOOD_SENTINEL"

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0],
      phase: moodSpeakPhase(), state: state)
    #expect(prompt.contains("あなたの今の気分"))
    #expect(prompt.contains("MOOD_SENTINEL"))
  }

  @Test func systemPromptOmitsMoodSectionWhenUnset() {
    let scenario = makeScenario()
    let state = SimulationState.initial(for: scenario)

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0],
      phase: moodSpeakPhase(), state: state)
    #expect(!prompt.contains("あなたの今の気分"))
  }

  @Test func systemPromptMoodSectionEnHeader() {
    let scenario = makeScenario(language: "en")
    var state = SimulationState.initial(for: scenario)
    state.variables["mood_Alice"] = "MOOD_SENTINEL"

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0],
      phase: moodSpeakPhase(), state: state)
    #expect(prompt.contains("Your Current Mood"))
    #expect(prompt.contains("MOOD_SENTINEL"))
  }

  // Mood inertia must survive an intervening non-declaring phase: the mood
  // section surfaces even when the current phase does not declare `mood`.
  @Test func systemPromptMoodSurfacesInNonDeclaringPhase() {
    let scenario = makeScenario()
    var state = SimulationState.initial(for: scenario)
    state.variables["mood_Alice"] = "MOOD_SENTINEL"
    let votePhase = Phase(type: .vote, prompt: "Vote!", outputSchema: ["vote": "string"])

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: votePhase, state: state)
    #expect(prompt.contains("MOOD_SENTINEL"))
  }

  // Mood coexists with the reflect-note section (both surface together).
  @Test func systemPromptMoodCoexistsWithNotes() {
    let scenario = makeScenario()
    var state = SimulationState.initial(for: scenario)
    state.variables["mood_Alice"] = "MOOD_SENTINEL"
    state.variables["notes_Alice"] = "NOTE_SENTINEL"

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0],
      phase: moodSpeakPhase(), state: state)
    #expect(prompt.contains("MOOD_SENTINEL"))
    #expect(prompt.contains("NOTE_SENTINEL"))
  }

  // MARK: - Mood answer-rule guidance (declaring phases only)

  @Test func moodAnswerRuleAppendedForDeclaringPhaseJa() {
    let scenario = makeScenario()
    let state = SimulationState.initial(for: scenario)
    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0],
      phase: moodSpeakPhase(), state: state)
    #expect(prompt.contains("moodには今の気分を短い言葉"))
  }

  @Test func moodAnswerRuleAppendedForDeclaringPhaseEn() {
    let scenario = makeScenario(language: "en")
    let state = SimulationState.initial(for: scenario)
    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0],
      phase: moodSpeakPhase(), state: state)
    #expect(prompt.contains("Write your current mood in the mood field"))
  }

  // A phase that does not declare `mood` never gets the mood-writing rule,
  // even if a carried-over mood is being surfaced in the section above.
  @Test func moodAnswerRuleOmittedForNonDeclaringPhase() {
    let scenario = makeScenario()
    var state = SimulationState.initial(for: scenario)
    state.variables["mood_Alice"] = "MOOD_SENTINEL"
    let votePhase = Phase(type: .vote, prompt: "Vote!", outputSchema: ["vote": "string"])

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: votePhase, state: state)
    #expect(!prompt.contains("moodには今の気分を短い言葉"))
  }
}
