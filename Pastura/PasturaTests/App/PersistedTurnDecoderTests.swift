import Foundation
import Testing

@testable import Pastura

/// Guards the ADR-005 §5.1 read-time content-safety invariant: persisted
/// `parsedOutputJSON` / `rawOutput` are stored UNFILTERED, so the past-results
/// and resume-replay display surfaces MUST route decode through
/// ``PersistedTurnDecoder/decodeFiltered(_:contentFilter:)``. A regression here
/// re-opens the exact filter-bypass #1075 closed.
@Suite(.timeLimit(.minutes(1)))
struct PersistedTurnDecoderTests {

  private func makeTurn(
    parsedOutputJSON: String,
    rawOutput: String = "raw"
  ) -> TurnRecord {
    TurnRecord(
      id: "t1", simulationId: "sim1", roundNumber: 1,
      phaseType: "speak_all", agentName: "Alice",
      rawOutput: rawOutput, parsedOutputJSON: parsedOutputJSON,
      sequenceNumber: 1, createdAt: Date(timeIntervalSince1970: 0))
  }

  private func encodedFields(_ fields: [String: String]) -> String {
    let data = (try? JSONEncoder().encode(TurnOutput(fields: fields))) ?? Data()
    return String(data: data, encoding: .utf8) ?? "{}"
  }

  // MARK: - Decoded-JSON path

  @Test func decodedPathAppliesContentFilter() {
    let filter = ContentFilter(blockedPatterns: ["殺す"])
    let turn = makeTurn(
      parsedOutputJSON: encodedFields([
        "statement": "殺すべきだ",
        "inner_thought": "殺す計画"
      ]))
    let output = PersistedTurnDecoder.decodeFiltered(turn, contentFilter: filter)
    #expect(output.statement == "***べきだ")
    #expect(output.innerThought == "***計画")
  }

  @Test func decodedPathPreservesCleanText() {
    let filter = ContentFilter(blockedPatterns: ["殺す"])
    let turn = makeTurn(parsedOutputJSON: encodedFields(["statement": "こんにちは"]))
    let output = PersistedTurnDecoder.decodeFiltered(turn, contentFilter: filter)
    #expect(output.statement == "こんにちは")
  }

  // MARK: - rawOutput fallback path

  @Test func fallbackPathFiltersRawOutput() {
    // A malformed parsedOutputJSON forces the `["raw": rawOutput]` fallback —
    // which must also pass through the filter (the fallback still renders).
    let filter = ContentFilter(blockedPatterns: ["fuck"])
    let turn = makeTurn(
      parsedOutputJSON: "}{ not json",
      rawOutput: "what the Fuck")
    let output = PersistedTurnDecoder.decodeFiltered(turn, contentFilter: filter)
    #expect(output.fields["raw"] == "what the ***")
  }

  // MARK: - Idempotency (share/export re-filter safety)

  @Test func doubleFilterIsIdempotent() {
    let filter = ContentFilter(blockedPatterns: ["fuck"])
    let turn = makeTurn(parsedOutputJSON: encodedFields(["statement": "Fuck it"]))
    let once = PersistedTurnDecoder.decodeFiltered(turn, contentFilter: filter)
    let twice = filter.filter(once)
    #expect(once.statement == "*** it")
    #expect(twice.statement == once.statement)
  }
}
