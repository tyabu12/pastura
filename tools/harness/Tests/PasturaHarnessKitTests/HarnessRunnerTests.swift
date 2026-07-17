import Foundation
import PasturaCore
import Synchronization
import Testing

@testable import PasturaHarnessKit

/// Collects appended JSONL lines in memory.
private final class InMemoryWriter: RunLogWriting {
  private let lines = Mutex<[String]>([])

  func append(_ line: String) throws {
    lines.withLock { $0.append(line) }
  }

  var all: [String] { lines.withLock { $0 } }
}

/// Hands out one scripted AsyncStream per attempt, in order.
private final class ScriptedStreams: Sendable {
  /// `nil` script = a stream that never yields and never finishes
  /// (drives the timeout path; finishes only via task cancellation).
  private let scripts: Mutex<[[SimulationEvent]?]>

  init(_ scripts: [[SimulationEvent]?]) {
    self.scripts = Mutex(scripts)
  }

  func next() -> AsyncStream<SimulationEvent> {
    let script = scripts.withLock { $0.isEmpty ? nil : $0.removeFirst() }
    return AsyncStream { continuation in
      guard let script else { return }  // hang until cancelled
      for event in script { continuation.yield(event) }
      continuation.finish()
    }
  }
}

private func makeScenario() throws -> Scenario {
  let yaml = """
    id: test_scenario
    name: Test Scenario
    description: minimal
    language: ja
    agents: 2
    rounds: 1
    context: test
    personas:
      - name: A
        personality: calm
      - name: B
        personality: bold
    phases:
      - type: speak_all
        prompt: say something
        output:
          statement: string
    """
  return try ScenarioLoader().load(yaml: yaml)
}

/// Reference-typed counter (Mutex itself is noncopyable, so it cannot ride
/// in an optional parameter).
private final class Counter: Sendable {
  private let storage = Mutex<Int>(0)
  var value: Int { storage.withLock { $0 } }
  func increment() { storage.withLock { $0 += 1 } }
}

private func makeRunner(
  scripts: ScriptedStreams, writer: InMemoryWriter,
  timeoutSeconds: Int = 5, factoryCount: Counter? = nil,
  diagLogger: StderrEngineLogger? = nil
) -> HarnessRunner {
  HarnessRunner(
    llmFactory: {
      factoryCount?.increment()
      return MockLLMService(responses: [])
    },
    writer: writer,
    timeoutSeconds: timeoutSeconds,
    streamFactory: { _, _, _ in scripts.next() },
    diagLogger: diagLogger,
    progress: nil)
}

@Suite(.timeLimit(.minutes(1)))
struct HarnessRunnerTests {
  @Test func successOnFirstAttempt() async throws {
    let writer = InMemoryWriter()
    let scripts = ScriptedStreams([
      [
        .roundStarted(round: 1, totalRounds: 1),
        .simulationCompleted
      ]
    ])
    let runner = makeRunner(scripts: scripts, writer: writer)
    let summary = await runner.execute(
      scenario: try makeScenario(), runID: "test-run", startDate: "2026-06-13T00:00:00Z",
      modelName: "mock")
    #expect(summary.status == .ok)
    #expect(summary.attempts == 1)
    #expect(summary.error == nil)

    let lines = writer.all
    #expect(lines.first?.contains("\"type\":\"run_start\"") == true)
    #expect(lines.last?.contains("\"type\":\"run_end\"") == true)
    #expect(lines.last?.contains("\"status\":\"ok\"") == true)
    #expect(lines.contains { $0.contains("\"event\":\"round_started\"") })
  }

  @Test func engineErrorRetriesOnceThenRecordsFailure() async throws {
    let writer = InMemoryWriter()
    let factoryCount = Counter()
    let scripts = ScriptedStreams([
      [.error(.retriesExhausted)],
      [.error(.retriesExhausted)]
    ])
    let runner = makeRunner(
      scripts: scripts, writer: writer, factoryCount: factoryCount)
    let summary = await runner.execute(
      scenario: try makeScenario(), runID: "test-run", startDate: "2026-06-13T00:00:00Z",
      modelName: "mock")
    #expect(summary.status == .error)
    #expect(summary.attempts == 2)
    #expect(summary.error?.contains("retriesExhausted") == true)
    // Fresh LLMService per attempt — never reuse a possibly-wedged context.
    #expect(factoryCount.value == 2)
    #expect(writer.all.last?.contains("\"status\":\"error\"") == true)
  }

  @Test func retryRecoversAfterFirstFailure() async throws {
    let writer = InMemoryWriter()
    let scripts = ScriptedStreams([
      [.error(.jsonParseFailed(raw: "garbage"))],
      [.simulationCompleted]
    ])
    let runner = makeRunner(scripts: scripts, writer: writer)
    let summary = await runner.execute(
      scenario: try makeScenario(), runID: "test-run", startDate: "2026-06-13T00:00:00Z",
      modelName: "mock")
    #expect(summary.status == .ok)
    #expect(summary.attempts == 2)
    #expect(summary.error == nil)
  }

  @Test func streamEndingWithoutCompletionIsFailure() async throws {
    let writer = InMemoryWriter()
    let scripts = ScriptedStreams([
      [.roundStarted(round: 1, totalRounds: 1)],
      [.roundStarted(round: 1, totalRounds: 1)]
    ])
    let runner = makeRunner(scripts: scripts, writer: writer)
    let summary = await runner.execute(
      scenario: try makeScenario(), runID: "test-run", startDate: "2026-06-13T00:00:00Z",
      modelName: "mock")
    #expect(summary.status == .error)
    #expect(summary.error?.contains("simulation_completed") == true)
  }

  @Test(.timeLimit(.minutes(1))) func timeoutFailsBothAttempts() async throws {
    let writer = InMemoryWriter()
    // nil scripts: streams that never finish — only the timeout ends them.
    let scripts = ScriptedStreams([nil, nil])
    let runner = makeRunner(scripts: scripts, writer: writer, timeoutSeconds: 1)
    let summary = await runner.execute(
      scenario: try makeScenario(), runID: "test-run", startDate: "2026-06-13T00:00:00Z",
      modelName: "mock")
    #expect(summary.status == .error)
    #expect(summary.attempts == 2)
    #expect(summary.error?.contains("timeout") == true)
  }

  /// A failed attempt replays the whole scenario, so every Engine diagnostic
  /// is emitted twice. `attempt` is the only field that separates the passes —
  /// without this the two runs' evidence silently merges and a refusal looks
  /// twice as common as it is.
  ///
  /// Drives the real wiring (`execute` -> the injected logger instance), not a
  /// hand-called `beginAttempt`: the stamp advancing is exactly what a future
  /// refactor could drop silently.
  @Test func stampsDiagnosticsWithTheHarnessAttempt() async throws {
    let writer = InMemoryWriter()
    let captured = Mutex<[String]>([])
    let logger = StderrEngineLogger(sink: { line in captured.withLock { $0.append(line) } })

    // Attempt 1 ends without `.simulationCompleted` -> failure -> rerun.
    let scripts = ScriptedStreams([
      [.roundStarted(round: 1, totalRounds: 1)],
      [.roundStarted(round: 1, totalRounds: 1), .simulationCompleted]
    ])
    let runner = makeRunner(scripts: scripts, writer: writer, diagLogger: logger)

    // The scripted streams bypass the Engine, so emit through the same logger
    // the runner stamps — standing in for `LLMCaller.logParseFailure`.
    logger.log(.warning, category: "LLMCaller", "before", privacy: .public)
    let summary = await runner.execute(
      scenario: try makeScenario(), runID: "test-run", startDate: "2026-06-13T00:00:00Z",
      modelName: "mock")
    #expect(summary.attempts == 2)

    // `execute` stamps attempt 1, then 2 — so a record logged after it must
    // carry the last attempt the runner reached.
    logger.log(.warning, category: "LLMCaller", "after", privacy: .public)

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let lines = captured.withLock { $0 }
    let decoded = try lines.map { try decoder.decode(DiagLine.self, from: Data($0.utf8)) }
    let before = try #require(decoded.first { $0.message == "before" })
    let after = try #require(decoded.first { $0.message == "after" })
    #expect(before.attempt == 1)
    #expect(after.attempt == 2)
  }
}
