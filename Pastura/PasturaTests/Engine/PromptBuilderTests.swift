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

  // MARK: - Prompt Hardening (#194 PR#a Item 3)

  // Two new rule lines added in PR#a Item 3 — assert both are present
  // so a future refactor doesn't silently drop the structural-validity
  // emphasis that reduces Hyp A frequency.
  @Test func systemPromptIncludesAugmentedSyntaxRules() {
    let scenario = makeScenario()
    let phase = Phase(
      type: .speakAll,
      prompt: "Speak!",
      outputSchema: ["statement": "string"]
    )
    let state = SimulationState.initial(for: scenario)

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: phase, state: state
    )
    #expect(prompt.contains("JSONに構文エラーがあると失敗扱いになる"))
    #expect(prompt.contains("単一オブジェクトのみ出力"))
  }

  // Placeholder example must appear when outputSchema is set, AND must
  // use placeholder syntax (`<ここに...>`) — concrete Japanese values
  // would risk Gemma 2B parroting the demonstrated content (round 2
  // Axis 5 finding).
  @Test func systemPromptIncludesPlaceholderExampleWhenSchemaSet() {
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
    let exampleLine =
      prompt.components(separatedBy: "\n")
      .first { $0.hasPrefix("例:") } ?? ""
    #expect(!exampleLine.isEmpty, "expected an `例:` line in the output format section")
    #expect(exampleLine.contains("<ここに"), "placeholder convention must be `<ここに{key}>`")
    #expect(exampleLine.contains(">"))
    #expect(exampleLine.contains("statement"))
    #expect(exampleLine.contains("inner_thought"))
  }

  @Test func systemPromptOmitsExampleWhenNoOutputSchema() {
    let scenario = makeScenario()
    let phase = Phase(type: .speakAll, prompt: "Speak!")  // no outputSchema
    let state = SimulationState.initial(for: scenario)

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: phase, state: state
    )
    #expect(!prompt.contains("例:"))
  }

  // Char-count regression guard — total prompt growth from PR#a Item 3
  // must stay within +300 chars of the equivalent pre-PR prompt for the
  // largest preset schema (2 keys per phase across current presets).
  // Loose upper bound: well under 7K chars for an 8K context model.
  @Test func systemPromptCharCountStaysWithinBudget() {
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
    // Budget reasoning: scenario + persona + 6 rule lines + format spec
    // (~2 short lines) for a 2-key schema fits comfortably under 1500
    // chars on the test scenario; CI bound at 2000 leaves room for
    // future minor additions without rebaselining the test.
    #expect(prompt.count < 2000, "prompt grew larger than expected: \(prompt.count) chars")
  }

  // Primary-first ordering (#194 PR#b): the placeholder example and the
  // output-format spec line must both list `statement` before
  // `inner_thought` — alphabetical would invert this and break
  // PartialOutputExtractor's streaming UX (user sees nothing until
  // inner_thought finishes). Source of truth: OutputSchema.fields.
  @Test func systemPromptExampleUsesPrimaryFirstOrder() {
    let scenario = makeScenario()
    let phase = Phase(
      type: .speakAll,
      prompt: "Speak!",
      outputSchema: ["inner_thought": "string", "statement": "string"]
    )
    let state = SimulationState.initial(for: scenario)

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: phase, state: state
    )
    // Both the spec line (`{"statement": ...}`) and the `例:` line must
    // have statement appear before inner_thought.
    let specLine =
      prompt.components(separatedBy: "\n")
      .first { $0.hasPrefix("{\"") } ?? ""
    let exampleLine =
      prompt.components(separatedBy: "\n")
      .first { $0.hasPrefix("例:") } ?? ""
    for line in [specLine, exampleLine] {
      guard
        let sIdx = line.range(of: "statement")?.lowerBound,
        let tIdx = line.range(of: "inner_thought")?.lowerBound
      else {
        Issue.record("expected both keys in line: \(line)")
        continue
      }
      #expect(
        sIdx < tIdx,
        "statement must precede inner_thought in primary-first order: \(line)")
    }
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
