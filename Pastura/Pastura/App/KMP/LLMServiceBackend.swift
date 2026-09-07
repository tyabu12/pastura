import Foundation
import PasturaSharedEngine

/// The Stage-5 inference boundary: a Kotlin `LLMBackend` backed by the app's
/// own `LLMService` (ADR-023 §5.2, S5-2 PR-A, #1647).
///
/// **Why it lives in `App/KMP/`.** ADR-023 §6 ruling (c) puts every K/N
/// boundary adapter here, and CLAUDE.md § Dependency Rules makes this the only
/// place `PasturaSharedEngine` may be imported — `LLM/` and `Engine/` must stay
/// unaware of the umbrella. So the adapter, not the service, owns the
/// translation.
///
/// **Single copy.** The Stage-2 gate spike that once carried a twin of each
/// adapter is retired (S5-5), so this file is the only `LLMBackend` actual and
/// `Pastura/PasturaTests/App/KMP/LLMServiceBackendTests.swift` the only suite
/// behind it. The spike never had a counterpart for this adapter anyway — its
/// `ScriptedStreamingBackend` replayed canned text instead of wrapping a
/// service.
///
/// **`SuspendController` never crosses the boundary** (`LLMBackend.kt`,
/// ADR-023 Decision 3). Suspension reaches this adapter the same way it reaches
/// every other `LLMService` consumer — as `LLMError.suspended` thrown into the
/// stream — and leaves as `TerminalStatus.Suspended`. `SharedEngineRunner`'s
/// `SuspensionRelayingBackend` wraps this one to drive the resume relay; the
/// controller itself stays on the Swift side of the seam. **Open edge until
/// S5-4:** nothing yet calls `service.attachSuspendController(_:)`, so today no
/// `.suspended` can reach this stream. Whoever constructs this adapter for a
/// real run must attach the *same* `SuspendController` instance
/// `SharedEngineRunner` holds — two controllers would make the ADR-003 relay
/// inert without any diagnostic.
///
/// **How the four `LLMBackend.generateStream` clauses are satisfied:**
///
/// 1. *Zero or more `onChunk`, then exactly one `onTerminal`.* The drain loop
///    forwards every `LLMStreamChunk`; the terminal is delivered on exactly one
///    exit path of ``drain(_:into:)``. The final-chunk shape is `LLMService`'s
///    own contract — exactly one `isFinal` chunk, always last, on a stream that
///    completes.
/// 2. *Nothing after `onTerminal`.* The terminal is the last statement on every
///    path; the stream is exhausted or thrown by then.
/// 3. *`cancel()` is best-effort, not a barrier.* ``TaskStreamHandle`` cancels
///    the backing task and returns; it does not gate a callback already in
///    flight, and Kotlin drops late callbacks. A cancelled call delivers **no**
///    terminal.
/// 4. *Callbacks are delivered serially.* One call spawns exactly one `Task`,
///    which drains exactly one `AsyncThrowingStream` and is the only thing that
///    ever touches `callbacks`.
///
/// **Isolation.** `nonisolated` because `LLMBackend` imports as an
/// *unannotated* Obj-C protocol whose members Kotlin reads from
/// `Dispatchers.Default` — without it the `@objc` thunk carries a MainActor
/// precondition that compiles clean and traps at runtime
/// (`.claude/rules/swift-isolation.md` Pattern 7).
///
/// **No `@concurrent` (Pattern 6).** Both entry points are synchronous:
/// `generateStream` spawns a `Task` and returns, and `knownTurnMarkers` is a
/// plain getter. A `Task`'s body does not inherit the caller's executor, so
/// there is no `nonisolated async` body here that could run blocking work on a
/// MainActor caller.
///
/// **Plain `Sendable`, not `@unchecked`.** The only stored member is an
/// immutable `any LLMService` (itself `Sendable`), so a later `var` fails the
/// build rather than quietly re-opening a race (`swift-isolation.md` Pattern
/// 7). The spike's twin needs `@unchecked` only because it stores a K/N
/// `[ChatTurnMarkers]`.
nonisolated final class LLMServiceBackend: LLMBackend, Sendable {
  private let service: any LLMService

  init(service: any LLMService) {
    self.service = service
  }

  /// A **computed** forward, never a stored snapshot: `LlamaCppService` reports
  /// the loaded model's own pair, so the value changes on every model load and
  /// a `let` captured at construction would keep answering with the pair of
  /// whatever model was loaded first (or ChatML, before any load).
  ///
  /// Stated at all — rather than inherited — because Kotlin's interface default
  /// does not cross K/N (#1472, `.claude/rules/kmp-interop.md` Pattern 3): the
  /// member arrives as a required Obj-C property, so an adapter that says
  /// nothing does not fall back to ChatML, it fails to compile.
  var knownTurnMarkers: [PasturaSharedEngine.ChatTurnMarkers] {
    service.knownTurnMarkers.map {
      PasturaSharedEngine.ChatTurnMarkers(start: $0.start, end: $0.end)
    }
  }

  func generateStream(
    request: PasturaSharedEngine.GenerationRequest,
    callbacks: any StreamCallbacks
  ) -> any StreamHandle {
    let stream = service.generateStream(
      system: request.system,
      user: request.user,
      // Dropping the schema here would silently disable constrained decoding —
      // no compile error, no runtime signal, just free-form output where
      // structured JSON was contracted (`OutputSchema+SharedEngine.swift`).
      schema: OutputSchema.fromShared(request.schema),
      antiRepetitionSeeds: request.antiRepetitionSeeds)

    // `any StreamCallbacks` is a Kotlin/Native protocol existential, so it
    // carries no Swift `Sendable` conformance and cannot be given one
    // retroactively (`kmp-interop.md` Pattern 1) — without the box the `Task`
    // closure is rejected as a `sending` parameter risking a race. The claim
    // the box records: Kotlin's callback object is safe to invoke from another
    // thread (clause 4 fixes the *ordering*, not the thread), and this task is
    // the only thing that ever touches it.
    let boxed = CallbacksBox(callbacks)
    let task = Task {
      await Self.drain(stream, into: boxed.value)
    }
    return TaskStreamHandle(task: task)
  }

  /// Forwards one stream's chunks to `callbacks`, then delivers exactly one
  /// terminal status — or, for a cancelled call, none.
  private static func drain(
    _ stream: AsyncThrowingStream<LLMStreamChunk, Error>,
    into callbacks: any StreamCallbacks
  ) async {
    do {
      for try await chunk in stream {
        callbacks.onChunk(
          delta: chunk.delta,
          isFinal: chunk.isFinal,
          // `clamping:` rather than the spike's trapping `Int32(_:)` — unreachable in
          // practice, but the only trapping conversion in this file otherwise.
          completionTokens: chunk.completionTokens.map { KotlinInt(int: Int32(clamping: $0)) })
      }
      // The loop ran out of elements. Distinguish a genuine end-of-stream from
      // a cancelled one: cancellation reaches this drain by TWO paths, and only
      // one of them throws.
      //
      //   - The service's producer task observes the cancellation at a
      //     suspension point and finishes the stream `throwing:` a
      //     `CancellationError` (what `MockLLMService` does) → the `catch`.
      //   - Nothing was suspended, so the stream simply *finishes* → this
      //     guard. Dropping it would report a fabricated `Completed`.
      guard !Task.isCancelled else { return }
      callbacks.onTerminal(status: TerminalStatusCompleted.shared)
    } catch is CancellationError {
      // A cancelled call delivers no terminal. Synthesising `.failed` would
      // report a failure to the Kotlin side that asked for the cancellation
      // and, per clause 3, drops late callbacks anyway — turning an orderly
      // teardown into a fake error in every log.
    } catch LLMError.suspended {
      // Checked before the generic mapping below: `.suspended` is
      // re-issuable, and mapping it to `.failed` would break the ADR-003
      // relay by making a backgrounded run look like a crash.
      callbacks.onTerminal(status: TerminalStatusSuspended.shared)
    } catch {
      guard !Task.isCancelled else { return }
      callbacks.onTerminal(
        status: TerminalStatusFailed(
          errorCode: errorCode(for: error),
          message: error.localizedDescription))
    }
  }

  /// A stable, diagnostic-only identifier for a failed generation.
  ///
  /// `TerminalStatus.Failed.errorCode` is deliberately untyped until the
  /// Stage-3 `StreamFailure` taxonomy lands, and Kotlin documents that nothing
  /// may branch on it — so this only has to be stable and greppable, not
  /// parseable. `LLMError` cases get their case name; anything else gets its
  /// concrete type, which is the most specific thing available.
  static func errorCode(for error: Error) -> String {
    guard let llmError = error as? LLMError else {
      return "llm.unmapped.\(type(of: error))"
    }
    switch llmError {
    case .loadFailed: return "llm.loadFailed"
    case .generationFailed: return "llm.generationFailed"
    case .notLoaded: return "llm.notLoaded"
    case .invalidResponse: return "llm.invalidResponse"
    case .networkError: return "llm.networkError"
    // Unreachable from `drain` — `.suspended` is caught above — but stated so
    // the mapping stays total if another caller ever reaches this.
    case .suspended: return "llm.suspended"
    case .invalidGrammar: return "llm.invalidGrammar"
    case .samplerCrashCaught: return "llm.samplerCrashCaught"
    }
  }
}

/// Carries `any StreamCallbacks` across the task boundary.
///
/// A Swift protocol existential coming from Kotlin cannot be made `Sendable`
/// retroactively (conformances may not be added to protocols), so each crossing
/// needs a concrete wrapper asserting the contract by hand — the same
/// constraint that forces `RunHandleBox` in `SharedEngineRunner`.
nonisolated private struct CallbacksBox: @unchecked Sendable {
  let value: any StreamCallbacks

  init(_ value: any StreamCallbacks) {
    self.value = value
  }
}

/// The §5.2 cancellation-composition seam: Kotlin's `invokeOnCancellation`
/// reaches `cancel()`, which cancels the Swift task backing the call.
///
/// This is what stops an abandoned inference from running on after
/// `RunHandle.cancel()`.
nonisolated private final class TaskStreamHandle: StreamHandle, Sendable {
  private let task: Task<Void, Never>

  init(task: Task<Void, Never>) {
    self.task = task
  }

  /// Idempotent and safe after the stream already ended — `Task.cancel()` is
  /// both, so the clause costs no bookkeeping.
  func cancel() {
    task.cancel()
  }
}
