import PasturaSharedEngine
import Synchronization

// The two run-scoped boxes `SharedEngineRunner` closes its callback/handle
// cycle with. They sit in their own file only because that adapter is at
// SwiftLint's `file_length` cap; the gate-spike twin
// (`tools/kmp-gate-spike/Sources/KMPGateSpike/SharedEngineRunner.swift`) keeps
// them inline, which is a layout difference and not a contract one.

// Internal rather than private so the latch can be tested directly: the window
// it closes is a genuine thread race that a black-box test cannot force
// deterministically, and an untested latch is indistinguishable from a comment.
// (Placed above the doc comment, not between it and the declaration, or
// SwiftLint's `orphaned_doc_comment` fires — `.claude/rules/build-traps.md`.)
/// Holds the `RunHandle` the engine returns, so the relay and the termination
/// handler can reach it from other threads — **and latches signals that arrive
/// before it exists.**
///
/// The latch is not defensive padding. `SimulationEngine.run` launches the run
/// loop on `Dispatchers.Default` *before* returning the handle, so there is a
/// real window in which the engine is running while this box is still empty. A
/// resume dropped in that window parks the run forever, a cancel dropped in it
/// leaks the Kotlin coroutine, and a **pause** dropped in it lets the run walk
/// past the boundary the UI is already showing as paused — the user taps pause
/// during model load, the tap lands between `engine.run` and `store`, and the
/// run keeps producing turns behind a paused-looking screen. All three are
/// replayed on `store`.
///
/// `@unchecked Sendable`: all state is guarded by the mutex, and the Kotlin
/// handle's own methods are documented idempotent and thread-safe.
nonisolated final class RunHandleBox: @unchecked Sendable {
  // Boxed rather than stored bare: `Mutex.withLock` takes an `inout sending`
  // parameter, and `any RunHandle` is a Kotlin/Native protocol with no Swift
  // `Sendable` conformance — so a bare store fails with "'inout sending'
  // parameter cannot be task-isolated". A protocol cannot be given a
  // retroactive conformance, hence the wrapper.
  private struct Boxed: @unchecked Sendable {
    let value: any RunHandle
  }

  private struct State: @unchecked Sendable {
    var handle: Boxed?
    var pendingPause = false
    var pendingResume = false
    var pendingCancel = false
  }

  private let storage = Mutex(State())

  // A struct rather than a 3-tuple: SwiftLint's `large_tuple` caps tuples at
  // two members, and the sibling `ReplaceOutcome` typealias below shows why the
  // shape is named at all rather than spelled inline.
  private struct PendingSignals {
    var pause = false
    var resume = false
    var cancel = false
  }

  /// Stores the handle and replays anything that arrived before it.
  ///
  /// Replay order is pause → resume → cancel. Pause first, so a run paused
  /// before its handle existed halts at its *first* checkpoint rather than at
  /// whichever one it happened to reach while this box was empty; cancel last,
  /// so a run cancelled while parked is released and then torn down. This
  /// orders the *replay* only — a live `cancel()` racing this method can still
  /// land before the replayed `notifyLLMResumed()`. That is harmless (a resume
  /// on a cancelled `Job` is a no-op), and no stronger guarantee is claimed.
  func store(_ handle: any RunHandle) {
    let boxed = Boxed(value: handle)
    let pending: PendingSignals = storage.withLock { state in
      state.handle = boxed
      let carried = PendingSignals(
        pause: state.pendingPause, resume: state.pendingResume, cancel: state.pendingCancel)
      state.pendingPause = false
      state.pendingResume = false
      state.pendingCancel = false
      return carried
    }
    if pending.pause { handle.pause() }
    if pending.resume { handle.notifyLLMResumed() }
    if pending.cancel { handle.cancel() }
  }

  /// Requests a cooperative pause, latching if the handle has not arrived yet.
  ///
  /// Distinct from ``notifyResumed()``'s signal despite the neighbouring names:
  /// this pair drives `RunHandle.pause()` / `resume()`, the round/phase-boundary
  /// halt, while `notifyResumed` drives `notifyLLMResumed()`, the ADR-023 §5.2
  /// app-lifecycle suspension relay.
  func requestPause() {
    let handle: Boxed? = storage.withLock { state in
      if state.handle == nil { state.pendingPause = true }
      return state.handle
    }
    handle?.value.pause()
  }

  /// Releases a pause. With no handle yet this *clears* the latch rather than
  /// setting one: a pause requested and released inside the pre-`store` window
  /// is a round trip to the same state, so nothing should be replayed.
  func releasePause() {
    let handle: Boxed? = storage.withLock { state in
      if state.handle == nil { state.pendingPause = false }
      return state.handle
    }
    handle?.value.resume()
  }

  /// Releases a parked inference, latching if the handle has not arrived yet.
  func notifyResumed() {
    let handle: Boxed? = storage.withLock { state in
      if state.handle == nil { state.pendingResume = true }
      return state.handle
    }
    handle?.value.notifyLLMResumed()
  }

  /// Cancels the run, latching if the handle has not arrived yet.
  func cancel() {
    let handle: Boxed? = storage.withLock { state in
      if state.handle == nil { state.pendingCancel = true }
      return state.handle
    }
    handle?.value.cancel()
  }
}

// Internal, not private, so the terminated flag is testable — `RunHandleBox` above has the reasoning.
/// Tracks the in-flight relay task so stream termination can cancel a parked
/// one instead of leaking it — and **remembers that termination already
/// happened**, so a relay armed after that point is cancelled on arrival.
///
/// The flag is not about the pre-`store` window. The reachable path is
/// **cooperative cancellation**: a consumer breaks out of its `for await`,
/// `onTermination` fires `cancelPending()` on a box that holds nothing yet, and
/// `RunHandle.cancel()` only *requests* the Kotlin job stop — so a backend call
/// already in flight can still deliver `onTerminal(.suspended)` afterwards.
/// Without the flag that terminal installs a relay task awaiting a resume that
/// will never come, and nothing is left to cancel it: a permanently parked
/// `Task`. `BoundaryContractTests` exercises exactly this shape whenever it
/// calls `consumer.cancel()` mid-run.
///
/// (What cannot happen is the run loop emitting a terminal and *then* taking a
/// `.suspended` — `onEvent` runs synchronously on the loop's own thread and the
/// terminal is its last event.)
nonisolated final class RelayTaskBox: @unchecked Sendable {
  private struct State {
    var task: Task<Void, Never>?
    var terminated = false
  }

  private let storage = Mutex(State())

  // Named rather than spelled inline so the `withLock` closure's parameter
  // still fits on the opening-brace line: swift-format rewraps the inline
  // annotation onto a `state in` continuation, which SwiftLint's
  // `closure_parameter_position` then rejects. The gate-spike twin escapes
  // this only because it runs neither check.
  private typealias ReplaceOutcome = (previous: Task<Void, Never>?, alreadyTerminated: Bool)

  func replace(with task: Task<Void, Never>) {
    let outcome: ReplaceOutcome = storage.withLock { state in
      let previous = state.task
      // Do not retain a task that is about to be cancelled — otherwise a
      // terminated box holds a dead task forever.
      state.task = state.terminated ? nil : task
      return (previous, state.terminated)
    }
    // Defensive: a well-behaved run has at most one suspension in flight, so
    // this should always be nil. Cancelling rather than asserting keeps a
    // contract violation from leaking a task.
    outcome.previous?.cancel()
    if outcome.alreadyTerminated { task.cancel() }
  }

  func cancelPending() {
    let pending: Task<Void, Never>? = storage.withLock { state in
      state.terminated = true
      let existing = state.task
      state.task = nil
      return existing
    }
    pending?.cancel()
  }
}
