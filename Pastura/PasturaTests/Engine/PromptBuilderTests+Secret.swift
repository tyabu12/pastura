import Foundation
import Testing

@testable import Pastura

// MARK: - Persona secret injection (#914)
//
// Sibling-file extension per the testing.md split convention — NOT a new
// @Suite (a second suite would run in parallel against the same shared
// state class; see PR #157). Helpers (`builder`, `makeScenario`) stay at
// internal access in PromptBuilderTests.swift so this file can see them.
extension PromptBuilderTests {

  private static let aliceSecret = "You already sold the family house."
  private static let bobSecret = "You forged the will last winter."

  /// Alice carries a secret, Bob a different one, Charlie none — so one
  /// scenario covers the present / absent / cross-agent cases.
  private func makeSecretScenario(language: String = "ja") -> Scenario {
    let base = makeScenario(language: language)
    return Scenario(
      id: base.id,
      name: base.name,
      description: base.description,
      language: language,
      agentCount: base.agentCount,
      rounds: base.rounds,
      context: base.context,
      personas: [
        Persona(name: "Alice", description: "A careful strategist", secret: Self.aliceSecret),
        Persona(name: "Bob", description: "An optimist", secret: Self.bobSecret),
        Persona(name: "Charlie", description: "A trickster")
      ],
      phases: base.phases
    )
  }

  private func speakPhase() -> Phase {
    Phase(
      type: .speakAll, prompt: "Speak!",
      outputSchema: ["statement": "string", "inner_thought": "string"])
  }

  private func systemPrompt(for personaIndex: Int, language: String = "ja") -> String {
    let scenario = makeSecretScenario(language: language)
    return builder.buildSystemPrompt(
      scenario: scenario,
      persona: scenario.personas[personaIndex],
      phase: speakPhase(),
      state: SimulationState.initial(for: scenario))
  }

  // MARK: - Section presence + wording

  @Test func systemPromptContainsSecretSectionWhenSetJA() {
    let prompt = systemPrompt(for: 0)
    #expect(prompt.contains("## あなたの秘密（他の参加者は知りません）"))
    #expect(prompt.contains(Self.aliceSecret))
    // Channel-scoped guidance: statement is off-limits, inner_thought licensed.
    #expect(prompt.contains("発言（statement）では決して明かしてはいけません"))
    #expect(prompt.contains("心の声（inner_thought）では率直に触れてかまいません"))
  }

  @Test func systemPromptContainsSecretSectionWhenSetEN() {
    let prompt = systemPrompt(for: 0, language: "en")
    #expect(prompt.contains("## Your Secret (the other participants do not know this)"))
    #expect(prompt.contains(Self.aliceSecret))
    #expect(prompt.contains("Never reveal this secret in anything the other participants can hear"))
    #expect(prompt.contains("You may reference it freely in your inner_thought"))
  }

  /// Charlie has no secret. Checked in both languages — asserting the EN header
  /// is absent from a `ja` prompt would pass no matter what the code did.
  @Test(arguments: ["ja", "en"])
  func systemPromptOmitsSecretSectionWhenNil(_ language: String) {
    let prompt = systemPrompt(for: 2, language: language)
    #expect(!prompt.contains("## あなたの秘密"))
    #expect(!prompt.contains("Your Secret"))
  }

  @Test func systemPromptOmitsSecretSectionWhenEmptyAfterLoad() throws {
    // Empty ≡ absent: the loader normalizes `secret: ""` to nil, so no
    // header-only section can ever render.
    let yaml = """
      id: t
      name: T
      description: d
      language: ja
      agents: 2
      rounds: 1
      context: c
      personas:
        - name: Alice
          description: A
          secret: ""
        - name: Bob
          description: B
      phases:
        - type: speak_all
          prompt: Speak
          output:
            statement: string
      """
    let scenario = try ScenarioLoader().load(yaml: yaml)
    #expect(scenario.personas[0].secret == nil)
    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: speakPhase(),
      state: SimulationState.initial(for: scenario))
    #expect(!prompt.contains("## あなたの秘密"))
  }

  // MARK: - Placement

  @Test func secretSectionSitsAfterCharacterAndBeforeAnswerRules() throws {
    let prompt = systemPrompt(for: 0)
    let character = try #require(prompt.range(of: "## あなたのキャラクター"))
    let secret = try #require(prompt.range(of: "## あなたの秘密"))
    let rules = try #require(prompt.range(of: "## 回答ルール"))
    #expect(character.lowerBound < secret.lowerBound)
    #expect(secret.lowerBound < rules.lowerBound)
  }

  @Test func secretSectionPrecedesPerRoundPrivateNotes() throws {
    let scenario = makeSecretScenario()
    var state = SimulationState.initial(for: scenario)
    state.variables["notes_Alice"] = "Bob is bluffing."
    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: speakPhase(), state: state)
    let secret = try #require(prompt.range(of: "## あなたの秘密"))
    let notes = try #require(prompt.range(of: "## あなたの非公開メモ"))
    #expect(secret.lowerBound < notes.lowerBound)
  }

  // MARK: - Cross-agent structural invariant
  //
  // `appendSecretSection` takes a single `persona` and never reads
  // `scenario.personas`, so today this holds by signature rather than by a
  // guard — there is no fix line to revert. It is kept as a structural pin: it
  // would catch a future refactor that renders a participant roster with
  // per-persona fields into the system prompt. The load-bearing regression gate
  // for the secrecy invariant is the handler-driven test in
  // `SecrecyInvariantTests`, which drives the real user-prompt assembly.

  @Test func systemPromptNeverContainsAnotherAgentsSecret() {
    let alice = systemPrompt(for: 0)
    #expect(!alice.contains(Self.bobSecret))

    let bob = systemPrompt(for: 1)
    #expect(!bob.contains(Self.aliceSecret))

    let charlie = systemPrompt(for: 2)
    #expect(!charlie.contains(Self.aliceSecret))
    #expect(!charlie.contains(Self.bobSecret))
  }
}
