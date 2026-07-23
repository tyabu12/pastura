import Foundation
import PasturaCore
import Synchronization
import Testing

@testable import PasturaHarnessKit

/// Collects appended JSONL lines in memory (mirrors `HarnessRunnerTests`).
private final class InMemoryWriter: RunLogWriting {
  private let lines = Mutex<[String]>([])

  func append(_ line: String) throws {
    lines.withLock { $0.append(line) }
  }

  var all: [String] { lines.withLock { $0 } }
}

/// A `language: ja` scenario whose `speak_all` output is a `.string` field —
/// so the ADR-010 Step E language-adherence check runs on the agents'
/// (English) statements.
private func makeJapaneseScenario() throws -> Scenario {
  let yaml = """
    id: lang_drift_test
    name: Lang Drift Test
    description: minimal ja scenario for the language-adherence negative control
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

/// Negative control for issue #1234: the harness must inject a real
/// `LanguageDetector`, otherwise `LLMCaller.detectLanguageMismatch` short-
/// circuits on `guard let detector` and the `language_mismatch` metric is 0 by
/// construction in every harness run.
///
/// `.serialized`: this suite constructs a real `SimulationRunner` (via the
/// default `streamFactory`), which spawns `Task` + `AsyncStream`; per
/// `.claude/rules/swift-testing-parallelism.md`, such suites serialize to avoid
/// concurrent-teardown flakes as tests are added.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct HarnessLanguageDetectorTests {
  /// Drives the DEFAULT `streamFactory` path — passing a test-supplied
  /// `streamFactory` would bypass the injection site and make this pass by
  /// construction (the exact defect being fixed). Feeds unambiguous English
  /// through a `ja` scenario and asserts the mismatch reaches the JSONL, so a
  /// silent regression to `detector == nil` fails loudly.
  @Test func englishOutputInJapaneseScenarioEmitsLanguageMismatch() async throws {
    let writer = InMemoryWriter()
    let diag = Mutex<[String]>([])
    let diagLogger = StderrEngineLogger(sink: { line in diag.withLock { $0.append(line) } })

    // ≥12 unicode scalars of unambiguous English inside the `.string`
    // `statement` field (the < 12-scalar gate skips the check as too_short).
    // Queue enough for 2 agents × 3 attempts: the mismatch only emits on the
    // 3rd, retry-exhausting attempt (LLMCaller.maxRetries = 2).
    let english = #"{"statement": "I strongly believe we should all cooperate together right now"}"#
    let runner = HarnessRunner(
      llmFactory: { MockLLMService(responses: Array(repeating: english, count: 8)) },
      writer: writer,
      timeoutSeconds: 10,
      diagLogger: diagLogger)

    let summary = await runner.execute(
      scenario: try makeJapaneseScenario(), runID: "lang-drift",
      startDate: "2026-07-23T00:00:00Z", modelName: "mock")

    // The mismatch does not fail the run — ADR-010 Step E: the sim continues
    // with the parsed output, structurally distinct from parse/empty failures.
    #expect(summary.status == .ok)
    // Primary negative control: the mismatch actually reached the run-log JSONL.
    #expect(writer.all.contains { $0.contains("\"event\":\"language_mismatch\"") })
    // Co-assertion (diagnostic channel, not the JSONL): the check was NOT
    // skipped as too_short. A future fixture shrink below the 12-scalar gate
    // would otherwise silently stop firing while this test still "passed".
    #expect(!diag.withLock { $0 }.contains { $0.contains("reason=too_short") })
  }
}
