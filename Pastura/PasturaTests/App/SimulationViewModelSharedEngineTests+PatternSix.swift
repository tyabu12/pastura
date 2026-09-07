import Foundation
import Synchronization
import Testing

@testable import Pastura

extension SimulationViewModelSharedEngineTests {

  /// Discharges the ADR-023 §6 **S5-2 deferral** (S5-2 acceptance, amended
  /// 2026-08-31): the Pattern 6 audit was to be re-run "from the real
  /// `SimulationViewModel` path once it references `App/KMP/`". S5-4 built that
  /// path, so this is the same probe as
  /// `PatternSixProbeTests.aPacedRunKeepsAMainActorConsumerLive`, step for step,
  /// but driven through the production `@MainActor` consumer:
  /// `SimulationViewModel.run` → `makeSharedRunner` → `SharedEngineRunner` →
  /// `LLMServiceBackend` → Kotlin engine.
  ///
  /// **Outcome.** No `@concurrent` is owed. Both adapter entry points —
  /// `SharedEngineRunner.run(yaml:llm:)` and
  /// `LLMServiceBackend.generateStream(request:callbacks:)` — remain
  /// **synchronous**, so neither can inherit the MainActor caller's executor
  /// (SE-0461 applies to `nonisolated async` bodies only;
  /// `.claude/rules/swift-isolation.md` Pattern 6). Each hands its work to a
  /// `Task {}` created in a `nonisolated` lexical context, which takes no
  /// isolation. That is structural, not lucky — and this test is the standing
  /// regression guard should either entry point ever go `async`, which would
  /// re-open the trap with no compiler diagnostic.
  ///
  /// **Ratio, not floor** (`.claude/rules/swift-testing-parallelism.md`):
  /// `.serialized` is intra-suite only, so the liveness assertion compares the
  /// run's heartbeat rate against an idle control measured in the same test.
  /// Contention scales both.
  @Test("a paced Kotlin run through the ViewModel keeps the MainActor live")
  func aPacedKotlinRunThroughTheViewModelKeepsTheMainActorLive() async throws {
    let env = try await makeProbeEnv()
    let (sut, observations) = (env.sut, env.observations)

    // Control first: how fast the heartbeat ticks on THIS machine right now,
    // with nothing of ours competing.
    let control = ProbeHeartbeat()
    control.start()
    let controlStart = ContinuousClock.now
    try await Task.sleep(for: .milliseconds(100))
    let controlRate = Double(control.stop()) / (ContinuousClock.now - controlStart).secondsValue

    let heartbeat = ProbeHeartbeat()
    heartbeat.start()
    let runStart = ContinuousClock.now
    await sut.run(scenario: env.scenario, llm: env.llm, yamlDefinition: env.yaml)
    let runElapsed = ContinuousClock.now - runStart
    let ticks = heartbeat.stop()
    let runRate = Double(ticks) / runElapsed.secondsValue

    // Emitted so the measurement survives in the xcodebuild log — `#expect`
    // messages only appear on failure, and a ratio assertion's margin is only
    // checkable against real spread.
    print(
      "PatternSixProbe(VM) rates: controlRate=\(controlRate)/s runRate=\(runRate)/s "
        + "ticks=\(ticks) elapsed=\(runElapsed)")

    #expect(sut.isCompleted)
    #expect(sut.errorMessage == nil)

    // Guard against a vacuous pass: zero observations would satisfy the
    // main-thread assertion while proving the boundary was never crossed.
    #expect(observations.total > 0)
    #expect(
      observations.onMainThread == 0,
      "\(observations.onMainThread)/\(observations.total) LLM entries ran on the MainActor")

    // Liveness as a fraction of this machine's own idle rate. At `/10` this
    // catches a **total** freeze — the Pattern 6 shape — while leaving margin
    // for the contention of the other suites this one runs beside.
    #expect(
      runRate > controlRate / 10,
      """
      MainActor was starved during the run: \(ticks) ticks over \(runElapsed) \
      (\(runRate)/s) against an idle control of \(controlRate)/s
      """)
  }
}

// MARK: - Helpers
//
// `ProbeHeartbeat`, `ProbeThreadObservations`, `PacingProbeLLMService` and
// `splitAnswerIntoProbeDeltas` below are deliberate copies of the same-shaped
// helpers in `App/KMP/PatternSixProbeTests.swift`, renamed because the
// originals are `private` to that file. Hoisting them into a shared helper file
// would couple two suites meant to move independently — the sibling probe
// measures the adapters directly, this one measures them through the ViewModel
// — so the duplication is the cheaper of the two costs.

/// The probe's fixture — the sibling suite's `makeEnv(flagOn: true)` shape,
/// re-created here because that one is `private` to its file, with the paced +
/// thread-observing `LLMService` decorators this probe needs on top.
private struct ProbeEnv {
  let sut: SimulationViewModel
  let scenario: Pastura.Scenario
  let yaml: String
  let llm: any LLMService
  let observations: ProbeThreadObservations
}

@MainActor
private func makeProbeEnv() async throws -> ProbeEnv {
  let db = try DatabaseManager.inMemory()
  let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
  let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
  let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)

  let yaml = try SharedEngineFixtures.presetYaml()
  let scenario = try ScenarioLoader().load(yaml: yaml)
  try scenarioRepo.save(
    ScenarioRecord(
      id: scenario.id, name: scenario.name, yamlDefinition: yaml,
      isPreset: true, createdAt: Date(), updatedAt: Date()))

  let kotlinScenario = try SharedEngineFixtures.loadedPreset()
  let answers = SharedEngineFixtures.scriptedResponses(for: kotlinScenario)
  let mock = MockLLMService(responses: answers)
  try await mock.loadModel()
  // Streaming mode: with stream chunks configured `generate()` is never
  // reached, and an under-supplied array throws rather than hanging — so the
  // count comes from the fixture rather than from a guess.
  #expect(answers.count == SharedEngineFixtures.expectedInferenceCount(for: kotlinScenario))
  mock.setStreamChunks(answers.map(splitAnswerIntoProbeDeltas))

  // The ViewModel constructs `LLMServiceBackend` internally, so the seam is not
  // reachable for a backend-level decorator the way the sibling probe wraps it.
  // Sampling at the `LLMService` level observes the same executor: Kotlin calls
  // the backend, which calls straight into this decorator.
  let observations = ProbeThreadObservations()
  let llm = ThreadObservingLLMService(
    wrapping: PacingProbeLLMService(wrapping: mock), recordingInto: observations)

  let sut = SimulationViewModel(
    makeSharedRunner: { SharedEngineRunner(suspendController: $0) },
    simulationRepository: simRepo,
    turnRepository: turnRepo
  )
  sut.speed = .instant
  return ProbeEnv(
    sut: sut, scenario: scenario, yaml: yaml, llm: llm, observations: observations)
}

/// Splits one scripted answer into two deltas, so the pacing decorator (which
/// sleeps *between* chunks) has something to pace.
private func splitAnswerIntoProbeDeltas(_ answer: String) -> [String] {
  let midpoint = answer.index(answer.startIndex, offsetBy: answer.count / 2)
  return [String(answer[answer.startIndex..<midpoint]), String(answer[midpoint...])]
}

nonisolated private func probeRunningOnMainThread() -> Bool { Thread.isMainThread }

/// A `MainActor` counter driven by a self-rescheduling task — the liveness
/// detector. It advances only while the MainActor is free to run its queue.
@MainActor
private final class ProbeHeartbeat {
  private var ticks = 0
  private var task: Task<Void, Never>?

  func start() {
    task = Task { @MainActor in
      while !Task.isCancelled {
        ticks += 1
        try? await Task.sleep(for: .milliseconds(1))
      }
    }
  }

  @discardableResult
  func stop() -> Int {
    task?.cancel()
    task = nil
    return ticks
  }
}

/// Tallies which thread the LLM seam was entered on.
nonisolated private final class ProbeThreadObservations: Sendable {
  private struct Counts {
    var total = 0
    var onMain = 0
  }

  private let state = Mutex(Counts())

  var total: Int { state.withLock { $0.total } }
  var onMainThread: Int { state.withLock { $0.onMain } }

  func record() {
    let onMain = probeRunningOnMainThread()
    state.withLock {
      $0.total += 1
      if onMain { $0.onMain += 1 }
    }
  }
}

/// Paces a wrapped service's stream — a 10 ms gap between deltas.
///
/// Pacing is what makes the liveness measurement mean anything: a script that
/// drains instantly finishes before a frozen MainActor could be observed at
/// all, so an unpaced version of this test would pass against an adapter that
/// *did* freeze the UI. `nonisolated` because Kotlin drives the wrapping
/// backend from `Dispatchers.Default` (`swift-isolation.md` Pattern 7).
nonisolated private final class PacingProbeLLMService: LLMService, Sendable {
  private let wrapped: MockLLMService

  init(wrapping wrapped: MockLLMService) {
    self.wrapped = wrapped
  }

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
    let inner = wrapped.generateStream(
      system: system, user: user, schema: schema, antiRepetitionSeeds: antiRepetitionSeeds)
    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for try await chunk in inner {
            try await Task.sleep(for: .milliseconds(10))
            continuation.yield(chunk)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

/// Samples the calling thread at every seam entry and on every chunk forwarded.
///
/// Test-side on purpose: the observation is a property of the seam, and baking
/// a thread counter into the production adapter would add state only this probe
/// reads.
nonisolated private final class ThreadObservingLLMService: LLMService, Sendable {
  private let wrapped: PacingProbeLLMService
  private let observations: ProbeThreadObservations

  init(
    wrapping wrapped: PacingProbeLLMService, recordingInto observations: ProbeThreadObservations
  ) {
    self.wrapped = wrapped
    self.observations = observations
  }

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
    observations.record()
    return try await wrapped.generate(
      system: system, user: user, schema: schema, antiRepetitionSeeds: antiRepetitionSeeds)
  }

  func generateStream(
    system: String, user: String, schema: Pastura.OutputSchema?,
    antiRepetitionSeeds: [String]
  ) -> AsyncThrowingStream<LLMStreamChunk, Error> {
    observations.record()
    let inner = wrapped.generateStream(
      system: system, user: user, schema: schema, antiRepetitionSeeds: antiRepetitionSeeds)
    let observations = observations
    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for try await chunk in inner {
            observations.record()
            continuation.yield(chunk)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

extension Duration {
  /// Wall-clock seconds as a `Double`, for rate arithmetic — `Duration` exposes
  /// only integer `components`, and this file compares two rates.
  fileprivate var secondsValue: Double {
    Double(components.seconds) + Double(components.attoseconds) / 1e18
  }
}
