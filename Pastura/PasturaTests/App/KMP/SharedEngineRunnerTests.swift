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
/// App-target twin of the `RunHandleBoxLatchTests` suite in
/// `tools/kmp-gate-spike/Tests/KMPGateSpikeTests/BoundaryContractTests.swift`,
/// which the nightly gate-spike rung keeps running until S5-5.
@Suite("run-handle latch", .timeLimit(.minutes(1)))
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

    #expect(handle.log == ["resume", "cancel"])
  }
}

/// Records what the latch delivers, **in order** — counts alone cannot express
/// `store(_:)`'s resume-before-cancel replay claim.
///
/// Plain `Sendable`, not `@unchecked`: the only stored property is a `let
/// Mutex`, so the compiler can check it. `@unchecked` here would silently
/// exempt any property a later edit adds.
nonisolated private final class RecordingRunHandle: RunHandle, Sendable {
  private let calls = Mutex<[String]>([])

  /// Delivery order, e.g. `["resume", "cancel"]`.
  var log: [String] { calls.withLock { $0 } }

  var resumeSignals: Int { log.filter { $0 == "resume" }.count }
  var cancels: Int { log.filter { $0 == "cancel" }.count }

  func pause() {}
  func resume() {}
  func cancel() { calls.withLock { $0.append("cancel") } }
  func notifyLLMResumed() { calls.withLock { $0.append("resume") } }
}
