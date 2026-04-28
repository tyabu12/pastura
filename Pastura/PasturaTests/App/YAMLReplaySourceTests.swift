import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
// swiftlint:disable:next type_body_length
struct YAMLReplaySourceTests {

  // MARK: - Fixture scenario

  // Access modifier: `internal` (default) — sibling-file extensions
  // cannot see `private` members (see `.claude/rules/testing.md`).
  // This suite's fixture helpers are reused by
  // `YAMLReplaySourceTests+PlannedEvents.swift`.

  static let scenarioYAML = """
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

  func makeScenario() throws -> Scenario {
    try ScenarioLoader().load(yaml: Self.scenarioYAML)
  }

  /// Speed up replay for tests — 100× means a 1200 ms nominal delay
  /// finishes in 12 ms, keeping the suite well under the 1-minute cap.
  var fastConfig: ReplayPlaybackConfig {
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
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Bob
          fields: { statement: 'hi' }
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

  @Test func decodesEventInjectedHitPayload() async throws {
    let yaml = """
      schema_version: 1
      turns: []
      code_phase_events:
        - round: 1
          phase_index: 0
          phase_type: event_inject
          summary: 'Event: 突然停電'
          payload:
            kind: eventInjected
            event: 突然停電
      """
    let source = try YAMLReplaySource(
      yaml: yaml, scenario: makeScenario(), config: fastConfig)

    var collected: [SimulationEvent] = []
    for await event in source.events() { collected.append(event) }

    #expect(collected.count == 1)
    if case .eventInjected(let event) = collected[0] {
      #expect(event == "突然停電")
    } else {
      Issue.record("Expected eventInjected hit, got \(collected[0])")
    }
  }

  @Test func decodesEventInjectedMissPayload() async throws {
    // The miss case is meaningful — exporter writes `event: null` so
    // decoders must produce `.eventInjected(nil)`, not silently
    // collapse to `.eventInjected("")`.
    let yaml = """
      schema_version: 1
      turns: []
      code_phase_events:
        - round: 1
          phase_index: 0
          phase_type: event_inject
          summary: 'No event this round'
          payload:
            kind: eventInjected
            event: null
      """
    let source = try YAMLReplaySource(
      yaml: yaml, scenario: makeScenario(), config: fastConfig)

    var collected: [SimulationEvent] = []
    for await event in source.events() { collected.append(event) }

    #expect(collected.count == 1)
    if case .eventInjected(let event) = collected[0] {
      #expect(event == nil)
    } else {
      Issue.record("Expected eventInjected miss, got \(collected[0])")
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

  @Test func pacingIsSourcedFromConfigNotYAML() async throws {
    // The YAML carries NO delay hint. The source derives per-event
    // sleep from `ReplayPlaybackConfig.turnDelayMs` /
    // `codePhaseDelayMs` scaled by `speedMultiplier`. A tiny delay
    // here keeps the test fast; doubling it doubles wall time.
    let yaml = """
      schema_version: 1
      turns:
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Alice
          fields: { statement: 'hi' }
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Bob
          fields: { statement: 'hi' }
      """
    let slowConfig = ReplayPlaybackConfig(
      speedMultiplier: 1.0, turnDelayMs: 60, codePhaseDelayMs: 20,
      loopBehaviour: .stopAfterLast, onComplete: .stopPlayback)
    let source = try YAMLReplaySource(
      yaml: yaml, scenario: makeScenario(), config: slowConfig)

    let start = Date()
    var count = 0
    for await _ in source.events() { count += 1 }
    let elapsed = Date().timeIntervalSince(start)

    #expect(count == 2)
    // Two turns at 60 ms each ≈ 120 ms locally. The lower bound is
    // load-bearing: if pacing were silently bypassed the test would
    // return in <10 ms. The upper bound is just a "not runaway"
    // sanity check — CI under code coverage has seen this test body
    // take 1–3 s, so generous headroom is required. The suite's
    // `.timeLimit(.minutes(1))` catches genuinely hung tests.
    #expect(elapsed >= 0.100)
    #expect(elapsed < 30.0)
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
