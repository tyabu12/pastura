import Foundation
import Testing
import os

@testable import Pastura

/// End-to-end test for ADR-010 Step E PR2 item 5: `SimulationRunner.init(detector:)`
/// → `ExecutionContext.detector` → `PhaseContext.detector` → handler →
/// `LLMCaller.call(detector:expectedLanguage:)` → `.languageMismatch` event
/// emitted into the runner's `AsyncStream`. Verifies the full plumbing path
/// without bypassing any layer.
///
/// Sibling extension per testing.md's 400-line-cap pattern (the parent
/// `SimulationRunnerTests` already carries `// swiftlint:disable file_length`).
extension SimulationRunnerTests {
  /// Stubbed detector that always returns the canned ISO code, regardless
  /// of input. Mirrors the test fixture in `LLMCallerLanguageAdherenceTests`
  /// — duplicated rather than shared because handler-level integration
  /// tests are isolated from `LLMCaller`-unit-test internals.
  fileprivate final class FixedLanguageDetector: LanguageDetector, @unchecked Sendable {
    let verdict: String?
    init(verdict: String?) { self.verdict = verdict }
    func detect(text: String) -> String? { verdict }
  }

  @Test func runnerEmitsLanguageMismatchEventWhenDetectorConfigured() async throws {
    // 2 agents — Alice exhausts (3 wrong responses), Bob immediately on
    // attempt 1 with correct-language output. Total responses: 4. Adherence
    // retry on Alice → exhausts → `.languageMismatch` event + `.agentOutput`
    // still delivered; Bob's path tests that a single agent's adherence
    // failure doesn't poison the next agent.
    let wrong = #"{"statement": "ja-language statement long enough to pass the min-length gate"}"#
    let correct = #"{"statement": "en-language statement long enough to pass the min-length gate"}"#
    let mock = MockLLMService(responses: [wrong, wrong, wrong, correct])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      language: "en",
      rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])]
    )

    // Verdict queue: 3 "ja" for Alice's 3 attempts, then "en" for Bob.
    final class SequencedDetector: LanguageDetector, @unchecked Sendable {
      private let lock = OSAllocatedUnfairLock<[String?]>(initialState: [])
      init(verdicts: [String?]) { lock.withLock { $0 = verdicts } }
      func detect(text: String) -> String? {
        lock.withLock { queue in
          queue.isEmpty ? nil : queue.removeFirst()
        }
      }
    }
    let detector = SequencedDetector(verdicts: ["ja", "ja", "ja", "en"])
    let runner = SimulationRunner(detector: detector)
    let events = await collectAllEvents(
      runner.run(scenario: scenario, llm: mock, suspendController: SuspendController()))

    let mismatchEvents = events.compactMap { event -> SimulationEvent? in
      if case .languageMismatch = event { return event }
      return nil
    }
    #expect(
      mismatchEvents.count == 1, "Expected one .languageMismatch event from Alice's exhaustion")
    if case .languageMismatch(let agent, let detected, let expected) = mismatchEvents.first! {
      #expect(agent == "Alice")
      #expect(detected == "ja")
      #expect(expected == "en")
    }

    let outputEvents = events.compactMap { event -> SimulationEvent? in
      if case .agentOutput = event { return event }
      return nil
    }
    #expect(outputEvents.count == 2, "Sim continues — both Alice & Bob's .agentOutput delivered")
    #expect(mock.generateCallCount == 4, "Alice 3 attempts (exhausted) + Bob 1 attempt")

    // Simulation reaches completion (not blocked by the mismatch).
    #expect(events.contains { if case .simulationCompleted = $0 { true } else { false } })
  }

  @Test func runnerWithoutDetectorSkipsAdherenceCheck() async throws {
    // Default `SimulationRunner()` has no detector — back-compat path,
    // wrong-language output passes through without retry / event.
    let wrong = #"{"statement": "ja-language statement long enough to pass the min-length gate"}"#
    let mock = MockLLMService(responses: [wrong, wrong])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      language: "en",
      rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])]
    )

    let runner = SimulationRunner()  // no detector
    let events = await collectAllEvents(
      runner.run(scenario: scenario, llm: mock, suspendController: SuspendController()))

    #expect(
      !events.contains { if case .languageMismatch = $0 { true } else { false } },
      "No detector → no adherence check → no event"
    )
    #expect(mock.generateCallCount == 2, "One call per agent, no retry path consumed")
  }
}
