import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ResumeLogReplayMapperTests {

  // MARK: - Fixtures

  private func makeTurn(
    round: Int,
    seq: Int,
    phase: String = "speak_all",
    agent: String? = "Alice",
    fields: [String: String] = ["statement": "hello"]
  ) -> TurnRecord {
    let json =
      (try? JSONEncoder().encode(TurnOutput(fields: fields)))
      .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    return TurnRecord(
      id: UUID().uuidString, simulationId: "sim1",
      roundNumber: round, phaseType: phase,
      agentName: agent, rawOutput: "raw",
      parsedOutputJSON: json, sequenceNumber: seq,
      createdAt: Date(timeIntervalSince1970: TimeInterval(seq)))
  }

  private func makeEvent(
    round: Int, seq: Int, phase: String, payload: CodePhaseEventPayload
  ) -> CodePhaseEventRecord {
    let data = (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)
    let json = String(data: data, encoding: .utf8) ?? "{}"
    return CodePhaseEventRecord(
      id: UUID().uuidString, simulationId: "sim1",
      roundNumber: round, phaseType: phase,
      sequenceNumber: seq, payloadJSON: json,
      createdAt: Date(timeIntervalSince1970: TimeInterval(seq)))
  }

  // MARK: - Round separator → roundStarted (carries totalRounds)

  @Test
  func mapsRoundSeparatorToRoundStartedWithScenarioTotal() {
    let items = ResultDetailTimelineBuilder.build(
      turns: [makeTurn(round: 1, seq: 1)], events: [])
    let entries = ResumeLogReplayMapper.map(
      items: items, totalRounds: 5, contentFilter: ContentFilter())

    // build inserts a leading .roundSeparator(1) before the single turn.
    #expect(entries.count == 2)
    guard case .roundStarted(let round, let total) = entries[0].kind else {
      Issue.record("entry 0 is not .roundStarted")
      return
    }
    #expect(round == 1)
    // `.roundSeparator` carries no total; the mapper must fill it from the
    // scenario so the replayed header line reads "Round 1 / 5".
    #expect(total == 5)
  }

  // MARK: - Turn → agentOutput

  @Test
  func mapsTurnToAgentOutputPreservingAgentPhaseAndFields() {
    let items = ResultDetailTimelineBuilder.build(
      turns: [
        makeTurn(round: 1, seq: 1, phase: "speak_all", agent: "Bob", fields: ["statement": "hi"])
      ],
      events: [])
    let entries = ResumeLogReplayMapper.map(
      items: items, totalRounds: 3, contentFilter: ContentFilter())

    guard case .agentOutput(let agent, let output, let phaseType) = entries[1].kind else {
      Issue.record("entry 1 is not .agentOutput")
      return
    }
    #expect(agent == "Bob")
    #expect(phaseType == .speakAll)
    #expect(output.fields["statement"] == "hi")
  }

  // MARK: - Legacy turn without agentName is dropped

  @Test
  func dropsLegacyTurnWithoutAgentName() {
    let items = ResultDetailTimelineBuilder.build(
      turns: [makeTurn(round: 1, seq: 1, agent: nil)], events: [])
    let entries = ResumeLogReplayMapper.map(
      items: items, totalRounds: 3, contentFilter: ContentFilter())

    // Only the round separator survives; the agent-less turn maps to nil.
    #expect(entries.count == 1)
    guard case .roundStarted = entries[0].kind else {
      Issue.record("expected lone .roundStarted")
      return
    }
  }

  // MARK: - Code-phase payloads → matching LogEntry kinds

  @Test
  func mapsScoreUpdateCodePhase() {
    let items = ResultDetailTimelineBuilder.build(
      turns: [],
      events: [
        makeEvent(
          round: 1, seq: 1, phase: "score_calc",
          payload: .scoreUpdate(scores: ["Alice": 3, "Bob": 1]))
      ])
    let entries = ResumeLogReplayMapper.map(
      items: items, totalRounds: 3, contentFilter: ContentFilter())

    guard case .scoreUpdate(let scores) = entries[1].kind else {
      Issue.record("entry 1 is not .scoreUpdate")
      return
    }
    #expect(scores["Alice"] == 3)
    #expect(scores["Bob"] == 1)
  }

  @Test
  func mapsEliminationCodePhase() {
    let items = ResultDetailTimelineBuilder.build(
      turns: [],
      events: [
        makeEvent(
          round: 1, seq: 1, phase: "eliminate",
          payload: .elimination(agent: "Carol", voteCount: 2))
      ])
    let entries = ResumeLogReplayMapper.map(
      items: items, totalRounds: 3, contentFilter: ContentFilter())

    guard case .elimination(let agent, let voteCount) = entries[1].kind else {
      Issue.record("entry 1 is not .elimination")
      return
    }
    #expect(agent == "Carol")
    #expect(voteCount == 2)
  }

  // MARK: - Ordering preserved (merge-sorted by sequenceNumber)

  @Test
  func preservesSequenceOrderAcrossTurnsAndCodePhases() {
    let turns = [
      makeTurn(round: 1, seq: 1, agent: "Alice"),
      makeTurn(round: 1, seq: 3, agent: "Bob")
    ]
    let events = [
      makeEvent(round: 1, seq: 2, phase: "score_calc", payload: .scoreUpdate(scores: ["Alice": 1]))
    ]
    let items = ResultDetailTimelineBuilder.build(turns: turns, events: events)
    let entries = ResumeLogReplayMapper.map(
      items: items, totalRounds: 3, contentFilter: ContentFilter())

    // Expected: roundSeparator, Alice(seq1), score(seq2), Bob(seq3).
    #expect(entries.count == 4)
    guard case .agentOutput(let a0, _, _) = entries[1].kind,
      case .scoreUpdate = entries[2].kind,
      case .agentOutput(let a3, _, _) = entries[3].kind
    else {
      Issue.record("ordering not preserved")
      return
    }
    #expect(a0 == "Alice")
    #expect(a3 == "Bob")
  }
}
