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
    let result = builder.formatConversationLog([])
    #expect(result == "（まだなし）")
  }

  @Test func formatsConversationLogEntries() {
    let entries = [
      ConversationEntry(agentName: "Alice", content: "Hello!", phaseType: .speakAll, round: 1),
      ConversationEntry(agentName: "Bob", content: "Hi there!", phaseType: .speakAll, round: 1)
    ]
    let result = builder.formatConversationLog(entries)
    #expect(result.contains("Alice: Hello!"))
    #expect(result.contains("Bob: Hi there!"))
  }

  // MARK: - Get Main Field

  @Test func getMainFieldReturnsStatementWhenPresent() {
    let phase = Phase(
      type: .speakAll, outputSchema: ["statement": "string", "inner_thought": "string"])
    #expect(builder.getMainField(phase: phase) == "statement")
  }

  @Test func getMainFieldReturnsDeclarationWhenPresent() {
    let phase = Phase(type: .choose, outputSchema: ["declaration": "string", "action": "string"])
    #expect(builder.getMainField(phase: phase) == "declaration")
  }

  @Test func getMainFieldReturnsBokeWhenPresent() {
    let phase = Phase(type: .speakAll, outputSchema: ["boke": "string", "inner_thought": "string"])
    #expect(builder.getMainField(phase: phase) == "boke")
  }

  @Test func getMainFieldDefaultsToStatementWhenNoKnownField() {
    let phase = Phase(type: .speakAll, outputSchema: ["custom_field": "string"])
    #expect(builder.getMainField(phase: phase) == "statement")
  }

  @Test func getMainFieldDefaultsToStatementWhenNoOutputSchema() {
    let phase = Phase(type: .speakAll)
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

  private func makeScenario() -> Scenario {
    Scenario(
      id: "test",
      name: "Test Scenario",
      description: "A test scenario",
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
