import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1))) @MainActor
struct ResultMarkdownExporterCodePhaseTests {  // swiftlint:disable:this type_body_length

  // MARK: - Fixtures

  private let createdAt = Date(timeIntervalSince1970: 1_712_000_000)
  private let updatedAt = Date(timeIntervalSince1970: 1_712_000_342)
  private let exportAt = Date(timeIntervalSince1970: 1_713_000_000)

  private func makeScenario(
    id: String = "s1",
    name: String = "Test",
    yaml: String = "name: Test\n"
  ) -> ScenarioRecord {
    ScenarioRecord(
      id: id, name: name, yamlDefinition: yaml,
      isPreset: false, createdAt: Date(), updatedAt: Date())
  }

  private func makeSimulation() -> SimulationRecord {
    SimulationRecord(
      id: "sim1", scenarioId: "s1",
      status: SimulationStatus.completed.rawValue,
      currentRound: 1, currentPhaseIndex: 0,
      stateJSON: "{}", configJSON: nil,
      createdAt: createdAt, updatedAt: updatedAt,
      modelIdentifier: "test", llmBackend: "mock")
  }

  private func makeState() -> SimulationState {
    SimulationState(
      scores: [:], eliminated: [:], conversationLog: [],
      lastOutputs: [:], voteResults: [:], pairings: [],
      variables: [:], currentRound: 1)
  }

  private func makeCodePhaseEvent(
    id: String = UUID().uuidString,
    round: Int = 1,
    phaseType: String,
    seq: Int,
    payload: CodePhaseEventPayload
  ) -> CodePhaseEventRecord {
    let data = (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)
    let json = String(data: data, encoding: .utf8) ?? "{}"
    return CodePhaseEventRecord(
      id: id, simulationId: "sim1",
      roundNumber: round, phaseType: phaseType,
      sequenceNumber: seq, payloadJSON: json,
      createdAt: Date())
  }

  private func makeTurn(
    round: Int, seq: Int, phase: String,
    agent: String?, fields: [String: String]
  ) -> TurnRecord {
    let json =
      (try? JSONEncoder().encode(TurnOutput(fields: fields))).flatMap {
        String(data: $0, encoding: .utf8)
      } ?? "{}"
    return TurnRecord(
      id: UUID().uuidString, simulationId: "sim1",
      roundNumber: round, phaseType: phase,
      agentName: agent, rawOutput: json,
      parsedOutputJSON: json, sequenceNumber: seq,
      createdAt: Date())
  }

  private func makeExporter() -> ResultMarkdownExporter {
    ResultMarkdownExporter(
      contentFilter: ContentFilter(blockedPatterns: []),
      environment: .init(deviceModel: "iPhone", osVersion: "Version 17.5"),
      now: exportAt)
  }

  private func input(
    turns: [TurnRecord] = [],
    events: [CodePhaseEventRecord] = [],
    personas: [String] = []
  ) -> ResultMarkdownExporter.Input {
    ResultMarkdownExporter.Input(
      simulation: makeSimulation(),
      scenario: makeScenario(),
      turns: turns,
      codePhaseEvents: events,
      personas: personas,
      state: makeState())
  }

  // MARK: - Per-phase renderers

  @Test func rendersEliminationEvent() throws {
    let exporter = makeExporter()
    let event = makeCodePhaseEvent(
      phaseType: "eliminate", seq: 1,
      payload: .elimination(agent: "Bob", voteCount: 2))

    let result = try exporter.export(input(events: [event]))

    #expect(result.text.contains("#### Phase: eliminate"))
    #expect(result.text.contains("**Bob** was eliminated (2 votes)"))
  }

  @Test func rendersScoreUpdateEvent() throws {
    let exporter = makeExporter()
    let event = makeCodePhaseEvent(
      phaseType: "score_calc", seq: 1,
      payload: .scoreUpdate(scores: ["Alice": 5, "Bob": -1]))

    let result = try exporter.export(input(events: [event]))

    #expect(result.text.contains("#### Phase: score_calc"))
    #expect(result.text.contains("Alice: 5"))
    #expect(result.text.contains("Bob: -1"))
  }

  @Test func rendersSummaryEventVerbatim() throws {
    let exporter = makeExporter()
    let event = makeCodePhaseEvent(
      phaseType: "summarize", seq: 1,
      payload: .summary(text: "多数派の勝ち！"))

    let result = try exporter.export(input(events: [event]))

    #expect(result.text.contains("#### Phase: summarize"))
    #expect(result.text.contains("多数派の勝ち！"))
  }

  @Test func rendersVoteResultsWithTalliesAndVoterMap() throws {
    let exporter = makeExporter()
    let event = makeCodePhaseEvent(
      phaseType: "vote", seq: 1,
      payload: .voteResults(
        votes: ["Alice": "Bob", "Bob": "Alice", "Charlie": "Bob"],
        tallies: ["Alice": 1, "Bob": 2]))

    let result = try exporter.export(input(events: [event]))

    // Tally table
    #expect(result.text.contains("| Bob | 2 |"))
    #expect(result.text.contains("| Alice | 1 |"))
    // Voter → target list
    #expect(result.text.contains("Alice → Bob"))
    #expect(result.text.contains("Bob → Alice"))
    #expect(result.text.contains("Charlie → Bob"))
  }

  @Test func rendersPairingResultEvent() throws {
    let exporter = makeExporter()
    let event = makeCodePhaseEvent(
      phaseType: "choose", seq: 1,
      payload: .pairingResult(
        agent1: "Alice", action1: "cooperate",
        agent2: "Bob", action2: "betray"))

    let result = try exporter.export(input(events: [event]))

    #expect(result.text.contains("#### Phase: choose"))
    #expect(result.text.contains("Alice"))
    #expect(result.text.contains("Bob"))
    #expect(result.text.contains("cooperate"))
    #expect(result.text.contains("betray"))
  }

  @Test func rendersAssignmentEvent() throws {
    let exporter = makeExporter()
    let event = makeCodePhaseEvent(
      phaseType: "assign", seq: 1,
      payload: .assignment(agent: "Alice", value: "wolf"))

    let result = try exporter.export(input(events: [event]))

    #expect(result.text.contains("#### Phase: assign"))
    #expect(result.text.contains("**Alice** was assigned: wolf"))
  }

  // MARK: - Merge-sort ordering

  @Test func mergesTurnsAndEventsBySequenceNumber() throws {
    let exporter = makeExporter()
    // Vote phase: 3 agent votes then tallies result.
    let turn1 = makeTurn(
      round: 1, seq: 1, phase: "vote",
      agent: "Alice", fields: ["vote": "Bob"])
    let turn2 = makeTurn(
      round: 1, seq: 2, phase: "vote",
      agent: "Bob", fields: ["vote": "Alice"])
    let turn3 = makeTurn(
      round: 1, seq: 3, phase: "vote",
      agent: "Charlie", fields: ["vote": "Bob"])
    let tallyEvent = makeCodePhaseEvent(
      phaseType: "vote", seq: 4,
      payload: .voteResults(
        votes: ["Alice": "Bob", "Bob": "Alice", "Charlie": "Bob"],
        tallies: ["Alice": 1, "Bob": 2]))

    let result = try exporter.export(
      input(turns: [turn1, turn2, turn3], events: [tallyEvent]))

    // Agent votes must appear before tally line in the output.
    let aliceIdx = try #require(result.text.range(of: "- **Alice**: → Bob")?.lowerBound)
    let bobIdx = try #require(result.text.range(of: "- **Bob**: → Alice")?.lowerBound)
    let charlieIdx = try #require(
      result.text.range(of: "- **Charlie**: → Bob")?.lowerBound)
    let tallyIdx = try #require(result.text.range(of: "| Bob | 2 |")?.lowerBound)
    #expect(aliceIdx < bobIdx)
    #expect(bobIdx < charlieIdx)
    #expect(charlieIdx < tallyIdx)
  }

  // MARK: - Bifurcated Final Scores / Roster Status gating

  @Test func finalScoresRendersWhenScoreUpdatePresent() throws {
    let exporter = makeExporter()
    let event = makeCodePhaseEvent(
      phaseType: "score_calc", seq: 1,
      payload: .scoreUpdate(scores: ["Alice": 10, "Bob": 3]))

    let result = try exporter.export(
      input(events: [event], personas: ["Alice", "Bob"]))

    #expect(result.text.contains("## Final Scores"))
    #expect(result.text.contains("| Alice | 10 | active |"))
    #expect(result.text.contains("| Bob | 3 | active |"))
  }

  @Test func finalScoresWithPartialScoresFillsZeroForMissingPersonas() throws {
    let exporter = makeExporter()
    let event = makeCodePhaseEvent(
      phaseType: "score_calc", seq: 1,
      payload: .scoreUpdate(scores: ["Alice": 5]))

    let result = try exporter.export(
      input(events: [event], personas: ["Alice", "Bob", "Charlie"]))

    #expect(result.text.contains("## Final Scores"))
    #expect(result.text.contains("| Alice | 5 | active |"))
    #expect(result.text.contains("| Bob | 0 | active |"))
    #expect(result.text.contains("| Charlie | 0 | active |"))
  }

  @Test func finalScoresReflectsEliminationStatus() throws {
    let exporter = makeExporter()
    let scoreEvent = makeCodePhaseEvent(
      phaseType: "score_calc", seq: 1,
      payload: .scoreUpdate(scores: ["Alice": 10, "Bob": 3]))
    let elimEvent = makeCodePhaseEvent(
      phaseType: "eliminate", seq: 2,
      payload: .elimination(agent: "Bob", voteCount: 2))

    let result = try exporter.export(
      input(
        events: [scoreEvent, elimEvent],
        personas: ["Alice", "Bob"]))

    #expect(result.text.contains("| Alice | 10 | active |"))
    #expect(result.text.contains("| Bob | 3 | eliminated |"))
  }

  @Test func finalScoresRendersWhenAllScoresZero() throws {
    // A scoring scenario that ran score_calc but produced all zeros (rare but
    // legitimate) should still render — the presence of a scoreUpdate event
    // proves scoring happened.
    let exporter = makeExporter()
    let event = makeCodePhaseEvent(
      phaseType: "score_calc", seq: 1,
      payload: .scoreUpdate(scores: ["Alice": 0, "Bob": 0]))

    let result = try exporter.export(
      input(events: [event], personas: ["Alice", "Bob"]))

    #expect(result.text.contains("## Final Scores"))
    #expect(result.text.contains("| Alice | 0 | active |"))
  }

  @Test func rosterStatusRendersWhenOnlyEliminationPresent() throws {
    // Word Wolf-style: wordwolf_judge emits summary, eliminate emits elimination,
    // but no scoreUpdate — show status without a misleading all-zero score table.
    let exporter = makeExporter()
    let elim = makeCodePhaseEvent(
      phaseType: "eliminate", seq: 1,
      payload: .elimination(agent: "Charlie", voteCount: 3))

    let result = try exporter.export(
      input(events: [elim], personas: ["Alice", "Bob", "Charlie"]))

    // Roster Status section renders.
    #expect(result.text.contains("## Roster Status"))
    // NO misleading all-zero Final Scores.
    #expect(!result.text.contains("## Final Scores"))
    #expect(!result.text.contains("| Alice | 0 |"))
    // Per-agent status present.
    #expect(result.text.contains("Charlie"))
    #expect(result.text.contains("eliminated"))
    #expect(result.text.contains("Alice"))
    #expect(result.text.contains("active"))
  }

  @Test func omitsBothSectionsWhenNoScoreOrEliminationEvents() throws {
    let exporter = makeExporter()
    // Only a summary event — no scoring, no elimination.
    let summary = makeCodePhaseEvent(
      phaseType: "summarize", seq: 1,
      payload: .summary(text: "ended"))

    let result = try exporter.export(
      input(events: [summary], personas: ["Alice", "Bob"]))

    #expect(!result.text.contains("## Final Scores"))
    #expect(!result.text.contains("## Roster Status"))
  }

  @Test func omitsBothSectionsForObservationOnlyScenario() throws {
    let exporter = makeExporter()
    let turn = makeTurn(
      round: 1, seq: 1, phase: "speak_each",
      agent: "Alice", fields: ["statement": "hi"])

    let result = try exporter.export(
      input(turns: [turn], events: [], personas: ["Alice", "Bob"]))

    #expect(!result.text.contains("## Final Scores"))
    #expect(!result.text.contains("## Roster Status"))
  }

  // The Word Wolf end-to-end fixture lives in
  // `ResultMarkdownExporterWordWolfTests.swift` to keep this file under
  // `file_length`. It models a realistic Word Wolf round and defends the
  // four Acceptance Criteria from #92.
}
