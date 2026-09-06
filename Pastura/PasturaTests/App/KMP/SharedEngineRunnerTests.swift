import PasturaSharedEngine
import Synchronization
import Testing

@testable import Pastura

/// The Swift half of ADR-023 §5.2 invariant 3, tested where it is
/// deterministic.
///
/// `SimulationEngine.run` launches the run loop before returning the handle, so
/// a `.suspended` terminal can drive the relay while `SharedEngineRunner` has
/// not stored the handle yet. An end-to-end test cannot force that interleave
/// — it can only sample whatever the scheduler gives it — but the box that
/// closes it is a plain object, so the window can be reproduced exactly by
/// signalling before `store`.
///
/// The same reasoning covers ``RelayTaskBox``'s terminated flag, tested below,
/// and the §5.1 early-termination clause — a consumer walking away must reach
/// the *far* end of the cancellation chain, which is asserted here through a
/// real Kotlin run rather than through a box.
///
/// App-target twin of the `RunHandleBoxLatchTests` suite in
/// `tools/kmp-gate-spike/Tests/KMPGateSpikeTests/BoundaryContractTests.swift`,
/// which the nightly gate-spike rung keeps running until S5-5.
/// `.serialized`: the cancellation test drives a real Kotlin run and spawns
/// `Task` + `AsyncStream` teardown, which
/// `.claude/rules/swift-testing-parallelism.md` keeps off the parallel path.
@Suite("SharedEngineRunner boxes and cancellation", .timeLimit(.minutes(1)), .serialized)
struct SharedEngineRunnerTests {

  @Test("a resume arriving before the handle is replayed, not dropped")
  func resumeBeforeStoreIsReplayed() {
    let box = RunHandleBox()
    let handle = RecordingRunHandle()

    box.notifyResumed()
    #expect(handle.resumeSignals == 0, "nothing to deliver to yet")

    box.store(handle)
    #expect(handle.resumeSignals == 1, "the latched resume must fire on store")
  }

  @Test("a cancel arriving before the handle is replayed, not dropped")
  func cancelBeforeStoreIsReplayed() {
    let box = RunHandleBox()
    let handle = RecordingRunHandle()

    box.cancel()
    box.store(handle)

    #expect(handle.cancels == 1, "an early consumer break must still tear the run down")
  }

  @Test("signals arriving after the handle go straight through")
  func signalsAfterStorePassThrough() {
    let box = RunHandleBox()
    let handle = RecordingRunHandle()

    box.store(handle)
    box.notifyResumed()
    box.cancel()

    #expect(handle.resumeSignals == 1)
    #expect(handle.cancels == 1)
  }

  @Test("a latched signal fires once, not on every later store")
  func latchIsClearedOnReplay() {
    let box = RunHandleBox()
    let first = RecordingRunHandle()
    let second = RecordingRunHandle()

    box.notifyResumed()
    box.store(first)
    box.store(second)

    #expect(first.resumeSignals == 1)
    #expect(second.resumeSignals == 0, "the latch must not re-fire")
  }

  @Test("both signals latched together are replayed resume-then-cancel")
  func bothLatchedReplayInOrder() {
    // `store(_:)` documents this ordering, and a doc-stated ordering with no
    // test is exactly the assertion class this review round was convened to
    // clean up: swapping the two replay lines passes every other test here.
    let box = RunHandleBox()
    let handle = RecordingRunHandle()

    box.notifyResumed()
    box.cancel()
    box.store(handle)

    #expect(handle.log == ["llmResume", "cancel"])
  }

  // MARK: - RunHandleBox — the pause latch

  @Test("a pause arriving before the handle is replayed, not dropped")
  func pauseBeforeStoreIsReplayed() {
    // Reachable from the UI: the user taps pause while the model is still
    // loading, so `requestPause()` lands between `engine.run` launching the run
    // loop and `store` handing the handle over. Dropping it would let the run
    // walk past the very checkpoint the UI already shows as paused.
    let box = RunHandleBox()
    let handle = RecordingRunHandle()

    box.requestPause()
    #expect(handle.pauses == 0, "nothing to deliver to yet")

    box.store(handle)
    #expect(handle.pauses == 1, "the latched pause must fire on store")
    #expect(handle.unpauses == 0, "a replayed pause must not be followed by an unpause")
  }

  @Test("a pause released before the handle arrives is not replayed")
  func pauseReleasedBeforeStoreIsNotReplayed() {
    // Pause then resume inside the pre-`store` window is a round trip to the
    // same state, so the correct replay is *nothing* — replaying the pause
    // would park a run the user has already un-paused.
    let box = RunHandleBox()
    let handle = RecordingRunHandle()

    box.requestPause()
    box.releasePause()
    box.store(handle)

    #expect(handle.log.isEmpty, "a pause released before the handle must leave no trace")
  }

  @Test("pause and resume arriving after the handle go straight through")
  func pauseSignalsAfterStorePassThrough() {
    let box = RunHandleBox()
    let handle = RecordingRunHandle()

    box.store(handle)
    box.requestPause()
    box.releasePause()

    #expect(handle.log == ["pause", "unpause"])
  }

  @Test("all three signals latched together are replayed pause-resume-cancel")
  func allThreeLatchedReplayInOrder() {
    // `store(_:)` documents this ordering. Pause goes first so a run paused
    // before its handle existed stops at its first checkpoint rather than at
    // whichever one it happened to reach; cancel goes last so a run cancelled
    // while parked is released before it is torn down.
    let box = RunHandleBox()
    let handle = RecordingRunHandle()

    box.requestPause()
    box.notifyResumed()
    box.cancel()
    box.store(handle)

    #expect(handle.log == ["pause", "llmResume", "cancel"])
  }

  // MARK: - SharedEngineRunner — pause with no active run

  @Test("pause and resume with no active run are no-ops, not traps")
  func pauseWithNoActiveRunIsANoOp() {
    // `SimulationViewModel` may flip its pause flag between runs — nothing ties
    // a tap to a live Kotlin run — so the runner has to absorb both signals
    // while its box slot is empty.
    let runner = SharedEngineRunner()

    runner.pause()
    runner.resume()

    // Reaching here at all is the assertion: a force-unwrap or a precondition
    // on the empty slot would have trapped above. The trailing pause proves the
    // no-op left behind no latched state a later call could trip over.
    runner.pause()
  }

  // MARK: - RelayTaskBox — the terminated flag

  @Test("a relay armed after termination is cancelled instead of stored")
  func relayArmedAfterTerminationIsCancelled() async throws {
    // The reachable shape this flag exists for: the consumer has already
    // walked away (`cancelPending`), and a backend call still in flight then
    // delivers `.suspended`, arming a relay that awaits a resume nobody will
    // send. Without the flag the task below runs its full 30 s sleep and
    // `cancelled` stays false — the `#expect` fails, not the suite `.timeLimit`
    // (the sleep is deliberately under it); the sleep length only has to
    // exceed the cancel-propagation window, not reach the limit.
    let box = RelayTaskBox()
    box.cancelPending()

    let cancelled = Mutex(false)
    let relay = Task<Void, Never> {
      do {
        try await Task.sleep(for: .seconds(30))
      } catch {
        cancelled.withLock { $0 = true }
      }
    }
    box.replace(with: relay)
    // Returns as soon as the sleep is cancelled — the assertion is that this
    // does not wait 30 s.
    await relay.value

    #expect(cancelled.withLock { $0 }, "a relay armed after termination must be cancelled at once")
  }

  // MARK: - §5.1 — early termination cancels the run

  @Test("abandoning the stream cancels the inference in flight")
  func earlyTerminationCancelsTheRun() async throws {
    let scenario = try SharedEngineFixtures.loadedPreset()
    let mock = MockLLMService(responses: SharedEngineFixtures.scriptedResponses(for: scenario))
    try await mock.loadModel()
    // Wrap mode on purpose: `BlockGate` gates `generate`, and only a wrap-mode
    // `generateStream` goes through it — a `setStreamChunks` script would sail
    // straight past the park (`LLMServiceBackendTests` says the same). The gate
    // is what makes the run *provably* mid-flight when the consumer walks away:
    // the gate-spike twin paces its script instead, and its comment explains
    // why an instant run measures nothing.
    mock.blockGenerateUntilSignal()
    let service = CancellationObservingLLMService(wrapping: mock)
    let runner = SharedEngineRunner()

    let events = runner.run(scenario: scenario, backend: LLMServiceBackend(service: service))
    // A cancelled *consumer task*, not a `break`. Two measured reasons:
    //
    //   - The run is parked at its first inference, so no further event is
    //     coming; a loop waiting for one to break on would hang instead.
    //   - `break` only terminates the stream when the last reference to it dies
    //     with the iterator. Holding it in a local `let` — which polling before
    //     consuming forces — keeps the storage alive, so `onTermination` never
    //     fires and the whole chain below is silently skipped. (Measured on
    //     iOS 26.5: a plain buffered `AsyncStream` broken out of while a local
    //     binding survives reports no termination at all.) Cancelling the
    //     consumer fires `onTermination(.cancelled)` regardless of references,
    //     and is the same shape `RelayTaskBox`'s doc comment describes.
    let consumer = Task { for await _ in events {} }
    // 20 s each, not the 30 s default: two sequential polls at 30 s would trip
    // the 1-minute `.timeLimit` on a real regression and discard the
    // `Issue.record` message this test exists to produce.
    try await pollUntilBackendCondition(timeout: .seconds(20)) { service.parkedCalls >= 1 }
    consumer.cancel()

    // The gate is deliberately NOT released before the assertion.
    // `RunHandle.cancel()` only *requests* the Kotlin job stop, so the far end
    // of the chain arrives a few hops later; unblocking first lets the parked
    // `generate` return a scripted answer and the call complete normally in
    // that window — measured, and it makes the test pass through the
    // uncancelled path. Cancellation unparks the gate on its own
    // (`awaitBlockReleaseIfArmed`'s cancel handler), which is the signal being
    // observed here.
    //
    // `onTermination` → `RunHandle.cancel()` → Kotlin cancels the coroutine →
    // `invokeOnCancellation` → `StreamHandle.cancel()` → the Swift task stops.
    // Observing the *far* end of that chain is what makes this a composition
    // test rather than a "did we call cancel" test — and it is asserted as a
    // positive count, because an absence passes just as well when nothing was
    // wired at all.
    try await pollUntilBackendCondition(timeout: .seconds(20)) {
      service.observedCancellations >= 1
    }
    #expect(service.observedCancellations >= 1)

    // Teardown only: releases the gate's latch so nothing is left parked if the
    // chain above did not reach the mock.
    mock.unblockGenerate()
  }
}

/// Records what the latch delivers, **in order** — counts alone cannot express
/// `store(_:)`'s pause-then-resume-then-cancel replay claim.
///
/// The recorded names deliberately avoid reusing "resume" for two unrelated
/// signals. `RunHandle` exports both `resume()` — the *unpause* half of
/// cooperative pause control — and `notifyLLMResumed()` — the §5.2 suspension
/// relay's wakeup. An assertion reading `["resume", …]` could not say which
/// one fired, so they log as `"unpause"` and `"llmResume"`.
///
/// Plain `Sendable`, not `@unchecked`: the only stored property is a `let
/// Mutex`, so the compiler can check it. `@unchecked` here would silently
/// exempt any property a later edit adds.
nonisolated private final class RecordingRunHandle: RunHandle, Sendable {
  private let calls = Mutex<[String]>([])

  /// Delivery order, e.g. `["pause", "llmResume", "cancel"]`.
  var log: [String] { calls.withLock { $0 } }

  var pauses: Int { log.filter { $0 == "pause" }.count }
  var unpauses: Int { log.filter { $0 == "unpause" }.count }
  var resumeSignals: Int { log.filter { $0 == "llmResume" }.count }
  var cancels: Int { log.filter { $0 == "cancel" }.count }

  func pause() { calls.withLock { $0.append("pause") } }
  func resume() { calls.withLock { $0.append("unpause") } }
  func cancel() { calls.withLock { $0.append("cancel") } }
  func notifyLLMResumed() { calls.withLock { $0.append("llmResume") } }
}

/// Decorates a ``MockLLMService`` with the two observations the mock itself
/// cannot report: that a call has reached the block gate, and that a call's
/// drain ended in cancellation.
///
/// App-target analogue of the gate spike's
/// `ScriptedStreamingBackend.observedCancellations`, one layer lower: there the
/// counter sits on a Kotlin `LLMBackend`, here on a Swift `LLMService`, so the
/// real ``LLMServiceBackend`` relay is *inside* what the test observes.
///
/// `nonisolated` + `Mutex`-guarded because Kotlin drives `generateStream` from
/// `Dispatchers.Default` (`.claude/rules/swift-isolation.md` Pattern 7). Plain
/// `Sendable`, not `@unchecked`: both stored members are immutable and
/// `Sendable`, so a later `var` fails the build.
///
/// Swift twins are spelled `Pastura.X` — `PasturaSharedEngine` is imported
/// here too, so a bare `OutputSchema` / `ChatTurnMarkers` is ambiguous rather
/// than merely shadowed (`.claude/rules/kmp-interop.md` Pattern 1b).
nonisolated private final class CancellationObservingLLMService: LLMService, Sendable {
  private struct Counters {
    var entered = 0
    var cancellations = 0
  }

  private let wrapped: MockLLMService
  private let counters = Mutex(Counters())

  init(wrapping wrapped: MockLLMService) {
    self.wrapped = wrapped
  }

  /// Calls that have entered ``generateStream(system:user:schema:antiRepetitionSeeds:)``.
  ///
  /// With ``MockLLMService/blockGenerateUntilSignal()`` armed, entry *is* the
  /// park: the wrapped mock's very next move is `awaitBlockReleaseIfArmed`,
  /// which has no observable hook of its own. So this reads "a call is parked"
  /// only for a gate-armed mock — which is the only way this double is used.
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
          // Cancellation reaches a drain by two paths and only one throws
          // (``LLMServiceBackend/drain(_:into:)`` documents the same split):
          // the mock's parked `generate` rethrows `CancellationError`, but a
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
