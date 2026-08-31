import Foundation
import PasturaSharedEngine
import Synchronization

// Every Kotlin type below that also has a Swift twin declared in this module —
// `Scenario`, `SimulationEvent`, `NoopEngineLogger`, `SystemRandomSource`,
// `ChatTurnMarkers`, `LanguageDetector`, `EngineLogger`, `RandomSource` — is
// spelled `PasturaSharedEngine.X`. An in-module
// declaration shadows the import, so a bare name binds to the *Swift* type and
// the file either fails to build or, worse, builds against the wrong one. No
// typealias: a bare alias would hide the shadowing from the next reader. The
// bare names (`SimulationEngine`, `LLMBackend`, `RunHandle`, `StreamCallbacks`,
// …) are bare only because Kotlin exports no twin for them today — a Kotlin
// bump that adds one rebinds silently, so re-run the count in
// `.claude/rules/kmp-interop.md` Pattern 1b after each bump.

// Kotlin/Native does not emit Swift `Sendable` conformances, but these types
// cross threads by design: `onEvent` fires from a Kotlin worker context
// (ADR-023 §5.1 threading clause) and the relay task touches the handle from a
// third context. The Kotlin side documents both as thread-safe — `RunHandle`'s
// methods are idempotent and internally synchronized, and `SimulationEvent` is
// an immutable value carrier — so `@unchecked` records a checked-by-contract
// claim rather than a shrug.
extension PasturaSharedEngine.SimulationEvent: @retroactive @unchecked Sendable {}
// `SimulationEngine` is no longer stateless: it holds a `ScenarioValidator`
// (D3's preflight gate) plus the constructor-injected detector and logger
// seams. Every one of them is a Kotlin `val` assigned at init and never
// mutated, and each implementation is itself thread-safe (the validator is a
// stateless value), while `run` still allocates the coroutine scope it owns per
// call. So the claim is all-`val` immutability plus thread-safe members, not
// "there is no state" — a future `var` field would invalidate it (Pattern 1 of
// `.claude/rules/kmp-interop.md` says the same for the retroactive
// conformance).
//
// It follows that anything injected into that constructor must be
// Sendable-safe on the Swift side too: Kotlin calls `LanguageDetector.detect`
// and `EngineLogger.log` from `Dispatchers.Default`, which is why both
// interfaces' KDoc requires a Swift conformer to be declared `nonisolated`.
// `nonisolated` alone is not enough, though: it only removes the actor hop, so
// the injected instances must themselves be `Sendable` / internally
// thread-safe, or this conformance launders a real race into a checked claim.
extension SimulationEngine: @retroactive @unchecked Sendable {}
// The two Kotlin defaults `init` below hands to `SimulationEngine` when a caller names no
// seam. Both are K/N-exported classes, so neither arrives `Sendable` (Pattern 1) nor satisfies
// its parameter's `& Sendable` composition without this — measured: "type 'NoopEngineLogger'
// does not conform to the 'Sendable' protocol". Checked-by-contract on the narrowest claim:
// `NoopEngineLogger` has no state (`log` is an empty body), `SystemRandomSource` none either
// (delegates to Kotlin's thread-safe `Random.Default`). A field on either invalidates both, and
// nothing detects one being added — this sentence is the detector until upstreamed to `commonMain`.
extension PasturaSharedEngine.NoopEngineLogger: @retroactive @unchecked Sendable {}
extension PasturaSharedEngine.SystemRandomSource: @retroactive @unchecked Sendable {}

/// Reconstructs an `AsyncStream<SimulationEvent>` over the KMP engine's
/// callback boundary, and owns the suspension relay — the two responsibilities
/// ADR-023 §5.1 assigns to this adapter.
///
/// This is one of the two §10 *permanent* adapters. It lives under `App/KMP/`
/// per ADR-023 §6 ruling (c): bridging Engine ↔ App is the App layer's job by
/// ADR-001, so no new dependency edge is created. At S5-4/S5-5 it replaces the
/// shell role of `Pastura/Pastura/Engine/SimulationRunner.swift`, keeping the
/// App-facing surface (`SimulationViewModel`) unchanged.
///
/// `tools/kmp-gate-spike/Sources/KMPGateSpike/SharedEngineRunner.swift` is this
/// file's twin, still built by the nightly gate-spike rung until S5-5 — a
/// change to the §5.2 relay contract must land in both.
///
/// **Threading.** `onEvent` fires from a Kotlin worker context. Nothing here may
/// assume `MainActor` — `continuation.yield` is thread-agnostic, which is why
/// the reconstruction costs nothing. This type is deliberately `nonisolated`
/// even though the target compiles under default-`MainActor` isolation.
nonisolated final class SharedEngineRunner: Sendable {
  // All three arguments are spelled out at the construction site below because
  // Kotlin default arguments do not survive the K/N export
  // (`.claude/rules/kmp-interop.md` Pattern 3): the header declares exactly one
  // initializer, `init(detector:logger:random:)`, with no no-arg overload. The
  // Swift-side defaults restate the Kotlin ones — `nil` keeps the
  // language-adherence check off, `NoopEngineLogger` swallows diagnostics,
  // `SystemRandomSource` is the production RNG — so a caller naming none of them
  // gets the pre-S5-2 behaviour unchanged. This is where Stage 5 hands in
  // `NLLanguageDetector` / `OSLogEngineLogger` through `LanguageDetectorBridge` /
  // `EngineLoggerBridge`, and a parity fixture a `SplitMix64RandomSource` (S3b).
  private let engine: SimulationEngine
  private let suspendController: SuspendController

  /// - Parameters:
  ///   - suspendController: The controller the platform signals on app-lifecycle
  ///     suspend/resume. Ownership sits on the Swift side per ADR-023 §5.2
  ///     invariant 4 — post-port it is created here, not reached via `PhaseContext`.
  ///   - detector: ADR-010 Step E output-language detector; `nil` (the Kotlin
  ///     default) disables the adherence check.
  ///   - logger: Diagnostic seam reaching `LLMCaller`'s `StreamingDiag` channel.
  ///   - random: The `assign random_one` / `event_inject` randomness seam.
  ///
  /// Each seam parameter is a `& Sendable` **composition**, deliberately: the
  /// K/N protocol existentials carry no `Sendable` of their own (Pattern 1),
  /// and the `@retroactive @unchecked Sendable` on `SimulationEngine` above
  /// would otherwise launder a non-thread-safe conformer into a checked claim —
  /// Kotlin calls all three from `Dispatchers.Default`. With the composition it
  /// is the bridge's own declared `Sendable` that satisfies the parameter, so a
  /// conformer that cannot claim it fails the build instead.
  init(
    suspendController: SuspendController = SuspendController(),
    detector: (any PasturaSharedEngine.LanguageDetector & Sendable)? = nil,
    logger: any PasturaSharedEngine.EngineLogger & Sendable =
      PasturaSharedEngine.NoopEngineLogger(),
    random: any PasturaSharedEngine.RandomSource & Sendable =
      PasturaSharedEngine.SystemRandomSource()
  ) {
    self.suspendController = suspendController
    self.engine = SimulationEngine(detector: detector, logger: logger, random: random)
  }

  /// Starts a run and returns its event stream.
  ///
  /// The stream finishes on the terminal event (`SimulationCompleted` or
  /// `ErrorEvent`). Terminating the stream early — a consumer breaking out of
  /// its `for await` — cancels the Kotlin run through `RunHandle.cancel()`.
  func run(
    scenario: PasturaSharedEngine.Scenario,
    backend: any LLMBackend
  ) -> AsyncStream<PasturaSharedEngine.SimulationEvent> {
    AsyncStream { continuation in
      let handleBox = RunHandleBox()
      let relayBox = RelayTaskBox()

      // The engine needs the backend before it can hand back a handle, but the
      // relay needs the handle to call `notifyLLMResumed()`. The box closes
      // that cycle.
      //
      // It must also *latch*, because the handle genuinely can arrive late:
      // `SimulationEngine.run` does a non-lazy `scope.launch { RunLoop(...)
      // .execute() }` on `Dispatchers.Default` and only then returns the
      // handle, so the run loop can issue an inference call, take a
      // `.suspended` terminal, and drive the relay while `store` has not yet
      // run on this thread. Reading the handle optionally in that window would
      // drop the wakeup and park the run forever — see `RunHandleBox`.
      let relayingBackend = SuspensionRelayingBackend(
        wrapping: backend,
        suspendController: suspendController,
        handleBox: handleBox,
        relayBox: relayBox
      )

      // Installed before `engine.run` for the same reason both boxes latch.
      // Inside *this* window — before `run` returns — a consumer cannot be the
      // trigger, because none holds the stream yet; what reaches the handler
      // here is `onEvent` firing from the Kotlin run loop concurrently with the
      // lines below and hitting `continuation.finish()` on an immediate
      // terminal, while both boxes are still empty. (Consumer termination is
      // the dominant trigger *after* `run` returns — see `RelayTaskBox`.)
      continuation.onTermination = { _ in
        // Fires on normal finish AND on early consumer termination. `cancel()`
        // is idempotent, so the normal path costs a no-op rather than needing
        // a "did it already finish?" flag. Both calls latch when they land
        // before the thing they cancel exists.
        handleBox.cancel()
        relayBox.cancelPending()
      }

      let handle = engine.run(scenario: scenario, backend: relayingBackend) { event in
        continuation.yield(event)
        // Terminality is declared on the Kotlin `SimulationEvent` itself, via
        // an exhaustive `when` the compiler rejects when a subclass is added.
        // This used to be a local `is SimulationCompleted || is ErrorEvent`
        // chain, which no gate could see: ADR-022's no-default check reaches
        // `when` / `switch` projections, not `is` / `==` predicates. A new
        // terminal case would have left this stream never finishing, silently.
        if event.isTerminal {
          continuation.finish()
        }
      }
      handleBox.store(handle)
    }
  }
}

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
/// resume dropped in that window parks the run forever, and a cancel dropped in
/// it leaks the Kotlin coroutine. Both are replayed on `store`.
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
    var pendingResume = false
    var pendingCancel = false
  }

  private let storage = Mutex(State())

  /// Stores the handle and replays anything that arrived before it.
  ///
  /// When both were latched, cancel is replayed after resume so a run cancelled
  /// while parked is first released and then torn down. This orders the *replay*
  /// only — a live `cancel()` racing this method can still land before the
  /// replayed `notifyLLMResumed()`. That is harmless (a resume on a cancelled
  /// `Job` is a no-op), and no stronger guarantee is claimed.
  func store(_ handle: any RunHandle) {
    let boxed = Boxed(value: handle)
    let pending: (resume: Bool, cancel: Bool) = storage.withLock { state in
      state.handle = boxed
      let carried = (state.pendingResume, state.pendingCancel)
      state.pendingResume = false
      state.pendingCancel = false
      return carried
    }
    if pending.resume { handle.notifyLLMResumed() }
    if pending.cancel { handle.cancel() }
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

  /// Forwarded, not defaulted: a transparent decorator answering ChatML would
  /// mask whatever pair the wrapped backend reports, which at Stage 5 is the
  /// model's own. (Stated at all because Kotlin's interface default does not
  /// cross K/N — #1472.)
  ///
  /// Asserted end to end by
  /// `BoundaryContractTests.kotlinTruncatesOnForwardedTurnMarkers`: Kotlin
  /// reads this property off *this* object on every inference, so a ChatML
  /// hardcode here reaches #1422 truncation and reddens there.
  var knownTurnMarkers: [PasturaSharedEngine.ChatTurnMarkers] { wrapped.knownTurnMarkers }

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
            handleBox.notifyResumed()
          })
      })
    return wrapped.generateStream(request: request, callbacks: observing)
  }
}

/// Forwards every callback through untouched, notifying the relay when the
/// stream ends in `.suspended`.
///
/// **Forwarding order here is not load-bearing**, and an earlier version of
/// this comment claimed the opposite. §5.2 invariant 3 is satisfied on the
/// *Kotlin* side, not by this ordering: `LLMCaller` calls `SuspensionRelay
/// .arm()` before it issues the stream, so the `CompletableDeferred` already
/// exists across this whole window, and its completion is sticky — a
/// `notifyLLMResumed()` that lands before Kotlin parks is recorded, not
/// dropped. Forwarding the terminal first is simply the natural order; it is
/// not closing a race, and no future reader should preserve it as though it
/// were. See `SuspensionRelay`'s KDoc, which is the authority on the invariant.
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
