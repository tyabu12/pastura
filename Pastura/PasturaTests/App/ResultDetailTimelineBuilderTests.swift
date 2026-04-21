import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct ResultDetailTimelineBuilderTests {

  // MARK: - Fixtures

  private func makeTurn(
    id: String = UUID().uuidString,
    round: Int,
    seq: Int,
    phase: String = "speak",
    agent: String? = "Alice"
  ) -> TurnRecord {
    TurnRecord(
      id: id, simulationId: "sim1",
      roundNumber: round, phaseType: phase,
      agentName: agent, rawOutput: "{}",
      parsedOutputJSON: "{}", sequenceNumber: seq,
      createdAt: Date(timeIntervalSince1970: TimeInterval(seq))
    )
  }

  private func makeEvent(
    id: String = UUID().uuidString,
    round: Int,
    seq: Int,
    phase: String,
    payload: CodePhaseEventPayload
  ) -> CodePhaseEventRecord {
    let data = (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)
    let json = String(data: data, encoding: .utf8) ?? "{}"
    return CodePhaseEventRecord(
      id: id, simulationId: "sim1",
      roundNumber: round, phaseType: phase,
      sequenceNumber: seq, payloadJSON: json,
      createdAt: Date(timeIntervalSince1970: TimeInterval(seq))
    )
  }

  // MARK: - Empty

  @Test
  func buildEmpty() {
    let result = ResultDetailTimelineBuilder.build(turns: [], events: [])
    #expect(result.isEmpty)
  }

  // MARK: - Turn-only

  @Test
  func buildTurnsOnlyInsertsRoundSeparators() {
    let turns = [
      makeTurn(round: 1, seq: 1),
      makeTurn(round: 1, seq: 2),
      makeTurn(round: 2, seq: 3)
    ]
    let result = ResultDetailTimelineBuilder.build(turns: turns, events: [])

    #expect(result.count == 5)
    if case .roundSeparator(let round) = result[0] {
      #expect(round == 1)
    } else {
      Issue.record("0 not separator")
    }
    if case .turn(let turn) = result[1] {
      #expect(turn.sequenceNumber == 1)
    } else {
      Issue.record("1 not turn")
    }
    if case .turn(let turn) = result[2] {
      #expect(turn.sequenceNumber == 2)
    } else {
      Issue.record("2 not turn")
    }
    if case .roundSeparator(let round) = result[3] {
      #expect(round == 2)
    } else {
      Issue.record("3 not separator")
    }
    if case .turn(let turn) = result[4] {
      #expect(turn.sequenceNumber == 3)
    } else {
      Issue.record("4 not turn")
    }
  }

  // MARK: - Event-only

  @Test
  func buildEventsOnly() {
    let events = [
      makeEvent(
        round: 1, seq: 1, phase: "summarize",
        payload: .summary(text: "round 1 summary")),
      makeEvent(
        round: 2, seq: 2, phase: "score_calc",
        payload: .scoreUpdate(scores: ["A": 1]))
    ]
    let result = ResultDetailTimelineBuilder.build(turns: [], events: events)

    #expect(result.count == 4)
    if case .roundSeparator(let round) = result[0] {
      #expect(round == 1)
    } else {
      Issue.record("0 not sep")
    }
    if case .codePhase(_, let payload) = result[1] {
      if case .summary(let text) = payload {
        #expect(text == "round 1 summary")
      } else {
        Issue.record("1 wrong payload")
      }
    } else {
      Issue.record("1 not codePhase")
    }
    if case .roundSeparator(let round) = result[2] {
      #expect(round == 2)
    } else {
      Issue.record("2 not sep")
    }
    if case .codePhase = result[3] {} else { Issue.record("3 not codePhase") }
  }

  // MARK: - Mixed ordering

  @Test
  func buildMixedSortsBySequenceNumber() {
    // Interleave turns and events; they should merge by seq.
    let turns = [makeTurn(round: 1, seq: 1), makeTurn(round: 1, seq: 3)]
    let events = [
      makeEvent(
        round: 1, seq: 2, phase: "summarize",
        payload: .summary(text: "mid"))
    ]

    let result = ResultDetailTimelineBuilder.build(turns: turns, events: events)

    #expect(result.count == 4)
    // [separator(1), turn(seq=1), codePhase(seq=2), turn(seq=3)]
    if case .turn(let turn) = result[1] {
      #expect(turn.sequenceNumber == 1)
    } else {
      Issue.record("1 not turn")
    }
    if case .codePhase(let record, _) = result[2] {
      #expect(record.sequenceNumber == 2)
    } else {
      Issue.record("2 not codePhase")
    }
    if case .turn(let turn) = result[3] {
      #expect(turn.sequenceNumber == 3)
    } else {
      Issue.record("3 not turn")
    }
  }

  // MARK: - All-events round (no turns in that round)

  @Test
  func buildAllEventsRoundStillGetsSeparator() {
    // Round 2 has only code-phase events; rounds 1 and 3 have turns.
    let turns = [
      makeTurn(round: 1, seq: 1),
      makeTurn(round: 3, seq: 3)
    ]
    let events = [
      makeEvent(
        round: 2, seq: 2, phase: "summarize",
        payload: .summary(text: "interlude"))
    ]
    let result = ResultDetailTimelineBuilder.build(turns: turns, events: events)

    // Expected: sep(1), turn(seq=1), sep(2), event(seq=2), sep(3), turn(seq=3)
    #expect(result.count == 6)
    if case .roundSeparator(let round) = result[0] {
      #expect(round == 1)
    } else {
      Issue.record("0")
    }
    if case .turn = result[1] {} else { Issue.record("1") }
    if case .roundSeparator(let round) = result[2] {
      #expect(round == 2)
    } else {
      Issue.record("2")
    }
    if case .codePhase = result[3] {} else { Issue.record("3") }
    if case .roundSeparator(let round) = result[4] {
      #expect(round == 3)
    } else {
      Issue.record("4")
    }
    if case .turn = result[5] {} else { Issue.record("5") }
  }

  // MARK: - Malformed payload fallback

  @Test
  func buildMalformedPayloadFallsBackToUnreadableSummary() {
    let bad = CodePhaseEventRecord(
      id: "bad", simulationId: "sim1",
      roundNumber: 1, phaseType: "summarize",
      sequenceNumber: 1,
      payloadJSON: "{not valid json",
      createdAt: Date()
    )
    let result = ResultDetailTimelineBuilder.build(turns: [], events: [bad])

    #expect(result.count == 2)
    if case .codePhase(_, let payload) = result[1] {
      if case .summary(let text) = payload {
        #expect(text == "(unreadable payload)")
      } else {
        Issue.record("payload not summary fallback")
      }
    } else {
      Issue.record("not codePhase")
    }
  }

  // MARK: - phasePath accessor

  @Test
  func itemPhasePathPassesThroughFromUnderlyingRecord() throws {
    // TurnRecord with a nested path [1, 0] (sub-phase of conditional)
    let nestedTurn = TurnRecord(
      id: "t-nested", simulationId: "sim1",
      roundNumber: 1, phaseType: "speak",
      agentName: "Alice", rawOutput: "{}",
      parsedOutputJSON: "{}", sequenceNumber: 1,
      phasePathJSON: "[1,0]",
      createdAt: Date(timeIntervalSince1970: 1)
    )
    // CodePhaseEventRecord with a top-level path [2]
    let event = CodePhaseEventRecord(
      id: "e-top", simulationId: "sim1",
      roundNumber: 1, phaseType: "score_calc",
      sequenceNumber: 2,
      payloadJSON: "{\"type\":\"scoreUpdate\",\"scores\":{}}",
      phasePathJSON: "[2]",
      createdAt: Date(timeIntervalSince1970: 2)
    )
    // Legacy TurnRecord without phasePathJSON
    let legacyTurn = makeTurn(round: 1, seq: 3)

    let result = ResultDetailTimelineBuilder.build(
      turns: [nestedTurn, legacyTurn], events: [event])

    // Expected: sep(1), turn(seq=1), codePhase(seq=2), turn(seq=3)
    #expect(result.count == 4)
    if case .turn(let turn) = result[1] {
      #expect(turn.sequenceNumber == 1)
      #expect(result[1].phasePath == [1, 0])
    } else {
      Issue.record("result[1] not turn(nestedTurn)")
    }
    if case .codePhase = result[2] {
      #expect(result[2].phasePath == [2])
    } else {
      Issue.record("result[2] not codePhase")
    }
    if case .turn(let turn) = result[3] {
      #expect(turn.sequenceNumber == 3)
      #expect(result[3].phasePath == nil)
    } else {
      Issue.record("result[3] not turn(legacyTurn)")
    }
  }

  // MARK: - Item identifiable

  @Test
  func itemIdentifiableUsesRecordIDs() {
    let turn = makeTurn(id: "turn-id", round: 1, seq: 1)
    let event = makeEvent(
      id: "event-id", round: 1, seq: 2,
      phase: "summarize", payload: .summary(text: "x"))
    let result = ResultDetailTimelineBuilder.build(turns: [turn], events: [event])

    let ids = result.map(\.id)
    #expect(ids == ["sep-1", "turn-id", "event-id"])
  }
}
