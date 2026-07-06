import Foundation
import Testing

@testable import Pastura

// MARK: - Whisper private-channel injection (#908)
//
// Sibling-file extension per the testing.md split convention — NOT a new
// @Suite (a second suite would run in parallel against the same shared
// state class; see PR #157). Helpers (`builder`, `makeScenario`) stay at
// internal access in PromptBuilderTests.swift so this file can see them.
extension PromptBuilderTests {

  private func whisperPhase() -> Phase {
    Phase(type: .whisper, prompt: "Whisper!", outputSchema: ["statement": "string"])
  }

  // A representative standard user template (references only public template
  // vars — never a raw `whispers_<name>` key), matching how the speak / vote /
  // choose handlers build their prompts. Used by the leak tests.
  private static let standardUserTemplate =
    "Conversation: {conversation_log}\nScore: {scoreboard}\nYour whispers: {my_whispers}"

  // MARK: - injectWhispers

  @Test func injectWhispersSetsMyWhispersFromNamespacedKey() {
    var variables = ["whispers_Alice": "Whispering with Bob\n  Alice: secret"]
    builder.injectWhispers(into: &variables, personaName: "Alice")
    #expect(variables["my_whispers"] == "Whispering with Bob\n  Alice: secret")
  }

  @Test func injectWhispersSetsEmptyStringOnMiss() {
    var variables: [String: String] = [:]
    builder.injectWhispers(into: &variables, personaName: "Alice")
    #expect(variables["my_whispers"] == "")
  }

  // MARK: - System-prompt private-whispers section

  @Test func systemPromptContainsPrivateWhispersSectionWhenSet() {
    let scenario = makeScenario()
    var state = SimulationState.initial(for: scenario)
    state.variables["whispers_Alice"] = "密談相手: Bob\n  Alice: SENTINEL_AB"

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0],
      phase: whisperPhase(), state: state
    )
    #expect(prompt.contains("あなたの密談"))
    #expect(prompt.contains("SENTINEL_AB"))
  }

  @Test func systemPromptOmitsPrivateWhispersSectionWhenUnset() {
    let scenario = makeScenario()
    let state = SimulationState.initial(for: scenario)

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0],
      phase: whisperPhase(), state: state
    )
    #expect(!prompt.contains("あなたの密談"))
  }

  @Test func systemPromptPrivateWhispersSectionEnHeader() {
    let scenario = makeScenario(language: "en")
    var state = SimulationState.initial(for: scenario)
    state.variables["whispers_Alice"] = "Whispering with Bob\n  Alice: SENTINEL_AB"

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0],
      phase: whisperPhase(), state: state
    )
    #expect(prompt.contains("Your Private Whispers"))
    #expect(prompt.contains("SENTINEL_AB"))
  }

  // MARK: - Whisper answer-rule guidance

  @Test func whisperAnswerRulesIncludeGuidanceJa() {
    let scenario = makeScenario()
    let state = SimulationState.initial(for: scenario)
    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0],
      phase: whisperPhase(), state: state
    )
    #expect(prompt.contains("密談相手ひとり"))
  }

  @Test func whisperAnswerRulesIncludeGuidanceEn() {
    let scenario = makeScenario(language: "en")
    let state = SimulationState.initial(for: scenario)
    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0],
      phase: whisperPhase(), state: state
    )
    #expect(prompt.contains("private whisper to your one partner"))
  }

  @Test func nonWhisperPhaseOmitsWhisperGuidance() {
    let scenario = makeScenario()
    let phase = Phase(type: .speakAll, prompt: "Speak!", outputSchema: ["statement": "string"])
    let state = SimulationState.initial(for: scenario)
    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: phase, state: state
    )
    #expect(!prompt.contains("密談相手ひとり"))
  }

  // MARK: - Cross-pair leak guard (default path only)

  // A NON-participant (Charlie) must never see another pair's whisper sentinel,
  // in NEITHER the system prompt NOR an expanded standard user template, for the
  // speak_all / vote / choose phases. The section is gated on the reader's own
  // `whispers_<name>` key, and `{my_whispers}` resolves empty for Charlie.
  @Test func nonParticipantNeverSeesAnotherPairsWhisper() {
    let scenario = makeScenario()  // Alice, Bob, Charlie
    var state = SimulationState.initial(for: scenario)
    state.variables["whispers_Alice"] = "密談相手: Bob\n  Alice: SENTINEL_AB"
    state.variables["whispers_Bob"] = "密談相手: Alice\n  Bob: SENTINEL_AB"
    let charlie = scenario.personas[2]

    let phases: [Phase] = [
      Phase(type: .speakAll, prompt: "Speak!", outputSchema: ["statement": "string"]),
      Phase(type: .vote, prompt: "Vote!", outputSchema: ["vote": "string"]),
      Phase(type: .choose, prompt: "Choose!", outputSchema: ["action": "string"])
    ]
    for phase in phases {
      let system = builder.buildSystemPrompt(
        scenario: scenario, persona: charlie, phase: phase, state: state)
      #expect(!system.contains("SENTINEL_AB"), "system prompt leaked whisper for \(phase.type)")

      var variables = state.variables
      builder.injectWhispers(into: &variables, personaName: charlie.name)
      let user = builder.expandTemplate(Self.standardUserTemplate, variables: variables)
      #expect(!user.contains("SENTINEL_AB"), "user prompt leaked whisper for \(phase.type)")
    }
  }

  // The participant (Alice) DOES see her own whisper — in the system-prompt
  // section AND via `{my_whispers}` on a standard template.
  @Test func participantSeesOwnWhisper() {
    let scenario = makeScenario()
    var state = SimulationState.initial(for: scenario)
    state.variables["whispers_Alice"] = "密談相手: Bob\n  Alice: SENTINEL_AB"
    let alice = scenario.personas[0]
    let phase = Phase(type: .speakAll, prompt: "Speak!", outputSchema: ["statement": "string"])

    let system = builder.buildSystemPrompt(
      scenario: scenario, persona: alice, phase: phase, state: state)
    #expect(system.contains("SENTINEL_AB"))

    var variables = state.variables
    builder.injectWhispers(into: &variables, personaName: alice.name)
    let user = builder.expandTemplate(Self.standardUserTemplate, variables: variables)
    #expect(user.contains("SENTINEL_AB"))
  }
}
