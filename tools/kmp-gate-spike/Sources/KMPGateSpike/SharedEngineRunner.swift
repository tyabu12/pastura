import Foundation
import PasturaSharedEngine
import Synchronization

// Kotlin/Native does not emit Swift `Sendable` conformances, but these types
// cross threads by design: `onEvent` fires from a Kotlin worker context
// (ADR-023 §5.1 threading clause) and the relay task touches the handle from a
// third context. The Kotlin side documents both as thread-safe — `RunHandle`'s
// methods are idempotent and internally synchronized, and `SimulationEvent` is
// an immutable value carrier — so `@unchecked` records a checked-by-contract
// claim rather than a shrug.
extension SimulationEvent: @retroactive @unchecked Sendable {}
// `SimulationEngine` is stateless — `run` allocates the coroutine scope it owns
// per call — so an instance carries nothing to race on.
extension SimulationEngine: @retroactive @unchecked Sendable {}

/// Reconstructs an `AsyncStream<SimulationEvent>` over the KMP engine's
/// callback boundary, and owns the suspension relay — the two responsibilities
/// ADR-023 §5.1 assigns to this adapter.
///
/// This is one of the two §10 *permanent* adapters: it is written here for the
/// Stage-2 gate but is intended to replace the shell role of today's
/// `Pastura/Pastura/Engine/SimulationRunner.swift` at Stage 5, keeping the
/// App-facing surface (`SimulationViewModel`) unchanged.
///
/// **Threading.** `onEvent` fires from a Kotlin worker context. Nothing here may
/// assume `MainActor` — `continuation.yield` is thread-agnostic, which is why
/// the reconstruction costs nothing. This type is deliberately `nonisolated`
/// even though the package compiles under default-`MainActor` isolation, so it
/// keeps the same semantics it will have inside `Engine/`.
nonisolated public final class SharedEngineRunner: Sendable {
  private let engine = SimulationEngine()
  private let suspendController: SuspendController

  /// - Parameter suspendController: The controller the platform signals on
  ///   app-lifecycle suspend/resume. Ownership sits on the Swift side per
  ///   ADR-023 §5.2 invariant 4 — post-port it is created here rather than
  ///   reaching the engine through `PhaseContext`.
  public init(suspendController: SuspendController = SuspendController()) {
    self.suspendController = suspendController
  }

  /// Starts a run and returns its event stream.
  ///
  /// The stream finishes on the terminal event (`SimulationCompleted` or
  /// `ErrorEvent`). Terminating the stream early — a consumer breaking out of
  /// its `for await` — cancels the Kotlin run through `RunHandle.cancel()`.
  public func run(
    scenario: Scenario,
    backend: any LLMBackend
  ) -> AsyncStream<SimulationEvent> {
    AsyncStream { continuation in
      let handleBox = RunHandleBox()
      let relayBox = RelayTaskBox()

      // The engine needs the backend before it can hand back a handle, but the
      // relay needs the handle to call `notifyLLMResumed()`. The box closes
      // that cycle: the wrapper reads it lazily, and a `.suspended` terminal
      // cannot arrive before `run` has returned and filled it, because the
      // engine only starts issuing inference calls after that point.
      let relayingBackend = SuspensionRelayingBackend(
        wrapping: backend,
        suspendController: suspendController,
        handleBox: handleBox,
        relayBox: relayBox
      )

      let handle = engine.run(scenario: scenario, backend: relayingBackend) { event in
        continuation.yield(event)
        if Self.isTerminal(event) {
          continuation.finish()
        }
      }
      handleBox.store(handle)

      continuation.onTermination = { _ in
        // Fires on normal finish AND on early consumer termination. `cancel()`
        // is idempotent, so the normal path costs a no-op rather than needing
        // a "did it already finish?" flag.
        handleBox.handle?.cancel()
        relayBox.cancelPending()
      }
    }
  }

  /// The two events after which no further event arrives, per
  /// `SimulationEngine.run`'s contract.
  private static func isTerminal(_ event: SimulationEvent) -> Bool {
    event is SimulationEvent.SimulationCompleted || event is SimulationEvent.ErrorEvent
  }
}

/// Holds the `RunHandle` the engine returns, so the relay and the termination
/// handler can reach it from other threads.
///
/// `@unchecked Sendable`: the stored handle is guarded by the mutex, and the
/// Kotlin handle's own methods are documented idempotent and thread-safe.
nonisolated private final class RunHandleBox: @unchecked Sendable {
  // Boxed rather than stored bare: `Mutex.withLock` takes an `inout sending`
  // parameter, and `any RunHandle` is a Kotlin/Native protocol with no Swift
  // `Sendable` conformance — so a bare store fails with "'inout sending'
  // parameter cannot be task-isolated". A protocol cannot be given a
  // retroactive conformance, hence the wrapper.
  private struct Boxed: @unchecked Sendable {
    let value: any RunHandle
  }

  private let storage = Mutex<Boxed?>(nil)

  var handle: (any RunHandle)? { storage.withLock { $0 }?.value }

  func store(_ handle: any RunHandle) {
    let boxed = Boxed(value: handle)
    storage.withLock { $0 = boxed }
  }
}

/// Tracks the in-flight relay task so stream termination can cancel a parked
/// one instead of leaking it.
nonisolated private final class RelayTaskBox: @unchecked Sendable {
  private let storage = Mutex<Task<Void, Never>?>(nil)

  func replace(with task: Task<Void, Never>) {
    let previous: Task<Void, Never>? = storage.withLock {
      let old = $0
      $0 = task
      return old
    }
    // Defensive: a well-behaved run has at most one suspension in flight, so
    // this should always be nil. Cancelling rather than asserting keeps a
    // contract violation from leaking a task.
    previous?.cancel()
  }

  func cancelPending() {
    storage.withLock { $0 }?.cancel()
  }
}

/// Wraps the platform backend so the runner can observe `.suspended` terminals
/// and drive the ADR-023 §5.2 suspension relay.
///
/// The relay is spawned **per suspension cycle**, not held as a long-lived
/// loop, which is what §5.2 invariant 2 requires: `CompletableDeferred` is
/// single-shot, so each cycle needs a fresh one on the Kotlin side and a fresh
/// awaiter here.
nonisolated private final class SuspensionRelayingBackend: LLMBackend, @unchecked Sendable {
  private let wrapped: any LLMBackend
  private let suspendController: SuspendController
  private let handleBox: RunHandleBox
  private let relayBox: RelayTaskBox

  init(
    wrapping wrapped: any LLMBackend,
    suspendController: SuspendController,
    handleBox: RunHandleBox,
    relayBox: RelayTaskBox
  ) {
    self.wrapped = wrapped
    self.suspendController = suspendController
    self.handleBox = handleBox
    self.relayBox = relayBox
  }

  func generateStream(
    request: GenerationRequest,
    callbacks: any StreamCallbacks
  ) -> any StreamHandle {
    let observing = RelayObservingCallbacks(
      forwardingTo: callbacks,
      onSuspended: { [suspendController, handleBox, relayBox] in
        relayBox.replace(
          with: Task {
            await suspendController.awaitResume()
            // A cancelled relay must not wake the engine: the run is going
            // away, and `notifyLLMResumed()` would release a park the engine
            // is about to abandon. `awaitResume()` returns promptly on
            // cancellation, so this check is the one that distinguishes the
            // two exits.
            guard !Task.isCancelled else { return }
            handleBox.handle?.notifyLLMResumed()
          })
      })
    return wrapped.generateStream(request: request, callbacks: observing)
  }
}

/// Forwards every callback through untouched, notifying the relay when the
/// stream ends in `.suspended`.
///
/// Forwarding order is load-bearing: the terminal reaches Kotlin **before** the
/// relay is armed. Arming first would open a window where a resume that lands
/// immediately calls `notifyLLMResumed()` on a park the engine has not created
/// yet — the lost-wakeup shape §5.2 invariant 3 exists to rule out.
nonisolated private final class RelayObservingCallbacks: StreamCallbacks, @unchecked Sendable {
  private let wrapped: any StreamCallbacks
  private let onSuspended: @Sendable () -> Void

  init(forwardingTo wrapped: any StreamCallbacks, onSuspended: @escaping @Sendable () -> Void) {
    self.wrapped = wrapped
    self.onSuspended = onSuspended
  }

  func onChunk(delta: String, isFinal: Bool, completionTokens: KotlinInt?) {
    wrapped.onChunk(delta: delta, isFinal: isFinal, completionTokens: completionTokens)
  }

  func onTerminal(status: any TerminalStatus) {
    wrapped.onTerminal(status: status)
    if status is TerminalStatusSuspended {
      onSuspended()
    }
  }
}
