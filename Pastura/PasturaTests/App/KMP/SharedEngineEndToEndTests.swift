import Foundation
import PasturaSharedEngine
import Synchronization
import Testing

@testable import Pastura

/// S5-2 PR-B acceptance for the **whole** Stage-5 boundary: a bundled preset
/// parsed by Kotlin's `ScenarioLoader`, run by Kotlin's `SimulationEngine`
/// through ``SharedEngineRunner``'s three injected seams, answered by a Swift
/// `LLMService` behind ``LLMServiceBackend`` (ADR-023 §5, #1647).
///
/// The per-adapter suites next door (`SeamBridgeTests`, `LLMServiceBackendTests`)
/// call each bridge directly, which is the right shape for an enum mapping but
/// proves nothing about *wiring*: an adapter that is never handed to the engine
/// passes every one of them. This suite is the wiring assertion — it fails if
/// `SharedEngineRunner` drops a seam on the floor.
///
/// It is also `PasturaSharedEngine.ScenarioLoader`'s first caller anywhere in
/// the app: nothing in `shared/engine` calls it, so until now a YAML shape the
/// Swift loader accepts and the Kotlin one rejects had no detector.
///
/// Kotlin twins are spelled `PasturaSharedEngine.X`, Swift ones `Pastura.X` —
/// both modules are in scope here, so a bare name is ambiguous rather than
/// merely shadowed (`.claude/rules/kmp-interop.md` Pattern 1b).
@Suite("Kotlin engine end-to-end", .timeLimit(.minutes(1)))
struct SharedEngineEndToEndTests {

  @Test("a bundled preset runs to SimulationCompleted through the injected seams")
  func bundledPresetRunsToCompletion() async throws {
    let scenario = try SharedEngineFixtures.loadedPreset()
    let expectedCalls = SharedEngineFixtures.expectedInferenceCount(for: scenario)
    let mock = MockLLMService(responses: SharedEngineFixtures.scriptedResponses(for: scenario))
    try await mock.loadModel()

    let recorder = RecordingEngineLogger()
    // Wrapping the *production* detector rather than a stub: what is under test
    // is that the seam is reached at all, and a stub would leave open whether
    // the real concrete still satisfies the Kotlin protocol.
    let detector = CountingLanguageDetector(wrapping: NLLanguageDetector())
    let runner = SharedEngineRunner(
      detector: LanguageDetectorBridge(detector: detector),
      logger: EngineLoggerBridge(logger: recorder),
      random: PasturaSharedEngine.SystemRandomSource())

    var events: [PasturaSharedEngine.SimulationEvent] = []
    for await event in runner.run(
      scenario: scenario, backend: LLMServiceBackend(service: mock)) {
      events.append(event)
    }

    // Printed rather than merely asserted away: an `ErrorEvent` terminal makes
    // every other assertion below trivially explicable, and the payload names
    // which preflight rule or turn failed.
    if let failure = events.last as? PasturaSharedEngine.SimulationEvent.ErrorEvent {
      Issue.record("the run ended in ErrorEvent: \(failure.error)")
    }
    // `SimulationCompleted` *specifically*: `isTerminal` is also true for
    // `ErrorEvent`, so asserting terminality would pass on a failed run.
    #expect(events.last is PasturaSharedEngine.SimulationEvent.SimulationCompleted)

    // A completed run that emitted no turn is a preflight rejection wearing a
    // success terminal — the engine has to have produced agent output.
    let agentOutputs = events.filter { $0 is PasturaSharedEngine.SimulationEvent.AgentOutput }
    #expect(agentOutputs.count == expectedCalls)

    // The Swift service really answered: `MockLLMService` counts `generate`
    // calls, which is the path `LLMServiceBackend`'s wrap mode takes.
    #expect(mock.generateCallCount == expectedCalls)

    // The detector seam is live. Asserted instead of the logger's line count
    // because the Kotlin engine logs nothing on a clean run — every
    // `logger.log` call site in `LLMCaller` is a parse failure, a retry, a
    // repair, a template-token leak or a skipped language check — so
    // `recorder.lines.isEmpty` is the *expected* happy-path shape and would
    // make a logger assertion vacuous.
    #expect(detector.callCount > 0)
    #expect(recorder.lines.isEmpty, "a clean run logs nothing; a non-empty log means a retry ran")
  }

  @Test("malformed YAML crosses the K/N boundary as a Swift error, not a crash")
  func malformedYamlThrows() throws {
    // Pattern 5: `load(yaml:)` carries `@Throws`, so the Kotlin
    // `SimulationException` imports as a Swift `throws` instead of terminating
    // the process. This test reaching its assertion at all is half the claim.
    #expect(throws: (any Error).self) {
      _ = try PasturaSharedEngine.ScenarioLoader().load(yaml: "agents: [")
    }

    do {
      _ = try PasturaSharedEngine.ScenarioLoader().load(yaml: "agents: [")
      Issue.record("the Kotlin loader accepted malformed YAML")
    } catch {
      // K/N wraps the Kotlin throwable in an `NSError` under this key; pinning
      // the concrete type keeps a future un-annotated sibling from degrading
      // into a generic error while this test still passes.
      let boxed = (error as NSError).userInfo["KotlinException"]
      #expect(boxed is PasturaSharedEngine.SimulationException)
    }
  }
}

// MARK: - Test doubles

/// Counts how many times Kotlin consulted the detector, forwarding to the real
/// one.
///
/// `nonisolated` + `Mutex`-guarded: `LanguageDetector.detect` is called from
/// `Dispatchers.Default`, so unlike the direct-call doubles in
/// `SeamBridgeTests` this one genuinely runs off the main actor
/// (`.claude/rules/swift-isolation.md` Pattern 7).
nonisolated final class CountingLanguageDetector: Pastura.LanguageDetector, Sendable {
  private let wrapped: any Pastura.LanguageDetector
  private let calls = Mutex(0)

  var callCount: Int { calls.withLock { $0 } }

  init(wrapping wrapped: any Pastura.LanguageDetector) {
    self.wrapped = wrapped
  }

  func detect(text: String) -> String? {
    calls.withLock { $0 += 1 }
    return wrapped.detect(text: text)
  }
}
