import Foundation
import Testing
import os

@testable import Pastura

/// Streaming-path tests for ``LLMCaller``. Split from `LLMCallerTests`
/// to keep each suite under its type-body-length lint budget.
struct LLMCallerStreamingTests {
  let caller = LLMCaller()

  @Test func emitsAgentOutputStreamPerDeltaDuringStreaming() async throws {
    // Configure Mock to return each part of the JSON as a separate
    // chunk. LLMCaller must run each accumulated buffer through the
    // partial extractor and emit an agentOutputStream snapshot per
    // non-empty delta.
    let mock = MockLLMService(responses: [])
    mock.setStreamChunks([
      [
        #"{"statement":""#,
        #"hel"#,
        #"lo"#,
        #"","inner_thought":"thinking"}"#
      ]
    ])
    try await mock.loadModel()

    let collector = EventCollector()
    let result = try await caller.call(
      llm: mock, system: "s", user: "u", agentName: "Alice",
      suspendController: SuspendController(),
      emitter: collector.emit
    )

    #expect(result.statement == "hello")
    #expect(result.innerThought == "thinking")

    let streamEvents = collector.events.compactMap { event -> (String?, String?)? in
      if case .agentOutputStream(_, let primary, let thought) = event {
        return (primary, thought)
      }
      return nil
    }
    #expect(
      streamEvents.count >= 4,
      "expected at least 4 stream events (one per delta), got \(streamEvents.count)")

    // Primary progresses: nil → "" (opening quote) → "hel" → "hello".
    // The final snapshot emitted must have primary == "hello".
    let lastStream = streamEvents.last
    #expect(lastStream?.0 == "hello")
  }

  @Test func streamSnapshotsArrayIsMonotonicOnPrimary() async throws {
    let mock = MockLLMService(responses: [])
    mock.setStreamChunks([
      [
        #"{"statement":""#,
        "a", "b", "c",
        #"","inner_thought":"x"}"#
      ]
    ])
    try await mock.loadModel()

    let collector = EventCollector()
    _ = try await caller.call(
      llm: mock, system: "s", user: "u", agentName: "Alice",
      suspendController: SuspendController(),
      emitter: collector.emit
    )

    // Extract non-nil primary values in emission order — each must be
    // a prefix of the next.
    let primaries: [String] = collector.events.compactMap { event in
      if case .agentOutputStream(_, let primary, _) = event {
        return primary
      }
      return nil
    }
    var previous = ""
    for primary in primaries {
      #expect(
        primary.hasPrefix(previous) || previous.isEmpty,
        "primary shrank: was \(previous), now \(primary)")
      previous = primary
    }
  }

  @Test func streamRetryOnParseFailureStartsFreshStream() async throws {
    // First stream yields garbage (parse fails), second yields valid JSON.
    // After the retry, the second stream's snapshots should reset the
    // consumer view — new emissions overwrite.
    let mock = MockLLMService(responses: [])
    mock.setStreamChunks([
      ["not json at all"],
      [#"{"statement":"ok"}"#]
    ])
    try await mock.loadModel()

    let collector = EventCollector()
    let result = try await caller.call(
      llm: mock, system: "s", user: "u", agentName: "Alice",
      suspendController: SuspendController(),
      emitter: collector.emit
    )

    #expect(result.statement == "ok")
    // Two inference cycles — one failed parse retry.
    let starts = collector.events.filter {
      if case .inferenceStarted = $0 { return true }
      return false
    }
    #expect(starts.count == 2, "expected 2 inferenceStarted, got \(starts.count)")
    #expect(mock.streamCallCount == 2)
  }
}
