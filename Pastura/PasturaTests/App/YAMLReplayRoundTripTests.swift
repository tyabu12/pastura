import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct YAMLReplayRoundTripTests {

  // MARK: - Fixtures

  private static let scenarioYAML = """
    id: rt_scn
    name: Round-trip Scenario
    description: ''
    agents: 2
    rounds: 2
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
      - type: vote
        prompt: vote
        candidates: agents
      - type: score_calc
        logic: vote_tally
    """

  private let exportAt = Date(timeIntervalSince1970: 1_713_000_000)

  private var scenarioRecord: ScenarioRecord {
    ScenarioRecord(
      id: "rt_scn", name: "Round-trip Scenario",
      yamlDefinition: Self.scenarioYAML, isPreset: true,
      createdAt: Date(), updatedAt: Date())
  }

  private var simulation: SimulationRecord {
    SimulationRecord(
      id: "sim", scenarioId: "rt_scn",
      status: SimulationStatus.completed.rawValue,
      currentRound: 2, currentPhaseIndex: 2,
      stateJSON: "{}", configJSON: nil,
      createdAt: exportAt, updatedAt: exportAt,
      modelIdentifier: "gemma4_e2b_q4km", llmBackend: "llama.cpp")
  }

  private func makeTurn(
    seq: Int, phase: String, agent: String, fields: [String: String]
  ) -> TurnRecord {
    let json =
      (try? JSONEncoder().encode(TurnOutput(fields: fields))).flatMap {
        String(data: $0, encoding: .utf8)
      } ?? "{}"
    return TurnRecord(
      id: UUID().uuidString, simulationId: "sim",
      roundNumber: 1, phaseType: phase,
      agentName: agent, rawOutput: json,
      parsedOutputJSON: json, sequenceNumber: seq,
      createdAt: exportAt)
  }

  private func makeCodeEvent(
    seq: Int, phase: String, payload: CodePhaseEventPayload
  ) -> CodePhaseEventRecord {
    let json =
      (try? JSONEncoder().encode(payload)).flatMap {
        String(data: $0, encoding: .utf8)
      } ?? "{}"
    return CodePhaseEventRecord(
      id: UUID().uuidString, simulationId: "sim",
      roundNumber: 2, phaseType: phase,
      sequenceNumber: seq, payloadJSON: json,
      createdAt: exportAt)
  }

  private var fastConfig: ReplayPlaybackConfig {
    ReplayPlaybackConfig(
      playbackSpeed: .instant,
      loopBehaviour: .stopAfterLast,
      onComplete: .stopPlayback)
  }

  private func exporter() -> YAMLReplayExporter {
    YAMLReplayExporter(
      contentFilter: ContentFilter(blockedPatterns: []),
      now: exportAt)
  }

  // MARK: - End-to-end round trip

  @Test func turnsRoundTripByAgentAndField() async throws {
    let turns = [
      makeTurn(
        seq: 1, phase: "speak_all", agent: "Alice",
        fields: ["statement": "hello there", "inner_thought": "I'm nervous"]),
      makeTurn(
        seq: 2, phase: "speak_all", agent: "Bob",
        fields: ["statement": "私は猫が好きです"])
    ]
    let exported = try exporter().export(
      .init(simulation: simulation, scenario: scenarioRecord, turns: turns))

    let scenario = try ScenarioLoader().load(yaml: scenarioRecord.yamlDefinition)
    let source = try YAMLReplaySource(
      yaml: exported.text, scenario: scenario, config: fastConfig)

    var replayed: [SimulationEvent] = []
    for await event in source.events() { replayed.append(event) }

    #expect(replayed.count == 2)
    if case .agentOutput(let agent, let output, let phase) = replayed[0] {
      #expect(agent == "Alice")
      #expect(output.statement == "hello there")
      #expect(output.innerThought == "I'm nervous")
      #expect(phase == .speakAll)
    } else {
      Issue.record("Expected agentOutput at 0")
    }
    if case .agentOutput(let agent, let output, _) = replayed[1] {
      #expect(agent == "Bob")
      #expect(output.statement == "私は猫が好きです")
    } else {
      Issue.record("Expected agentOutput at 1")
    }
  }

  @Test func codePhasePayloadsRoundTripStructurally() async throws {
    let events = [
      makeCodeEvent(
        seq: 3, phase: "vote",
        payload: .voteResults(
          votes: ["Alice": "Bob", "Bob": "Alice"],
          tallies: ["Alice": 1, "Bob": 1])),
      makeCodeEvent(
        seq: 4, phase: "score_calc",
        payload: .scoreUpdate(scores: ["Alice": 0, "Bob": 2])),
      makeCodeEvent(
        seq: 5, phase: "eliminate",
        payload: .elimination(agent: "Alice", voteCount: 1)),
      makeCodeEvent(
        seq: 6, phase: "assign",
        payload: .assignment(agent: "Bob", value: "wolf")),
      makeCodeEvent(
        seq: 7, phase: "choose",
        payload: .pairingResult(
          agent1: "Alice", action1: "cooperate",
          agent2: "Bob", action2: "betray")),
      makeCodeEvent(
        seq: 8, phase: "summarize",
        payload: .summary(text: "Bob wins."))
    ]
    let exported = try exporter().export(
      .init(
        simulation: simulation, scenario: scenarioRecord,
        turns: [], codePhaseEvents: events))

    let scenario = try ScenarioLoader().load(yaml: scenarioRecord.yamlDefinition)
    let source = try YAMLReplaySource(
      yaml: exported.text, scenario: scenario, config: fastConfig)

    var replayed: [SimulationEvent] = []
    for await event in source.events() { replayed.append(event) }

    #expect(replayed.count == 6)
    if case .voteResults(let votes, let tallies) = replayed[0] {
      #expect(votes == ["Alice": "Bob", "Bob": "Alice"])
      #expect(tallies == ["Alice": 1, "Bob": 1])
    } else {
      Issue.record("Expected voteResults at 0")
    }
    #expect(replayed[1] == .scoreUpdate(scores: ["Alice": 0, "Bob": 2]))
    #expect(replayed[2] == .elimination(agent: "Alice", voteCount: 1))
    #expect(replayed[3] == .assignment(agent: "Bob", value: "wolf"))
    #expect(
      replayed[4]
        == .pairingResult(
          agent1: "Alice", action1: "cooperate",
          agent2: "Bob", action2: "betray"))
    #expect(replayed[5] == .summary(text: "Bob wins."))
  }

  @Test func eventInjectedPayloadRoundTripsHitAndMiss() async throws {
    // Two event_inject events: one hit (event != nil), one miss (event == nil).
    // The miss case is meaningful — past-results timelines need to
    // distinguish "no event this round" from "phase didn't run".
    let events = [
      makeCodeEvent(
        seq: 3, phase: "event_inject",
        payload: .eventInjected(event: "突然停電が起きた")),
      makeCodeEvent(
        seq: 4, phase: "event_inject",
        payload: .eventInjected(event: nil))
    ]
    let exported = try exporter().export(
      .init(
        simulation: simulation, scenario: scenarioRecord,
        turns: [], codePhaseEvents: events))

    let scenario = try ScenarioLoader().load(yaml: scenarioRecord.yamlDefinition)
    let source = try YAMLReplaySource(
      yaml: exported.text, scenario: scenario, config: fastConfig)

    var replayed: [SimulationEvent] = []
    for await event in source.events() { replayed.append(event) }

    #expect(replayed.count == 2)
    #expect(replayed[0] == .eventInjected(event: "突然停電が起きた"))
    #expect(replayed[1] == .eventInjected(event: nil))
  }

  // MARK: - Exporter determinism (idempotency proxy)

  @Test func exporterIsDeterministicForSameInput() throws {
    // Full idempotency (`export(import(export(x))) == export(x)`) requires
    // synthesising TurnRecord / CodePhaseEventRecord rows from emitted
    // SimulationEvents — machinery that lives outside the primitive's
    // scope. The weaker determinism contract tested here is the load-
    // bearing invariant: given the same input records, the exporter
    // produces byte-stable YAML. If it regresses, diff-review breaks.
    let turns = [
      makeTurn(
        seq: 1, phase: "speak_all", agent: "Alice",
        fields: ["statement": "hello"]),
      makeTurn(
        seq: 2, phase: "speak_all", agent: "Bob",
        fields: ["statement": "hi"])
    ]
    let events = [
      makeCodeEvent(
        seq: 3, phase: "score_calc",
        payload: .scoreUpdate(scores: ["Alice": 1, "Bob": 1]))
    ]
    let input = YAMLReplayExporter.Input(
      simulation: simulation, scenario: scenarioRecord,
      turns: turns, codePhaseEvents: events)

    let first = try exporter().export(input).text
    let second = try exporter().export(input).text
    #expect(first == second)
  }

  // MARK: - Golden-fixture regression

  @Test func exportedDocumentParsesBackWithoutError() throws {
    // Regression guard: a future exporter change that emits subtly
    // invalid YAML (e.g. a new field with wrong indentation) would fail
    // here at load time, before any test asserting specific event
    // content even runs.
    let turns = [
      makeTurn(
        seq: 1, phase: "speak_all", agent: "Alice",
        fields: [
          "statement": "multi\nline\nstatement",
          "inner_thought": "quotes: \"safe\" and 'safe'"
        ])
    ]
    let exported = try exporter().export(
      .init(simulation: simulation, scenario: scenarioRecord, turns: turns))

    let scenario = try ScenarioLoader().load(yaml: scenarioRecord.yamlDefinition)
    _ = try YAMLReplaySource(yaml: exported.text, scenario: scenario)
  }
}
