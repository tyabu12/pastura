import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct PromptBuilderTests {
  let builder = PromptBuilder()

  // MARK: - Template Expansion

  @Test func expandsSimpleVariable() {
    let result = builder.expandTemplate(
      "Score: {scoreboard}",
      variables: ["scoreboard": "{\"A\": 3}"]
    )
    #expect(result == "Score: {\"A\": 3}")
  }

  @Test func expandsMultipleVariables() {
    let result = builder.expandTemplate(
      "Opponent: {opponent_name}, Score: {scoreboard}",
      variables: ["opponent_name": "Alice", "scoreboard": "{}"]
    )
    #expect(result == "Opponent: Alice, Score: {}")
  }

  @Test func leavesUnknownVariablesUnchanged() {
    let result = builder.expandTemplate(
      "Value: {unknown}",
      variables: ["other": "x"]
    )
    #expect(result == "Value: {unknown}")
  }

  @Test func expandsEmptyTemplate() {
    let result = builder.expandTemplate("", variables: ["a": "b"])
    #expect(result == "")
  }

  // MARK: - Conversation Log Formatting

  @Test func formatsEmptyConversationLog() {
    let result = builder.formatConversationLog([], language: "ja")
    #expect(result == "（まだなし）")
  }

  @Test func formatsConversationLogEntries() {
    let entries = [
      ConversationEntry(agentName: "Alice", content: "Hello!", phaseType: .speakAll, round: 1),
      ConversationEntry(agentName: "Bob", content: "Hi there!", phaseType: .speakAll, round: 1)
    ]
    let result = builder.formatConversationLog(entries, language: "ja")
    #expect(result.contains("Alice: Hello!"))
    #expect(result.contains("Bob: Hi there!"))
  }

  // MARK: - Conversation Log Window (#907)

  private var threeEntries: [ConversationEntry] {
    [
      ConversationEntry(agentName: "Alice", content: "one", phaseType: .speakAll, round: 1),
      ConversationEntry(agentName: "Bob", content: "two", phaseType: .speakAll, round: 1),
      ConversationEntry(agentName: "Charlie", content: "three", phaseType: .speakAll, round: 1)
    ]
  }

  @Test func windowKeepsOnlyLastNEntries() {
    let result = builder.formatConversationLog(threeEntries, language: "en", window: 2)
    #expect(!result.contains("Alice: one"))
    #expect(result.contains("Bob: two"))
    #expect(result.contains("Charlie: three"))
  }

  @Test func windowLargerThanCountKeepsAll() {
    let result = builder.formatConversationLog(threeEntries, language: "en", window: 10)
    #expect(result.contains("Alice: one"))
    #expect(result.contains("Bob: two"))
    #expect(result.contains("Charlie: three"))
  }

  @Test func nilWindowKeepsAll() {
    let result = builder.formatConversationLog(threeEntries, language: "en", window: nil)
    #expect(result.contains("Alice: one"))
    #expect(result.contains("Charlie: three"))
  }

  @Test func windowWithEmptyLogYieldsPlaceholder() {
    let result = builder.formatConversationLog([], language: "en", window: 2)
    #expect(result == "(none yet)")
  }

  // MARK: - Get Main Field

  /// Speak phases route the canonical `statement` field into the
  /// conversation log, regardless of which other fields the schema
  /// happens to carry.
  @Test func getMainFieldReturnsStatementForSpeakPhases() {
    let phase = Phase(
      type: .speakAll, outputSchema: ["statement": "string", "inner_thought": "string"])
    #expect(builder.getMainField(phase: phase) == "statement")
  }

  /// Choose phases use `action` (the canonical primary field bound to the
  /// GBNF enum constraint) — speak handlers don't dispatch to choose, but
  /// `getMainField` is generic on phase type and the conventions table is
  /// the single source of truth.
  @Test func getMainFieldReturnsActionForChoose() {
    let phase = Phase(type: .choose, outputSchema: ["action": "string"])
    #expect(builder.getMainField(phase: phase) == "action")
  }

  /// Vote phases canonicalise on `vote`.
  @Test func getMainFieldReturnsVoteForVote() {
    let phase = Phase(type: .vote, outputSchema: ["vote": "string", "reason": "string"])
    #expect(builder.getMainField(phase: phase) == "vote")
  }

  /// Code phases have no canonical field; the speak fallback applies so
  /// callers (today: only the speak handlers) receive a non-nil string
  /// even if the conventions table returns `nil`.
  @Test func getMainFieldFallsBackToStatementForCodePhases() {
    let phase = Phase(type: .scoreCalc)
    #expect(builder.getMainField(phase: phase) == "statement")
  }

  // MARK: - System Prompt Building

  @Test func systemPromptContainsScenarioContext() {
    let scenario = makeScenario()
    let persona = scenario.personas[0]
    let phase = Phase(
      type: .speakAll,
      prompt: "Speak!",
      outputSchema: ["statement": "string"]
    )
    let state = SimulationState.initial(for: scenario)

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: persona, phase: phase, state: state
    )
    #expect(prompt.contains(scenario.context))
    #expect(prompt.contains(persona.name))
    #expect(prompt.contains(persona.description))
  }

  @Test func systemPromptContainsOutputFormat() {
    let scenario = makeScenario()
    let phase = Phase(
      type: .speakAll,
      prompt: "Speak!",
      outputSchema: ["statement": "string", "inner_thought": "string"]
    )
    let state = SimulationState.initial(for: scenario)

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: phase, state: state
    )
    #expect(prompt.contains("statement"))
    #expect(prompt.contains("inner_thought"))
  }

  @Test func systemPromptIncludesOptionsForChoosePhase() {
    let scenario = makeScenario()
    let phase = Phase(
      type: .choose,
      prompt: "Choose!",
      outputSchema: ["action": "string"],
      options: ["cooperate", "betray"]
    )
    let state = SimulationState.initial(for: scenario)

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: phase, state: state
    )
    #expect(prompt.contains("cooperate"))
    #expect(prompt.contains("betray"))
  }

  @Test func systemPromptIncludesVoteCandidatesExcludingSelf() {
    let scenario = makeScenario()
    let phase = Phase(
      type: .vote,
      prompt: "Vote!",
      outputSchema: ["vote": "string", "reason": "string"],
      excludeSelf: true
    )
    let state = SimulationState.initial(for: scenario)

    // Building for persona "Alice" — candidates should exclude Alice
    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: phase, state: state
    )
    // Extract the vote constraint line to check candidates specifically
    let voteLine =
      prompt.components(separatedBy: "\n")
      .first { $0.contains("voteフィールド") } ?? ""
    #expect(!voteLine.contains("Alice"))
    #expect(voteLine.contains("Bob"))
    #expect(voteLine.contains("Charlie"))
  }

  @Test func systemPromptExcludesEliminatedFromVoteCandidates() {
    let scenario = makeScenario()
    let phase = Phase(
      type: .vote,
      prompt: "Vote!",
      outputSchema: ["vote": "string"],
      excludeSelf: true
    )
    var state = SimulationState.initial(for: scenario)
    state.eliminated["Bob"] = true

    // Building for Alice — Bob is eliminated, should not be in candidates
    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: phase, state: state
    )
    let voteLine =
      prompt.components(separatedBy: "\n")
      .first { $0.contains("voteフィールド") } ?? ""
    #expect(!voteLine.contains("Alice"))
    #expect(!voteLine.contains("Bob"))
    #expect(voteLine.contains("Charlie"))
  }

  // MARK: - Test Helpers

  // Internal (not private) — the sibling-file extension
  // PromptBuilderTests+Hardening.swift calls this helper (testing.md split
  // convention: private members are invisible to sibling-file extensions).
  func makeScenario(language: String = "ja") -> Scenario {
    Scenario(
      id: "test",
      name: "Test Scenario",
      description: "A test scenario",
      language: language,
      agentCount: 3,
      rounds: 3,
      context: "You are in a game show.",
      personas: [
        Persona(name: "Alice", description: "A careful strategist"),
        Persona(name: "Bob", description: "An optimist"),
        Persona(name: "Charlie", description: "A trickster")
      ],
      phases: []
    )
  }
}
