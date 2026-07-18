import Foundation
import PasturaSharedEngine
import Synchronization
import Testing

@testable import KMPGateSpike

/// The Pattern 6 probe — `.claude/rules/swift-isolation.md`'s only *silent*
/// isolation trap, and the named late-failure risk for the two ADR-023 §10
/// boundary adapters.
///
/// **The trap.** Under `NonisolatedNonsendingByDefault` (SE-0461) a
/// `nonisolated async` function does not hop to the global executor — it runs on
/// its **caller's** executor. Awaited from a `MainActor` consumer, its body runs
/// *on the MainActor*, and any synchronous blocking work inside freezes the UI.
/// The type-level `nonisolated` both adapters carry does **not** prevent this:
/// that annotation governs a member's default isolation, not which executor an
/// `async` body runs on. There is no compiler diagnostic. The fix is
/// `@concurrent`.
///
/// **Why this suite exists rather than an inspection.** Two claims stand between
/// "the adapters look fine" and "the adapters are fine", and neither is
/// checkable by reading:
///
/// 1. *`Package.swift` reproduces the app's regime.* The manifest enables
///    `NonisolatedNonsendingByDefault` and asserts that this is what makes the
///    probe representative. Nothing executed that assertion until
///    ``nonisolatedAsyncInheritsItsCallersExecutor`` — and had the setting been
///    dropped, every other test here would still pass while measuring semantics
///    the app does not use.
/// 2. *The adapters keep their work off the MainActor.* Asserted by
///    ``aPacedRunKeepsAMainActorConsumerLive``, whose detector is only
///    trustworthy because test 1 shows it also fires in the failing direction.
///
/// **Audit outcome (item 6's second half).** Neither adapter needs `@concurrent`
/// today, and the reason is structural rather than lucky. Both entry points —
/// `SharedEngineRunner.run` and `ScriptedStreamingBackend.generateStream` — are
/// **synchronous**, so neither can inherit a caller's executor; each hands its
/// work to a `Task {}` created in a `nonisolated` lexical context, which takes
/// no isolation and lands on the global executor regardless of who called
/// (pinned by ``aTaskSpawnedFromNonisolatedSyncCodeDoesNotInherit``). The one
/// `nonisolated async` body in either adapter, `ScriptedStreamingBackend.drain`,
/// is reached only from inside that `Task`, so its "caller's executor" is
/// already the global one.
///
/// This is a property of the *shape*, and the shape is what Stage 5 changes:
/// when the scripted source is replaced by `LlamaCppService.generateStream`, the
/// blocking work arriving behind that seam is the real `llama_decode` loop —
/// whose sibling `loadModelInternal` already carries `@concurrent` for exactly
/// this reason (#822). An adapter refactor that makes either entry point `async`
/// re-opens the trap silently; test 3 is the regression guard for that.
@Suite("Pattern 6 — executor inheritance", .timeLimit(.minutes(1)))
struct PatternSixProbeTests {

  // MARK: - The regime, and the detector's two directions

  /// Establishes SE-0461 semantics *and* calibrates the liveness detector, in
  /// one test so the comparison is immune to machine speed.
  ///
  /// The absolute tick counts are meaningless across CI runners; the *ratio* is
  /// the signal. Asserting only "the blocked case ticked rarely" would pass on a
  /// runner where the heartbeat is starved for unrelated reasons.
  @Test("a nonisolated async body runs on its caller's executor unless @concurrent")
  @MainActor
  func nonisolatedAsyncInheritsItsCallersExecutor() async {
    let probe = BlockingProbe()

    // No `@concurrent`: SE-0461 keeps this on the MainActor, and its
    // synchronous sleep is then a UI freeze. This is Pattern 6, reproduced.
    let blocked = await measuringHeartbeat { await probe.blockWithoutConcurrent() }
    // `@concurrent`: same body, global executor, MainActor stays free.
    let live = await measuringHeartbeat { await probe.blockWithConcurrent() }

    // Regime check. If `Package.swift` lost
    // `.enableUpcomingFeature("NonisolatedNonsendingByDefault")` this flips to
    // `false` — the body would hop off-main on its own — and the whole probe
    // would silently stop representing the app.
    #expect(blocked.ranOnMainThread, "SE-0461 is not in effect — Package.swift regime drifted")
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

  /// The probe proper: a `MainActor` consumer drains a **paced** run end to end.
  ///
  /// Pacing is the load-bearing part. An instantly-draining script finishes
  /// before a blocked MainActor could be caught at it, so an unpaced version of
  /// this test would pass against an adapter that *did* freeze the UI —
  /// `ScriptedResponse.chunkDelay` exists for this.
  @Test("a paced run keeps a MainActor consumer live and never calls back on it")
  @MainActor
  func aPacedRunKeepsAMainActorConsumerLive() async throws {
    let observations = ThreadObservations()
    let runner = SharedEngineRunner()
    let scripted = ScriptedStreamingBackend(
      responses: Array(
        repeating: .saysStreamed("turn", chunkDelay: .milliseconds(10)), count: 4))
    let backend = ThreadObservingBackend(wrapping: scripted, recordingInto: observations)

    let heartbeat = Heartbeat()
    heartbeat.start()
    var events: [SimulationEvent] = []
    for await event in runner.run(scenario: .twoSpeakAllTurns, backend: backend) {
      events.append(event)
    }
    let ticks = heartbeat.stop()

    #expect(events.last is SimulationEvent.SimulationCompleted)

    // Guard against a vacuous pass: zero observations would satisfy the
    // main-thread assertion below while proving the boundary was never crossed.
    #expect(observations.total > 0)
    #expect(
      observations.onMainThread == 0,
      "\(observations.onMainThread)/\(observations.total) backend callbacks ran on the MainActor")

    // Liveness. The floor is deliberately far below what the run's own duration
    // (4 calls × 3 paced deltas) affords — test 1 is what establishes that a
    // real freeze drives this near zero, so this only has to exclude that.
    #expect(ticks >= 10, "MainActor was starved during the run (\(ticks) ticks)")
  }
}

// MARK: - Helpers

/// A `MainActor` counter driven by a self-rescheduling task — the liveness
/// detector.
///
/// It advances only while the MainActor is free to run its queue, so
/// synchronous work occupying the MainActor shows up directly as missing ticks.
@MainActor
final class Heartbeat {
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
func measuringHeartbeat(
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
nonisolated func blockAndReportThread(for seconds: TimeInterval = 0.2) -> Bool {
  Thread.sleep(forTimeInterval: seconds)
  return Thread.isMainThread
}

nonisolated func runningOnMainThread() -> Bool { Thread.isMainThread }

/// The two spellings of the same blocking body, differing only in `@concurrent`.
nonisolated final class BlockingProbe: Sendable {
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
nonisolated final class ThreadObservations: Sendable {
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
/// state that only the gate reads.
nonisolated final class ThreadObservingBackend: LLMBackend, @unchecked Sendable {
  private let wrapped: any LLMBackend
  private let observations: ThreadObservations

  init(wrapping wrapped: any LLMBackend, recordingInto observations: ThreadObservations) {
    self.wrapped = wrapped
    self.observations = observations
  }

  func generateStream(
    request: GenerationRequest,
    callbacks: any StreamCallbacks
  ) -> any StreamHandle {
    wrapped.generateStream(
      request: request,
      callbacks: ThreadObservingCallbacks(forwardingTo: callbacks, recordingInto: observations))
  }
}

/// Forwards every callback untouched, sampling the calling thread first.
nonisolated final class ThreadObservingCallbacks: StreamCallbacks, @unchecked Sendable {
  private let wrapped: any StreamCallbacks
  private let observations: ThreadObservations

  init(forwardingTo wrapped: any StreamCallbacks, recordingInto observations: ThreadObservations) {
    self.wrapped = wrapped
    self.observations = observations
  }

  func onChunk(delta: String, isFinal: Bool, completionTokens: KotlinInt?) {
    observations.record()
    wrapped.onChunk(delta: delta, isFinal: isFinal, completionTokens: completionTokens)
  }

  func onTerminal(status: any TerminalStatus) {
    observations.record()
    wrapped.onTerminal(status: status)
  }
}

extension ScriptedResponse {
  /// A completed turn whose JSON arrives as several **paced** deltas.
  ///
  /// `ScriptedResponse.says` sends the whole object in one delta, which cannot
  /// pace a run no matter what delay it carries. Splitting it exercises
  /// `LLMCaller`'s cross-delta accumulation as a side effect.
  static func saysStreamed(_ text: String, chunkDelay: Duration) -> ScriptedResponse {
    ScriptedResponse(
      deltas: ["{\"statement\": \"", text, "\"}"],
      ending: .completed(completionTokens: nil),
      chunkDelay: chunkDelay
    )
  }
}
