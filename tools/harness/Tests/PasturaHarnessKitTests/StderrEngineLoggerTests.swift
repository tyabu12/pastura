import Foundation
import PasturaCore
import Synchronization
import Testing

@testable import PasturaHarnessKit

@Suite(.timeLimit(.minutes(1)))
struct StderrEngineLoggerTests {
  /// Collects rendered records in order.
  private final class Sink: Sendable {
    private let lines = Mutex<[String]>([])
    var captured: [String] { lines.withLock { $0 } }
    var write: @Sendable (String) -> Void {
      { line in self.lines.withLock { $0.append(line) } }
    }
  }

  private func decode(_ line: String) throws -> DiagLine {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(DiagLine.self, from: Data(line.utf8))
  }

  /// The defect this whole channel exists to avoid: `raw=` carries model
  /// output, which is routinely multi-line. If one diagnostic could smear
  /// across many lines, any line-oriented read of the capture would attribute
  /// newlines inside a refusal to separate diagnostics.
  @Test func multiLineMessageStaysOneRecord() throws {
    let sink = Sink()
    let logger = StderrEngineLogger(sink: sink.write)

    let raw = "Sorry, I can't help with that.\n\nTry a different prompt.\n{\"a\":"
    logger.log(
      .warning, category: "LLMCaller",
      "JSON parse failed agent=Alice (attempt 1/3): raw=\(raw)", privacy: .public)

    #expect(sink.captured.count == 1)
    let line = try #require(sink.captured.first)
    #expect(!line.contains("\n"))

    // The content survives the escaping round-trip — the record is evidence,
    // so a lossy render would defeat the purpose.
    let decoded = try decode(line)
    #expect(decoded.message.contains(raw))
  }

  @Test func stampsMonotonicSequence() throws {
    let sink = Sink()
    let logger = StderrEngineLogger(sink: sink.write)

    logger.log(.info, category: "c", "first", privacy: .public)
    logger.log(.info, category: "c", "second", privacy: .public)
    logger.log(.info, category: "c", "third", privacy: .public)

    let seqs = try sink.captured.map { try decode($0).seq }
    #expect(seqs == [1, 2, 3])
  }

  /// `HarnessRunner` reruns a failed scenario, replaying every diagnostic.
  /// Without this stamp the two passes are indistinguishable.
  @Test func stampsHarnessAttempt() throws {
    let sink = Sink()
    let logger = StderrEngineLogger(sink: sink.write)

    logger.beginAttempt(1)
    logger.log(.warning, category: "c", "first pass", privacy: .public)
    logger.beginAttempt(2)
    logger.log(.warning, category: "c", "second pass", privacy: .public)

    let decoded = try sink.captured.map { try decode($0) }
    #expect(decoded.map(\.attempt) == [1, 2])
    // seq keeps running across attempts, so records stay totally ordered.
    #expect(decoded.map(\.seq) == [1, 2])
  }

  /// Pins the unit: **one record is one failed sample, not one failed turn.**
  /// A turn burns `LLMCaller.maxRetries + 1` samples and logs each, so a reader
  /// counting records gets samples — which is the unit the two guardrail arms
  /// are comparable in, and NOT the turn tally (that lives in `turn_skipped`).
  /// If this ever collapsed to one record per turn, the doc's counting rule
  /// would be silently wrong in both units at once.
  @Test func oneTurnEmitsOneRecordPerFailedAttempt() throws {
    let sink = Sink()
    let logger = StderrEngineLogger(sink: sink.write)
    logger.beginAttempt(1)

    for attempt in 0...2 {
      logger.log(
        .warning, category: "LLMCaller",
        "JSON parse failed agent=Alice (attempt \(attempt + 1)/3): raw=Sorry, I can't help with that.",
        privacy: .public)
    }

    #expect(sink.captured.count == 3)
    let decoded = try sink.captured.map { try decode($0) }
    #expect(decoded.allSatisfy { $0.attempt == 1 })
    #expect(decoded.allSatisfy { $0.message.contains("Sorry, I can't help with that.") })
  }

  @Test func rendersLevelAndCategory() throws {
    let sink = Sink()
    let logger = StderrEngineLogger(sink: sink.write)

    logger.log(.debug, category: "StreamingDiag", "d", privacy: .private)
    logger.log(.info, category: "LLMCaller", "i", privacy: .public)
    logger.log(.warning, category: "LLMCaller", "w", privacy: .public)

    let decoded = try sink.captured.map { try decode($0) }
    #expect(decoded.map(\.level) == ["debug", "info", "warning"])
    #expect(decoded.map(\.category) == ["StreamingDiag", "LLMCaller", "LLMCaller"])
    // Assert on the raw line, not the decoded value: `type` has an initial
    // value, so synthesized Decodable never reads it — a decoded check would
    // pass even if the encoder dropped the field the JSONL consumer keys on.
    #expect(sink.captured.allSatisfy { $0.contains("\"type\":\"diag\"") })
  }

  /// `.private` governs OSLog redaction off-device; this logger is a local
  /// developer instrument where the raw content IS the artifact. A redacting
  /// implementation would silently empty the evidence channel.
  @Test func privateMessagesAreNotRedacted() throws {
    let sink = Sink()
    let logger = StderrEngineLogger(sink: sink.write)

    logger.log(.warning, category: "c", "sensitive raw output", privacy: .private)

    let decoded = try decode(try #require(sink.captured.first))
    #expect(decoded.message == "sensitive raw output")
  }
}
