import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct YAMLReplaySourceTests {

  // MARK: - Fixture scenario

  private static let scenarioYAML = """
    id: ts
    name: Test
    description: ''
    agents: 2
    rounds: 1
    context: ''
    personas:
      - name: Alice
        description: ''
      - name: Bob
        description: ''
    phases:
      - type: speak_all
        prompt: say
        output:
          statement: string
    """

  private func makeScenario() throws -> Scenario {
    try ScenarioLoader().load(yaml: Self.scenarioYAML)
  }

  /// Speed up replay for tests — 100× means a 1200 ms nominal delay
  /// finishes in 12 ms, keeping the suite well under the 1-minute cap.
  private var fastConfig: ReplayPlaybackConfig {
    ReplayPlaybackConfig(
      speedMultiplier: 100.0,
      loopBehaviour: .stopAfterLast,
      onComplete: .stopPlayback)
  }

  // MARK: - Schema-version handling

  @Test func throwsOnUnsupportedSchemaVersion() throws {
    let yaml = """
      schema_version: 9999
      turns: []
      """
    let scenario = try makeScenario()
    #expect(throws: YAMLReplaySourceError.unsupportedSchemaVersion(9999)) {
      _ = try YAMLReplaySource(yaml: yaml, scenario: scenario)
    }
  }

  @Test func throwsOnMissingSchemaVersion() throws {
    let yaml = """
      turns: []
      """
    let scenario = try makeScenario()
    #expect(throws: YAMLReplaySourceError.unsupportedSchemaVersion(nil)) {
      _ = try YAMLReplaySource(yaml: yaml, scenario: scenario)
    }
  }

  // MARK: - Malformed input

  @Test func throwsOnMalformedYAML() throws {
    let yaml = "\t\tnot: [valid: yaml: :"
    let scenario = try makeScenario()
    #expect(throws: YAMLReplaySourceError.self) {
      _ = try YAMLReplaySource(yaml: yaml, scenario: scenario)
    }
  }

  @Test func throwsOnNonMappingRoot() throws {
    let yaml = "- just\n- a\n- list"
    let scenario = try makeScenario()
    #expect(throws: YAMLReplaySourceError.self) {
      _ = try YAMLReplaySource(yaml: yaml, scenario: scenario)
    }
  }

  @Test func throwsOnUnknownAgent() throws {
    let yaml = """
      schema_version: 1
      turns:
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Eve
          fields: { statement: 'hi' }
          delay_ms_before: 0
      """
    let scenario = try makeScenario()
    #expect(throws: YAMLReplaySourceError.unknownAgent("Eve")) {
      _ = try YAMLReplaySource(yaml: yaml, scenario: scenario)
    }
  }

  @Test func throwsOnUnknownPhaseType() throws {
    let yaml = """
      schema_version: 1
      turns:
        - round: 1
          phase_index: 0
          phase_type: telekinesis
          agent: Alice
          fields: { statement: 'hi' }
          delay_ms_before: 0
      """
    let scenario = try makeScenario()
    #expect(throws: YAMLReplaySourceError.unknownPhaseType("telekinesis")) {
      _ = try YAMLReplaySource(yaml: yaml, scenario: scenario)
    }
  }

  // MARK: - Event emission

  @Test func emitsAgentOutputEventsInOrder() async throws {
    let yaml = """
      schema_version: 1
      turns:
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Alice
          fields: { statement: 'hello' }
          delay_ms_before: 0
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Bob
          fields: { statement: 'hi' }
          delay_ms_before: 0
      """
    let source = try YAMLReplaySource(
      yaml: yaml, scenario: makeScenario(), config: fastConfig)

    var collected: [SimulationEvent] = []
    for await event in source.events() { collected.append(event) }

    #expect(collected.count == 2)
    if case .agentOutput(let agent, let output, let phase) = collected[0] {
      #expect(agent == "Alice")
      #expect(output.statement == "hello")
      #expect(phase == .speakAll)
    } else {
      Issue.record("Expected agentOutput at index 0")
    }
    if case .agentOutput(let agent, _, _) = collected[1] {
      #expect(agent == "Bob")
    } else {
      Issue.record("Expected agentOutput at index 1")
    }
  }

  @Test func decodesScoreUpdatePayload() async throws {
    let yaml = """
      schema_version: 1
      turns: []
      code_phase_events:
        - round: 2
          phase_index: 0
          phase_type: score_calc
          summary: 'Scores — Alice: 1'
          payload:
            kind: scoreUpdate
            scores:
              Alice: 1
              Bob: 0
          delay_ms_before: 0
      """
    let source = try YAMLReplaySource(
      yaml: yaml, scenario: makeScenario(), config: fastConfig)

    var collected: [SimulationEvent] = []
    for await event in source.events() { collected.append(event) }

    #expect(collected.count == 1)
    if case .scoreUpdate(let scores) = collected[0] {
      #expect(scores == ["Alice": 1, "Bob": 0])
    } else {
      Issue.record("Expected scoreUpdate")
    }
  }

  @Test func decodesEliminationPayload() async throws {
    let yaml = """
      schema_version: 1
      turns: []
      code_phase_events:
        - round: 1
          phase_index: 0
          phase_type: eliminate
          summary: 'Alice was eliminated (3 votes)'
          payload:
            kind: elimination
            agent: Alice
            vote_count: 3
          delay_ms_before: 0
      """
    let source = try YAMLReplaySource(
      yaml: yaml, scenario: makeScenario(), config: fastConfig)

    var collected: [SimulationEvent] = []
    for await event in source.events() { collected.append(event) }

    #expect(collected.count == 1)
    if case .elimination(let agent, let count) = collected[0] {
      #expect(agent == "Alice")
      #expect(count == 3)
    } else {
      Issue.record("Expected elimination")
    }
  }

  @Test func fallsBackToSummaryWhenPayloadKindUnknown() async throws {
    let yaml = """
      schema_version: 1
      turns: []
      code_phase_events:
        - round: 1
          phase_index: 0
          phase_type: summarize
          summary: 'a narrative line'
          payload:
            kind: newKindFromV2
          delay_ms_before: 0
      """
    let source = try YAMLReplaySource(
      yaml: yaml, scenario: makeScenario(), config: fastConfig)

    var collected: [SimulationEvent] = []
    for await event in source.events() { collected.append(event) }

    #expect(collected.count == 1)
    if case .summary(let text) = collected[0] {
      #expect(text == "a narrative line")
    } else {
      Issue.record("Expected summary fallback")
    }
  }

  @Test func eventsCanBeConsumedMultipleTimes() async throws {
    let yaml = """
      schema_version: 1
      turns:
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Alice
          fields: { statement: 'once' }
          delay_ms_before: 0
      """
    let source = try YAMLReplaySource(
      yaml: yaml, scenario: makeScenario(), config: fastConfig)

    // First pass
    var first: [SimulationEvent] = []
    for await event in source.events() { first.append(event) }
    #expect(first.count == 1)

    // Second pass must yield an equivalent sequence — the source holds
    // the pre-parsed plan, not a one-shot iterator (spec §4.3).
    var second: [SimulationEvent] = []
    for await event in source.events() { second.append(event) }
    #expect(second.count == 1)
    #expect(first[0] == second[0])
  }
}
