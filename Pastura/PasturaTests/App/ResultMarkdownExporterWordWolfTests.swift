import Foundation
import Testing

@testable import Pastura

/// End-to-end Word Wolf fixture for the Markdown exporter.
///
/// Models a realistic Word Wolf round (assign → speak → vote → eliminate →
/// score_calc/judge verdict → summarize) to defend the four Acceptance
/// Criteria from #92 in a single integration-style test.
@Suite(.timeLimit(.minutes(1))) @MainActor
struct ResultMarkdownExporterWordWolfTests {

  private let createdAt = Date(timeIntervalSince1970: 1_712_000_000)
  private let updatedAt = Date(timeIntervalSince1970: 1_712_000_342)
  private let exportAt = Date(timeIntervalSince1970: 1_713_000_000)

  private func makeExporter() -> ResultMarkdownExporter {
    ResultMarkdownExporter(
      contentFilter: ContentFilter(blockedPatterns: []),
      environment: .init(deviceModel: "iPhone", osVersion: "Version 17.5"),
      now: exportAt)
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

  private func makeScenario() -> ScenarioRecord {
    ScenarioRecord(
      id: "s1", name: "Word Wolf",
      yamlDefinition: "name: Word Wolf\n",
      isPreset: true, createdAt: Date(), updatedAt: Date())
  }

  private func makeState() -> SimulationState {
    SimulationState(
      scores: [:], eliminated: [:], conversationLog: [],
      lastOutputs: [:], voteResults: [:], pairings: [],
      variables: [:], currentRound: 1)
  }

  private func makeCodePhaseEvent(
    round: Int, phaseType: String, seq: Int,
    payload: CodePhaseEventPayload
  ) -> CodePhaseEventRecord {
    let json =
      (try? JSONEncoder().encode(payload)).flatMap {
        String(data: $0, encoding: .utf8)
      } ?? "{}"
    return CodePhaseEventRecord(
      id: UUID().uuidString, simulationId: "sim1",
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

  // swiftlint:disable:next function_body_length
  @Test func wordWolfRoundExportSatisfiesAllAcceptanceCriteria() throws {
    let exporter = makeExporter()
    let personas = ["Alice", "Bob", "Charlie"]

    var seq = 0
    func nextSeq() -> Int {
      seq += 1
      return seq
    }

    // assign phase: each persona gets a role.
    let assignAlice = makeCodePhaseEvent(
      round: 1, phaseType: "assign", seq: nextSeq(),
      payload: .assignment(agent: "Alice", value: "wolf"))
    let assignBob = makeCodePhaseEvent(
      round: 1, phaseType: "assign", seq: nextSeq(),
      payload: .assignment(agent: "Bob", value: "villager"))
    let assignCharlie = makeCodePhaseEvent(
      round: 1, phaseType: "assign", seq: nextSeq(),
      payload: .assignment(agent: "Charlie", value: "villager"))

    // speak_all phase: each agent speaks.
    let speakAlice = makeTurn(
      round: 1, seq: nextSeq(), phase: "speak_all",
      agent: "Alice", fields: ["statement": "I think it's a cat."])
    let speakBob = makeTurn(
      round: 1, seq: nextSeq(), phase: "speak_all",
      agent: "Bob", fields: ["statement": "Mine has fluffy fur."])
    let speakCharlie = makeTurn(
      round: 1, seq: nextSeq(), phase: "speak_all",
      agent: "Charlie", fields: ["statement": "Mine purrs a lot."])

    // vote phase: agents vote, then tallies emit.
    let voteAlice = makeTurn(
      round: 1, seq: nextSeq(), phase: "vote",
      agent: "Alice", fields: ["vote": "Charlie"])
    let voteBob = makeTurn(
      round: 1, seq: nextSeq(), phase: "vote",
      agent: "Bob", fields: ["vote": "Alice"])
    let voteCharlie = makeTurn(
      round: 1, seq: nextSeq(), phase: "vote",
      agent: "Charlie", fields: ["vote": "Alice"])
    let voteResultsEvent = makeCodePhaseEvent(
      round: 1, phaseType: "vote", seq: nextSeq(),
      payload: .voteResults(
        votes: ["Alice": "Charlie", "Bob": "Alice", "Charlie": "Alice"],
        tallies: ["Alice": 2, "Charlie": 1]))

    // eliminate phase: most-voted agent (Alice — the wolf) is eliminated.
    let eliminationEvent = makeCodePhaseEvent(
      round: 1, phaseType: "eliminate", seq: nextSeq(),
      payload: .elimination(agent: "Alice", voteCount: 2))

    // score_calc phase (wordwolf_judge): emits a summary verdict, no scores.
    let judgeSummary = makeCodePhaseEvent(
      round: 1, phaseType: "score_calc", seq: nextSeq(),
      payload: .summary(text: "多数派の勝ち！ お題は『犬』、ウルフは『猫』"))

    // summarize phase: round wrap-up summary.
    let roundSummary = makeCodePhaseEvent(
      round: 1, phaseType: "summarize", seq: nextSeq(),
      payload: .summary(text: "Round 1 ends. The wolf was discovered."))

    let turns = [speakAlice, speakBob, speakCharlie, voteAlice, voteBob, voteCharlie]
    let events = [
      assignAlice, assignBob, assignCharlie,
      voteResultsEvent, eliminationEvent, judgeSummary, roundSummary
    ]

    let input = ResultMarkdownExporter.Input(
      simulation: makeSimulation(),
      scenario: makeScenario(),
      turns: turns,
      codePhaseEvents: events,
      personas: personas,
      state: makeState())
    let result = try exporter.export(input)

    // (i) "X was assigned: wolf" visible.
    #expect(result.text.contains("**Alice** was assigned: wolf"))
    #expect(result.text.contains("**Bob** was assigned: villager"))

    // (ii) Both summaries appear under their respective phaseType headers.
    let scoreCalcRange = try #require(
      result.text.range(of: "#### Phase: score_calc"))
    let summarizeRange = try #require(
      result.text.range(of: "#### Phase: summarize"))
    let judgeRange = try #require(result.text.range(of: "多数派の勝ち"))
    let wrapRange = try #require(result.text.range(of: "Round 1 ends"))
    // Judge verdict falls under score_calc, round wrap under summarize.
    #expect(scoreCalcRange.upperBound < judgeRange.lowerBound)
    #expect(judgeRange.upperBound <= summarizeRange.lowerBound)
    #expect(summarizeRange.upperBound < wrapRange.lowerBound)

    // (iii) Roster Status renders, Alice eliminated, others active.
    #expect(result.text.contains("## Roster Status"))
    #expect(result.text.contains("| Alice | eliminated |"))
    #expect(result.text.contains("| Bob | active |"))
    #expect(result.text.contains("| Charlie | active |"))

    // (iv) NO misleading all-zero score table (Word Wolf never emits scoreUpdate).
    #expect(!result.text.contains("## Final Scores"))
    #expect(!result.text.contains("| Alice | 0 |"))
    #expect(!result.text.contains("| Bob | 0 |"))

    // (v) Vote phase ordering: agent votes appear before tally line.
    let aliceVoteRange = try #require(
      result.text.range(of: "- **Alice**: → Charlie"))
    let tallyRange = try #require(result.text.range(of: "| Alice | 2 |"))
    #expect(aliceVoteRange.upperBound < tallyRange.lowerBound)

    // (vi) AC roll-up: each Phase header is present.
    #expect(result.text.contains("#### Phase: assign"))
    #expect(result.text.contains("#### Phase: speak_all"))
    #expect(result.text.contains("#### Phase: vote"))
    #expect(result.text.contains("#### Phase: eliminate"))
    #expect(result.text.contains("#### Phase: score_calc"))
    #expect(result.text.contains("#### Phase: summarize"))
  }
}
