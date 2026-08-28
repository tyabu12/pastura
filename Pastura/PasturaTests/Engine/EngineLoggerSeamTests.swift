import Foundation
import Testing
import os

@testable import Pastura

/// Thread-safe spy ``EngineLogger`` capturing every emitted line so the seam
/// contract (category / level / message / privacy) can be asserted after the
/// #501 S0.2 OSLog-removal refactor.
final class SpyEngineLogger: EngineLogger, @unchecked Sendable {
  struct Entry: Equatable {
    let level: EngineLogLevel
    let category: String
    let message: String
    let privacy: EngineLogPrivacy
  }

  private let lock = OSAllocatedUnfairLock(initialState: [Entry]())

  func log(
    _ level: EngineLogLevel, category: String, _ message: String,
    privacy: EngineLogPrivacy
  ) {
    lock.withLock {
      $0.append(Entry(level: level, category: category, message: message, privacy: privacy))
    }
  }

  var entries: [Entry] { lock.withLock { $0 } }
}

// Serialized: SimulationRunner tests create Tasks and AsyncStreams that can
// interfere with each other when run in parallel on the simulator.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct EngineLoggerSeamTests {
  /// Parse failure → the StreamingDiag `retryCause parse_failed` line (the
  /// load-bearing `scripts/analyze-streaming-diag.sh` wire format) and the
  /// LLMCaller warning both route through the seam as `.public`.
  @Test func parseFailureRoutesRetryCauseAndWarningThroughSeam() async throws {
    let mock = MockLLMService(responses: ["not json at all", #"{"statement": "ok"}"#])
    try await mock.loadModel()
    let spy = SpyEngineLogger()
    let caller = LLMCaller(logger: spy)
    let collector = EventCollector()

    _ = try await caller.call(
      llm: mock, system: "sys", user: "usr", agentName: "Alice",
      phaseType: .speakAll,
      suspendController: SuspendController(), emitter: collector.emit)

    let retry = spy.entries.first { $0.message.hasPrefix("retryCause") }
    #expect(retry?.category == "StreamingDiag")
    #expect(retry?.level == .info)
    #expect(retry?.privacy == .public)
    // Exact wire format is load-bearing: the analyzer regex expects `cause=`
    // to be the trailing token.
    #expect(retry?.message == "retryCause agent=Alice attempt=1 cause=parse_failed")

    let warning = spy.entries.first { $0.message.hasPrefix("JSON parse failed") }
    #expect(warning?.category == "LLMCaller")
    #expect(warning?.level == .warning)
    #expect(warning?.privacy == .public)
  }

  /// Empty-field retry: `logEmptyFields` interpolates agent output, so it stays
  /// `.private` (the documented S0.2 privacy delta — off-device redaction is
  /// preserved / stricter). The paired `retryCause empty_field` is `.public`.
  @Test func emptyFieldDiagnosticStaysPrivate() async throws {
    let mock = MockLLMService(responses: [#"{"statement": "..."}"#, #"{"statement": "real"}"#])
    try await mock.loadModel()
    let spy = SpyEngineLogger()
    let caller = LLMCaller(logger: spy)
    let collector = EventCollector()

    _ = try await caller.call(
      llm: mock, system: "sys", user: "usr", agentName: "Bob",
      phaseType: .speakAll,
      suspendController: SuspendController(), emitter: collector.emit)

    let empty = spy.entries.first { $0.message.hasPrefix("Empty fields detected") }
    #expect(empty?.category == "LLMCaller")
    #expect(empty?.level == .debug)
    #expect(empty?.privacy == .private)

    let retry = spy.entries.first { $0.message.contains("cause=empty_field") }
    #expect(retry?.category == "StreamingDiag")
    #expect(retry?.privacy == .public)
  }

  /// Through-runner reach pin: a logger injected via
  /// ``SimulationRunner/init(detector:logger:)`` must actually reach the run
  /// path — `SimulationRunner` → `ExecutionContext` → `PhaseContext` →
  /// handler → ``LLMCaller``. The suite's other cases construct `LLMCaller`
  /// directly, so none of them would notice a runner that dropped the seam on
  /// the floor and fell back to ``NoopEngineLogger``.
  ///
  /// Landed as the Swift half of the Kotlin injection-seam PR (the D2d
  /// Swift-pin-then-Kotlin-twin pairing); the Kotlin twin is
  /// `SimulationEngineSeamInjectionTests.injectedLoggerReachesTheRunPath` in
  /// `shared/engine/src/commonTest`. Swift is already wired, so this passes on
  /// arrival — its job is to be the parity spec that twin mirrors.
  @Test func runnerInjectedLoggerReachesTheRunPath() async throws {
    // Alice: attempt 1 unparseable → one `retryCause … parse_failed` line,
    // attempt 2 valid. Bob: valid on attempt 1. Deterministic, and the only
    // StreamingDiag emission in the run.
    //
    // One spare response beyond the 3 the run consumes: a retry-budget
    // regression must redden on the seam assertion below, not on the mock
    // running out of scripts before that assertion is ever reached.
    let valid = #"{"statement": "a statement"}"#
    let mock = MockLLMService(responses: ["not json at all", valid, valid, valid])
    try await mock.loadModel()
    let spy = SpyEngineLogger()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      language: "en",
      rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])]
    )
    let runner = SimulationRunner(logger: spy)
    let events = await collectAllEvents(
      runner.run(scenario: scenario, llm: mock, suspendController: SuspendController()))

    #expect(events.contains { if case .simulationCompleted = $0 { true } else { false } })
    let diag = spy.entries.filter { $0.category == "StreamingDiag" }.map(\.message)
    #expect(diag.contains("retryCause agent=Alice attempt=1 cause=parse_failed"))
  }

  /// Adapter smoke: every (level, privacy) combination is callable and the
  /// switch is exhaustive. OSLog's actual off-device redaction is
  /// real-device-verifiable only (documented manual `log stream` step in the
  /// PR body); this guards the adapter from a non-exhaustive refactor / crash.
  @Test func osLogAdapterHandlesAllLevelPrivacyCombos() {
    let adapter = OSLogEngineLogger()
    for level in [EngineLogLevel.debug, .info, .warning] {
      for privacy in [EngineLogPrivacy.public, .private] {
        adapter.log(level, category: "SeamSmokeTest", "probe", privacy: privacy)
      }
    }
  }
}
