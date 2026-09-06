// swiftlint:disable file_length
import Foundation
import PasturaSharedEngine
import Synchronization
import Testing

@testable import Pastura

/// The ADR-023 §6 **Stage-5 re-run** of the Stage-2 Pattern 6 audit, now against
/// the two adapters that actually ship: ``SharedEngineRunner`` and
/// ``LLMServiceBackend``, driven from a `@MainActor` consumer (#1647, S5-2 PR-C).
///
/// **The trap.** Under `NonisolatedNonsendingByDefault` (SE-0461) a
/// `nonisolated async` function does not hop to the global executor — it runs on
/// its **caller's**. Awaited from a `MainActor` consumer, its body runs *on the
/// MainActor*, and any synchronous blocking work inside freezes the UI. The
/// type-level `nonisolated` both adapters carry does **not** prevent this: that
/// annotation governs a member's default isolation, not which executor an
/// `async` body runs on. There is no compiler diagnostic
/// (`.claude/rules/swift-isolation.md` Pattern 6). The fix is `@concurrent`.
///
/// **Audit outcome for the app-side shape.** Neither adapter needs `@concurrent`
/// today, and the reason is structural rather than lucky: both entry points —
/// `SharedEngineRunner.run(scenario:backend:)` and
/// `LLMServiceBackend.generateStream(request:callbacks:)` — are **synchronous**,
/// so neither can inherit a caller's executor. Each hands its work to a `Task {}`
/// created in a `nonisolated` lexical context, which takes no isolation and lands
/// on the global executor regardless of who called (pinned by
/// ``aTaskSpawnedFromNonisolatedSyncCodeDoesNotInherit``). That is a property of
/// the *shape*: an adapter refactor that makes either entry point `async`
/// re-opens the trap silently, and ``aPacedRunKeepsAMainActorConsumerLive`` is
/// the regression guard for exactly that.
///
/// **Parallelism caveat.** `.serialized` is **intra-suite only**
/// (`.claude/rules/swift-testing-parallelism.md`): other `PasturaTests` suites
/// still run alongside this one, and the app target has no `--no-parallel` knob
/// to exclude them. So every timing assertion here is a **ratio against a
/// control measured inside the same test**, never an absolute floor — an
/// absolute bound would encode one machine's speed and the contention of the
/// day. For the same reason the deliberate blocking probe is bounded at 100 ms:
/// it genuinely pins the MainActor, which starves neighbouring `@MainActor`
/// suites, so the blast radius is kept short.
///
/// **CI headroom** (`testing.md` § "Wall-clock test bounds need CI headroom"):
/// the paced run measured 0.78 s locally (pacing floor 2 deltas × 24
/// inferences × 10 ms ≈ 0.5 s), so even at the measured worst-case ~30× CI
/// slowdown the suite sits near ~25 s against the 1-minute `.timeLimit`
/// minimum. If a CI run approaches the cap, trim the per-delta pacing first —
/// the liveness measurement stays meaningful well below 10 ms — before
/// touching the fixture.
///
/// `Heartbeat`, `BlockingProbe`, `ThreadObservations` and friends began as
/// file-local copies of the retired gate spike's probe helpers; this is now the
/// only copy.
///
/// Kotlin twins are spelled `PasturaSharedEngine.X`, Swift ones `Pastura.X` —
/// both modules are in scope here (`.claude/rules/kmp-interop.md` Pattern 1b).
@Suite("Pattern 6 — executor inheritance (App/KMP adapters)", .timeLimit(.minutes(1)), .serialized)
struct PatternSixProbeTests {

  // MARK: - The regime, and the detector's two directions

  /// Establishes SE-0461 semantics *and* calibrates the liveness detector, in
  /// one test so the comparison is immune to machine speed.
  ///
  /// The absolute tick counts are meaningless across machines; the *ratio* is
  /// the signal. Asserting only "the blocked case ticked rarely" would pass on a
  /// machine where the heartbeat is starved for unrelated reasons.
  @Test("a nonisolated async body runs on its caller's executor unless @concurrent")
  @MainActor
  func nonisolatedAsyncInheritsItsCallersExecutor() async {
    let probe = BlockingProbe()

    // No `@concurrent`: SE-0461 keeps this on the MainActor, and its
    // synchronous sleep is then a UI freeze. This is Pattern 6, reproduced.
    let blocked = await measuringHeartbeat { await probe.blockWithoutConcurrent() }
    // `@concurrent`: same body, global executor, MainActor stays free.
    let live = await measuringHeartbeat { await probe.blockWithConcurrent() }

    // Regime check — the app-target translation of the spike's `Package.swift`
    // assertion. The spike enables `NonisolatedNonsendingByDefault` in its
    // manifest and claims that is what makes the probe representative; the app
    // target gets the same semantics from `SWIFT_APPROACHABLE_CONCURRENCY`, and
    // there is no manifest line to read. This assertion *is* the read: were the
    // build setting dropped, the body would hop off-main on its own, this flips
    // to `false`, and every other test here would still pass while measuring
    // semantics the app does not use.
    #expect(blocked.ranOnMainThread, "SE-0461 is not in effect — the target's regime drifted")
    #expect(!live.ranOnMainThread)

    // The detector fires in the failing direction, which is the only thing that
    // makes test 3's clean result meaningful.
    #expect(
      live.ticks > blocked.ticks * 5,
      "liveness detector did not discriminate: blocked=\(blocked.ticks) live=\(live.ticks)")
  }

  /// Pins the structural reason both adapters are safe today.
  ///
  /// `Task {}` inherits the **static** isolation of the context that lexically
  /// encloses it, not the dynamic executor of whoever called that context. Both
  /// adapters spawn their work from a `nonisolated` synchronous method, so the
  /// task takes no isolation — even when the call came from the MainActor.
  /// Were this to change, the drain would inherit the MainActor and every
  /// Kotlin `onChunk` would run there.
  @Test("a Task spawned from nonisolated sync code does not inherit the caller's actor")
  @MainActor
  func aTaskSpawnedFromNonisolatedSyncCodeDoesNotInherit() async {
    let probe = BlockingProbe()
    #expect(await probe.spawnFromSyncContext().value == false)
  }

  // MARK: - The adapters under a MainActor consumer

  /// The probe proper: a `MainActor` consumer drains a **paced** real run —
  /// bundled preset, Kotlin engine, `LLMServiceBackend` over a Swift
  /// `LLMService` — end to end.
  @Test("a paced run keeps a MainActor consumer live and never calls back on it")
  @MainActor
  func aPacedRunKeepsAMainActorConsumerLive() async throws {
    let scenario = try SharedEngineFixtures.loadedPreset()
    let answers = SharedEngineFixtures.scriptedResponses(for: scenario)
    let mock = MockLLMService(responses: answers)
    try await mock.loadModel()
    // Streaming mode: with stream chunks configured `generate()` is never
    // reached, and an under-supplied array throws `streamChunks exhausted`
    // rather than hanging — so the count comes from the fixture's own
    // `expectedInferenceCount` rather than from a guess.
    #expect(answers.count == SharedEngineFixtures.expectedInferenceCount(for: scenario))
    mock.setStreamChunks(answers.map(splitIntoDeltas))

    let observations = ThreadObservations()
    // Pacing is the load-bearing part, and it has to live in a decorator:
    // `MockLLMService` has no delay hook. An instantly-draining script finishes
    // before a frozen MainActor could be caught at it, so an unpaced version of
    // this test would pass against an adapter that *did* freeze the UI.
    let paced = PacedLLMService(wrapping: mock)
    let backend = ThreadObservingBackend(
      wrapping: LLMServiceBackend(service: paced), recordingInto: observations)
    let runner = SharedEngineRunner()

    // Control first: how fast does the heartbeat tick on THIS machine, right
    // now, with nothing of ours competing? An absolute floor cannot answer that
    // — it encodes one machine's speed and one day's contention, and this
    // suite shares the bundle with every other `PasturaTests` suite.
    let control = Heartbeat()
    control.start()
    let controlStart = ContinuousClock.now
    try await Task.sleep(for: .milliseconds(100))
    let controlRate = Double(control.stop()) / (ContinuousClock.now - controlStart).seconds

    let heartbeat = Heartbeat()
    heartbeat.start()
    let runStart = ContinuousClock.now
    var events: [PasturaSharedEngine.SimulationEvent] = []
    for await event in runner.run(scenario: scenario, backend: backend) {
      events.append(event)
    }
    let runElapsed = ContinuousClock.now - runStart
    let ticks = heartbeat.stop()
    let runRate = Double(ticks) / runElapsed.seconds

    // Emitted so the measurement record survives in the xcodebuild log — the
    // `#expect` messages only appear on failure, and the point of a ratio
    // assertion is that its margin can be checked against real spread.
    print(
      "PatternSixProbe rates: controlRate=\(controlRate)/s runRate=\(runRate)/s "
        + "ticks=\(ticks) elapsed=\(runElapsed)")

    if let failure = events.last as? PasturaSharedEngine.SimulationEvent.ErrorEvent {
      Issue.record("the run ended in ErrorEvent: \(failure.error)")
    }
    // `SimulationCompleted` *specifically*: `isTerminal` is also true for
    // `ErrorEvent`, so asserting terminality would pass on a failed run — and a
    // run that died early is exactly the shape that would trivially satisfy the
    // liveness assertion below.
    #expect(events.last is PasturaSharedEngine.SimulationEvent.SimulationCompleted)

    // Guard against a vacuous pass: zero observations would satisfy the
    // main-thread assertion below while proving the boundary was never crossed.
    #expect(observations.total > 0)
    #expect(
      observations.onMainThread == 0,
      "\(observations.onMainThread)/\(observations.total) backend callbacks ran on the MainActor")

    // Liveness, as a fraction of this machine's own idle rate. Contention
    // scales both measurements, which is exactly the property an absolute floor
    // lacks.
    //
    // Scope, stated rather than implied: at `/10` this catches a **total**
    // freeze — the Pattern 6 shape, where a synchronous blocking body holds the
    // MainActor for the whole call, driving the ratio to ~0 (test 1 pins that
    // direction). A run stalled for up to ~90% of its duration would still
    // pass. The threshold is loose on purpose: a healthy run measures ~1x the
    // control, so the margin absorbs the contention of the other suites this
    // one runs beside.
    #expect(
      runRate > controlRate / 10,
      """
      MainActor was starved during the run: \(ticks) ticks over \(runElapsed) \
      (\(runRate)/s) against an idle control of \(controlRate)/s
      """)
  }
}

// MARK: - Helpers

/// Splits one scripted answer into two deltas.
///
/// The pacing decorator sleeps *between* chunks, so a single-delta script would
/// pace nothing. Splitting also exercises Kotlin `LLMCaller`'s cross-delta
/// accumulation as a side effect.
private func splitIntoDeltas(_ answer: String) -> [String] {
  let midpoint = answer.index(answer.startIndex, offsetBy: answer.count / 2)
  return [String(answer[answer.startIndex..<midpoint]), String(answer[midpoint...])]
}

/// A `MainActor` counter driven by a self-rescheduling task — the liveness
/// detector.
///
/// It advances only while the MainActor is free to run its queue, so
/// synchronous work occupying the MainActor shows up directly as missing ticks.
@MainActor
private final class Heartbeat {
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

  /// Stops beating and returns the count.
  @discardableResult
  func stop() -> Int {
    task?.cancel()
    task = nil
    return ticks
  }
}

/// Runs `body` while a heartbeat beats, reporting both the executor `body`
/// landed on and how live the MainActor stayed.
@MainActor
private func measuringHeartbeat(
  _ body: () async -> Bool
) async -> (ranOnMainThread: Bool, ticks: Int) {
  let heartbeat = Heartbeat()
  heartbeat.start()
  let ranOnMainThread = await body()
  return (ranOnMainThread, heartbeat.stop())
}

/// Blocks synchronously, then reports which thread it blocked.
///
/// A sync helper rather than an inline `Thread.sleep`: both `Thread.sleep` and
/// `Thread.isMainThread` are unavailable from an `async` context. That is not a
/// workaround — it is the shape of the real hazard, which is always a
/// *synchronous* call (`llama_decode`, a multi-GB model load) reached from an
/// `async` body.
///
/// 100 ms rather than the spike's 200 ms: this suite runs inside the parallel
/// `PasturaTests` bundle, where a deliberate MainActor pin starves every
/// neighbouring `@MainActor` suite for its whole duration. Halving it halves
/// that blast radius while leaving the blocked/live ratio far above the 5x the
/// calibration asserts.
nonisolated private func blockAndReportThread(for seconds: TimeInterval = 0.1) -> Bool {
  Thread.sleep(forTimeInterval: seconds)
  return Thread.isMainThread
}

nonisolated private func runningOnMainThread() -> Bool { Thread.isMainThread }

/// The two spellings of the same blocking body, differing only in `@concurrent`.
nonisolated private final class BlockingProbe: Sendable {
  /// Inherits the caller's executor (SE-0461).
  func blockWithoutConcurrent() async -> Bool {
    blockAndReportThread()
  }

  /// Forced onto the global concurrent executor regardless of caller.
  @concurrent func blockWithConcurrent() async -> Bool {
    blockAndReportThread()
  }

  /// Mirrors how both adapters hand off work: a `Task` created in a
  /// `nonisolated` **synchronous** method.
  func spawnFromSyncContext() -> Task<Bool, Never> {
    Task { runningOnMainThread() }
  }
}

/// Tallies which thread the backend delivered its callbacks on.
nonisolated private final class ThreadObservations: Sendable {
  private struct Counts {
    var total = 0
    var onMain = 0
  }

  private let state = Mutex(Counts())

  var total: Int { state.withLock { $0.total } }
  var onMainThread: Int { state.withLock { $0.onMain } }

  func record() {
    let onMain = runningOnMainThread()
    state.withLock {
      $0.total += 1
      if onMain { $0.onMain += 1 }
    }
  }
}

/// Wraps a backend so every callback it delivers is thread-sampled.
///
/// Deliberately test-side: the observation is a property of the *seam*, and
/// baking a thread counter into the permanent adapter would add production
/// state that only this probe reads.
///
/// `@unchecked` (unlike ``PacedLLMService``'s plain `Sendable`) because the
/// stored `any PasturaSharedEngine.LLMBackend` is a K/N-exported Obj-C
/// protocol carrying no `Sendable` conformance for the compiler to check
/// (`.claude/rules/kmp-interop.md` Pattern 1); both stored members are
/// immutable `let`s — do not add mutable state under this annotation.
nonisolated private final class ThreadObservingBackend: PasturaSharedEngine.LLMBackend,
  @unchecked Sendable {
  private let wrapped: any PasturaSharedEngine.LLMBackend
  private let observations: ThreadObservations

  init(
    wrapping wrapped: any PasturaSharedEngine.LLMBackend,
    recordingInto observations: ThreadObservations
  ) {
    self.wrapped = wrapped
    self.observations = observations
  }

  /// Forwarded, not defaulted: Kotlin reads this to strip chat-template markers,
  /// and answering with the protocol default would change what the wrapped
  /// backend advertises.
  var knownTurnMarkers: [PasturaSharedEngine.ChatTurnMarkers] { wrapped.knownTurnMarkers }

  func generateStream(
    request: PasturaSharedEngine.GenerationRequest,
    callbacks: any PasturaSharedEngine.StreamCallbacks
  ) -> any PasturaSharedEngine.StreamHandle {
    wrapped.generateStream(
      request: request,
      callbacks: ThreadObservingCallbacks(forwardingTo: callbacks, recordingInto: observations))
  }
}

/// Forwards every callback untouched, sampling the calling thread first.
///
/// `@unchecked` for the same reason as ``ThreadObservingBackend``: the stored
/// `any PasturaSharedEngine.StreamCallbacks` existential carries no checkable
/// `Sendable`; both members are immutable `let`s.
nonisolated private final class ThreadObservingCallbacks: PasturaSharedEngine.StreamCallbacks,
  @unchecked Sendable {
  private let wrapped: any PasturaSharedEngine.StreamCallbacks
  private let observations: ThreadObservations

  init(
    forwardingTo wrapped: any PasturaSharedEngine.StreamCallbacks,
    recordingInto observations: ThreadObservations
  ) {
    self.wrapped = wrapped
    self.observations = observations
  }

  func onChunk(delta: String, isFinal: Bool, completionTokens: KotlinInt?) {
    observations.record()
    wrapped.onChunk(delta: delta, isFinal: isFinal, completionTokens: completionTokens)
  }

  func onTerminal(status: any PasturaSharedEngine.TerminalStatus) {
    observations.record()
    wrapped.onTerminal(status: status)
  }
}

/// Decorates a ``MockLLMService`` so its stream arrives **paced** — a 10 ms gap
/// between deltas.
///
/// The mock has no delay hook of its own, and pacing is what makes the liveness
/// measurement mean anything: a script that drains instantly finishes before a
/// frozen MainActor could be observed at all.
///
/// Same shape as `SharedEngineRunnerTests`'s `CancellationObservingLLMService`,
/// including why: `nonisolated` because Kotlin drives the wrapping backend from
/// `Dispatchers.Default` (`.claude/rules/swift-isolation.md` Pattern 7), and
/// plain `Sendable` rather than `@unchecked` because the single stored member is
/// an immutable `Sendable` `let`, so a later `var` fails the build.
///
/// Swift twins are spelled `Pastura.X` — `PasturaSharedEngine` is imported here
/// too, so a bare `OutputSchema` / `ChatTurnMarkers` is ambiguous rather than
/// merely shadowed (`.claude/rules/kmp-interop.md` Pattern 1b).
nonisolated private final class PacedLLMService: LLMService, Sendable {
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

extension Duration {
  /// Wall-clock seconds as a `Double`, for rate arithmetic.
  ///
  /// `Duration` exposes only integer `components`, and the liveness assertion
  /// compares two rates rather than two raw counts — so it needs a real
  /// quotient, not a truncated one.
  fileprivate var seconds: Double {
    Double(components.seconds) + Double(components.attoseconds) / 1e18
  }
}
