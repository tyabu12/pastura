import Foundation
import PasturaSharedEngine
import Synchronization
import Testing

@testable import Pastura

/// S5-4 acceptance for the **app run path**:
/// ``SharedEngineRunner/run(yaml:llm:)`` — the overload `SimulationViewModel`
/// consumes, which parses the YAML itself and hands back
/// `AsyncStream<Pastura.SimulationEvent>` (the *Swift* enum) so the ViewModel
/// cannot tell a Kotlin run from a Swift one (ADR-023 §6 S5-4, #1681).
///
/// ``SharedEngineEndToEndTests`` next door asserts the same wiring one layer
/// lower, in Kotlin events. What is new here — and what only this suite can
/// fail on — is the two things the overload adds on top: the parse, whose
/// failure must arrive as a `.error(.scenarioValidationFailed)` carrying the
/// **Kotlin-rendered** message rather than the exception's description, and
/// the Kotlin→Swift event translation applied to every event of a real run.
///
/// Kotlin twins are spelled `PasturaSharedEngine.X`, Swift ones `Pastura.X` —
/// both modules are in scope, so a bare name is ambiguous rather than merely
/// shadowed (`.claude/rules/kmp-interop.md` Pattern 1b).
///
/// `.serialized` because a real Kotlin run is `Task` + `AsyncStream` teardown
/// (`.claude/rules/swift-testing-parallelism.md`).
@Suite("SharedEngineRunner app run path", .timeLimit(.minutes(1)), .serialized)
struct SharedEngineAppRunPathTests {

  @Test("bundled preset YAML runs to .simulationCompleted as Swift events")
  func presetYamlRunsToCompletion() async throws {
    let yaml = try SharedEngineFixtures.presetYaml()
    // Parsed a second time here purely to derive the script: the responses are
    // positional and depend on persona names and round count, which only a
    // parsed scenario supplies. The overload under test does its own parse
    // from the same YAML.
    let scenario = try SharedEngineFixtures.loadedPreset()
    let expectedCalls = SharedEngineFixtures.expectedInferenceCount(for: scenario)
    let mock = MockLLMService(responses: SharedEngineFixtures.scriptedResponses(for: scenario))
    try await mock.loadModel()

    let runner = SharedEngineRunner()
    var events: [Pastura.SimulationEvent] = []
    for await event in runner.run(yaml: yaml, llm: mock) {
      events.append(event)
    }

    // Named rather than asserted away: an `.error` terminal makes every
    // assertion below trivially explicable, and the payload says which rule or
    // turn failed.
    if case .error(let failure) = events.last {
      Issue.record("the run ended in .error: \(failure)")
    }
    #expect(events.last == .simulationCompleted)

    let agentOutputs = events.filter {
      if case .agentOutput = $0 { return true } else { return false }
    }
    let roundStarts = events.filter {
      if case .roundStarted = $0 { return true } else { return false }
    }
    #expect(agentOutputs.count == expectedCalls)
    #expect(roundStarts.count == Int(scenario.rounds))
    #expect(mock.generateCallCount == expectedCalls)
  }

  @Test("malformed YAML yields one .scenarioValidationFailed with the Kotlin-rendered message")
  func malformedYamlYieldsOneValidationError() async throws {
    // The expectation is computed from the Kotlin loader itself rather than
    // transcribed: a message reword in `ScenarioValidationMessage` must move
    // this test's *subject*, not its expected string (`kmp-interop.md`
    // Pattern 4, the dual-landed message rule).
    var rendered: String?
    do {
      _ = try PasturaSharedEngine.ScenarioLoader().load(yaml: "agents: [")
      Issue.record("the Kotlin loader accepted malformed YAML")
    } catch {
      let boxed = (error as NSError).userInfo["KotlinException"]
      let exception = try #require(boxed as? PasturaSharedEngine.SimulationException)
      let failure = try #require(
        exception.error as? PasturaSharedEngine.SimulationError.ScenarioValidationFailed)
      rendered = failure.message
    }
    let expected = try #require(rendered)

    let mock = MockLLMService(responses: [])
    let runner = SharedEngineRunner()
    var events: [Pastura.SimulationEvent] = []
    for await event in runner.run(yaml: "agents: [", llm: mock) {
      events.append(event)
    }

    #expect(events.count == 1)
    #expect(events.first == .error(.scenarioValidationFailed(expected)))
    #expect(!expected.isEmpty)
    // The naive path — `error.localizedDescription` on the bridged `NSError` —
    // renders the *exception description*, which leads with the Kotlin class
    // name. The S5-4 `ja` acceptance reads the rendered catalog message, so
    // that shape must not be what reaches the ViewModel.
    #expect(!expected.hasPrefix("SimulationException"))
    // Nothing may be inferred for a scenario that never parsed.
    #expect(mock.generateCallCount == 0)
  }

  @Test("a consumer walking away cancels the Kotlin run")
  func earlyTerminationCancelsTheRun() async throws {
    let yaml = try SharedEngineFixtures.presetYaml()
    let scenario = try SharedEngineFixtures.loadedPreset()
    let mock = MockLLMService(responses: SharedEngineFixtures.scriptedResponses(for: scenario))
    try await mock.loadModel()
    // Wrap mode on purpose: `BlockGate` gates `generate`, and only a wrap-mode
    // `generateStream` goes through it. The gate is what makes the run
    // provably mid-flight when the consumer walks away — the same reasoning as
    // `SharedEngineRunnerTests.earlyTerminationCancelsTheRun`, one layer down.
    mock.blockGenerateUntilSignal()
    let service = AppRunPathCancellationObserver(wrapping: mock)
    let runner = SharedEngineRunner()

    let events = runner.run(yaml: yaml, llm: service)
    // A cancelled consumer *task*, not a `break`: the run is parked at its
    // first inference so no event is coming to break on, and a `break` while a
    // local binding still holds the stream fires no `onTermination` at all
    // (measured on iOS 26.5 — `SharedEngineRunnerTests` records the same).
    let consumer = Task { for await _ in events {} }
    try await pollUntilBackendCondition(timeout: .seconds(20)) { service.parkedCalls >= 1 }
    consumer.cancel()

    // The gate stays latched: releasing it first lets the parked `generate`
    // return a scripted answer and the call complete through the *uncancelled*
    // path. Cancellation unparks the gate itself, which is the signal observed.
    try await pollUntilBackendCondition(timeout: .seconds(20)) {
      service.observedCancellations >= 1
    }
    #expect(service.observedCancellations >= 1)

    // Teardown only.
    mock.unblockGenerate()
  }
}

// MARK: - Test doubles

/// Counts entered and cancellation-terminated `generateStream` calls, forwarding
/// everything to a wrapped ``MockLLMService``.
///
/// A near-copy of `SharedEngineRunnerTests`' own observer, which is `private` to
/// that file. Kept private here too rather than hoisted: the two suites assert
/// different overloads, and a shared double would let either free the other's
/// meaning to change under it.
nonisolated private final class AppRunPathCancellationObserver: LLMService, Sendable {
  private struct Counters {
    var entered = 0
    var cancellations = 0
  }

  private let wrapped: MockLLMService
  private let counters = Mutex(Counters())

  init(wrapping wrapped: MockLLMService) {
    self.wrapped = wrapped
  }

  /// Calls that have entered `generateStream`. With the mock's gate armed,
  /// entry *is* the park — the mock's next move is `awaitBlockReleaseIfArmed`,
  /// which has no observable hook of its own.
  var parkedCalls: Int { counters.withLock { $0.entered } }

  /// Calls whose drain ended because the task was cancelled.
  var observedCancellations: Int { counters.withLock { $0.cancellations } }

  var isModelLoaded: Bool { wrapped.isModelLoaded }
  var modelIdentifier: String { wrapped.modelIdentifier }
  var backendIdentifier: String { wrapped.backendIdentifier }
  var knownTurnMarkers: [Pastura.ChatTurnMarkers] { wrapped.knownTurnMarkers }

  func loadModel() async throws { try await wrapped.loadModel() }
  func unloadModel() async throws { try await wrapped.unloadModel() }

  func attachSuspendController(_ controller: Pastura.SuspendController?) async {
    await wrapped.attachSuspendController(controller)
  }

  func generate(
    system: String, user: String, schema: Pastura.OutputSchema?,
    antiRepetitionSeeds: [String]
  ) async throws -> String {
    try await wrapped.generate(
      system: system, user: user, schema: schema, antiRepetitionSeeds: antiRepetitionSeeds)
  }

  func generateStream(
    system: String, user: String, schema: Pastura.OutputSchema?,
    antiRepetitionSeeds: [String]
  ) -> AsyncThrowingStream<LLMStreamChunk, Error> {
    counters.withLock { $0.entered += 1 }
    let inner = wrapped.generateStream(
      system: system, user: user, schema: schema, antiRepetitionSeeds: antiRepetitionSeeds)
    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for try await chunk in inner { continuation.yield(chunk) }
          // Cancellation reaches a drain by two paths and only one throws: the
          // mock's parked `generate` rethrows `CancellationError`, but a
          // stream cancelled between chunks simply *finishes*.
          noteCancellationIfCancelled()
          continuation.finish()
        } catch {
          noteCancellationIfCancelled(error)
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private func noteCancellationIfCancelled(_ error: (any Error)? = nil) {
    guard error is CancellationError || Task.isCancelled else { return }
    counters.withLock { $0.cancellations += 1 }
  }
}
