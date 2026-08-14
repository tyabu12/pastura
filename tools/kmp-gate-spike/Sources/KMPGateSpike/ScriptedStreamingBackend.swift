import Foundation
import PasturaSharedEngine
import Synchronization

/// One scripted generation — the deltas a call emits and how it ends.
///
/// Mirrors what `LlamaCppService.generateStream` produces, minus the model:
/// non-final deltas arrive over time, and the call ends either normally, in a
/// platform suspension, or in a failure. The `ADR-023 §5.2` clause-1 shape
/// ("a completed stream carries exactly one `isFinal = true` chunk, always
/// last; suspended/failed carry none") is enforced during construction rather
/// than left to each call site — see ``ScriptedStreamingBackend``.
nonisolated public struct ScriptedResponse: Sendable {
  /// How a scripted call terminates.
  public enum Ending: Sendable {
    /// Normal completion. The token count rides the final chunk, exactly as
    /// llama.cpp reports it (`LLMCaller.swift:298-302`): a last chunk with an
    /// empty delta carrying only the count. `nil` means "unknown throughput".
    case completed(completionTokens: Int?)
    /// The platform cut the call off mid-generation and it is re-issuable.
    /// Maps from Swift `LLMError.suspended`.
    case suspended
    /// The call failed and the relay must not re-issue it.
    case failed(errorCode: String, message: String?)
  }

  /// Non-final deltas, emitted in order. May be empty — a backend without true
  /// streaming (Ollama, a mock) legally emits none.
  public var deltas: [String]

  /// How the call ends.
  public var ending: Ending

  /// Delay before each delta. `nil` emits as fast as the consumer drains.
  ///
  /// This is the knob the Pattern 6 liveness probe needs: a freeze is only
  /// observable when chunks are *paced*, because an instantly-draining stream
  /// finishes before a blocked `MainActor` consumer could be caught at it.
  public var chunkDelay: Duration?

  public init(
    deltas: [String],
    ending: Ending,
    chunkDelay: Duration? = nil
  ) {
    self.deltas = deltas
    self.ending = ending
    self.chunkDelay = chunkDelay
  }

  /// How many `onChunk` callbacks this response will deliver.
  ///
  /// Derived from the response rather than recomputed by callers. The `+1` is
  /// clause 1's final chunk, which exists only for `.completed` — a caller
  /// that re-derives the count from its own script parameters has to restate
  /// that rule and can restate it wrongly. Measurement (ii) divides by this,
  /// so a wrong denominator silently biases the published per-chunk figure.
  public var emittedChunkCount: Int {
    switch ending {
    case .completed: return deltas.count + 1
    case .suspended, .failed: return deltas.count
    }
  }
}

/// One chunk crossing the scripted stream.
///
/// Mirrors `Pastura/Pastura/LLM/LLMStreamChunk.swift` field-for-field. It is a
/// deliberate *mirror*, not a verbatim copy under a drift guard like
/// ``SuspendController``: the real type is three immutable fields with no
/// invariants to lose in transcription, so a copy would buy nothing while
/// implying a coupling the spike does not have.
nonisolated public struct ScriptedChunk: Sendable, Equatable {
  public let delta: String
  public let isFinal: Bool
  public let completionTokens: Int?

  public init(delta: String, isFinal: Bool, completionTokens: Int?) {
    self.delta = delta
    self.isFinal = isFinal
    self.completionTokens = completionTokens
  }
}

/// The Swift side of the ADR-023 §5.2 inference boundary: a scripted
/// `LLMBackend` that drives Kotlin's `LLMCaller` through a **real**
/// `AsyncThrowingStream`.
///
/// This is the second of the two §10 *permanent* adapters. At Stage 5 the
/// scripted source is replaced by `LLMService.generateStream` (i.e.
/// `LlamaCppService`) and the relay/mapping/cancellation machinery below stays
/// as-is — which is why the shape here is the production shape, not a test
/// double's shortcut. A Kotlin-side mock alone does not satisfy the Stage-2
/// gate (ADR-023 §6): the point is to measure the real Swift→Kotlin seam.
///
/// **How the four clauses of `LLMBackend.generateStream` are satisfied:**
///
/// 1. *Zero or more `onChunk`, then exactly one `onTerminal`.* The drain loop
///    forwards chunks; the terminal is delivered on exactly one exit path, and
///    ``ScriptedResponse`` construction is what guarantees the final-chunk
///    shape (final chunk iff `.completed`).
/// 2. *Nothing after `onTerminal`.* The terminal is the last statement on every
///    path; the stream is exhausted or thrown by then.
/// 3. *`cancel()` is best-effort, not a barrier.* It cancels the backing task
///    and returns — it does not gate a callback already in flight. Per the
///    clause, Kotlin ignores late callbacks, so no atomic gate is needed here.
///    A cancelled call delivers **no** terminal; see ``drain(_:into:)``.
/// 4. *Callbacks are delivered serially.* Bought for free by construction:
///    one call spawns exactly one `Task`, which drains exactly one stream, and
///    that task is the only thing that ever touches `callbacks`. There is no
///    producer task — the stream is built with `unfolding`, so elements are
///    produced on the draining task itself. That keeps "1 call = 1 task"
///    literally true and mechanically auditable — this returns exactly 1:
///    `grep -vE '^\s*(//|\*)' <this file> | grep -c 'Task {'`
///    — rather than true-modulo-a-helper-task. (The comment strip is not
///    incidental: the unstripped grep returns 2, because this line matches
///    itself.)
///
/// **Threading.** Nothing here assumes `MainActor`; the type is `nonisolated`
/// so it keeps the semantics it will have inside `LLM/` post-port, under the
/// same `NonisolatedNonsendingByDefault` regime the app compiles with (see
/// `Package.swift`).
nonisolated public final class ScriptedStreamingBackend: LLMBackend, @unchecked Sendable {
  private let script: Mutex<[ScriptedResponse]>
  private let counters = Counters()

  /// The leaf's own pair — see the initializer parameter.
  ///
  /// Covered by the class's `@unchecked Sendable`, and the only stored member
  /// here that needs the exemption: a K/N export carries no `Sendable`
  /// conformance (`kmp-interop.md` Pattern 1), so this stays sound only while
  /// `ChatTurnMarkers`' two fields remain `val` on the Kotlin side.
  public let knownTurnMarkers: [ChatTurnMarkers]

  /// - Parameter responses: Consumed in order, one per `generateStream` call —
  ///   the `MockLLMService` convention (CLAUDE.md § Testing Strategy). A call
  ///   past the end of the script terminates as `.failed` with
  ///   ``scriptExhaustedErrorCode`` rather than trapping: the gate exercises
  ///   Kotlin's retry loop, which can legitimately issue more calls than a
  ///   test anticipated, and a trap there would read as a crash rather than as
  ///   the miscount it is.
  /// - Parameter knownTurnMarkers: Defaults to the Kotlin companion's ChatML
  ///   pair — the value `LLMBackend`'s interface default would supply if it
  ///   crossed K/N, which it does not (#1472). Injectable so a test can give a
  ///   decorator something other than ChatML to forward; without that, every
  ///   conformer in the package returns the same value and forwarding is
  ///   indistinguishable from hardcoding.
  public init(
    responses: [ScriptedResponse],
    knownTurnMarkers: [ChatTurnMarkers] = [ChatTurnMarkers.companion.chatML]
  ) {
    self.script = Mutex(responses)
    self.knownTurnMarkers = knownTurnMarkers
  }

  /// Error code reported when the script runs out of responses.
  public static let scriptExhaustedErrorCode = "spike.script_exhausted"

  /// Number of `generateStream` calls issued so far — the call count
  /// measurement (ii) reports, and the assertion that proves a suspend re-issue
  /// really did re-issue.
  public var callCount: Int { counters.callCount }

  /// When each `generateStream` call arrived, in call order.
  ///
  /// Measurement (ii)'s suspension round-trip reads its endpoint from here
  /// instead of from the poll loop that waits for it: polling bounds *how long
  /// the benchmark waits*, but if it also supplied the timestamp, the reported
  /// latency could never fall below the poll interval — the instrument would
  /// be the floor.
  public var callInstants: [ContinuousClock.Instant] { counters.callInstants }

  /// Number of calls whose drain task exited because it was cancelled.
  ///
  /// This is the observable end of the §5.2 cancellation-composition clause:
  /// a Kotlin coroutine cancellation must reach `StreamHandle.cancel()` and
  /// from there cancel the backing Swift task. Without a counter the clause is
  /// only assertable as an absence, which passes just as well when nothing was
  /// wired at all.
  public var observedCancellations: Int { counters.cancellations }

  public func generateStream(
    request: GenerationRequest,
    callbacks: any StreamCallbacks
  ) -> any StreamHandle {
    counters.recordCall()
    let response = nextResponse()
    let stream = Self.makeStream(for: response)

    // `any StreamCallbacks` is a Kotlin/Native protocol, so it carries no Swift
    // `Sendable` conformance and cannot be given one retroactively — the same
    // constraint that forces `RunHandleBox` in `SharedEngineRunner`. Without
    // the box the `Task` closure is rejected as a `sending` parameter risking a
    // race. The claim the box records: Kotlin's callback object is safe to
    // invoke from another thread (§5.2 clause 4 fixes the *ordering*, not the
    // thread), and this task is the only thing that ever touches it.
    let boxed = CallbacksBox(callbacks)
    let task = Task { [counters] in
      await Self.drain(stream, into: boxed.value, ending: response.ending, counters: counters)
    }
    return TaskStreamHandle(task: task)
  }

  private func nextResponse() -> ScriptedResponse {
    let next: ScriptedResponse? = script.withLock { remaining in
      guard !remaining.isEmpty else { return nil }
      return remaining.removeFirst()
    }
    return next
      ?? ScriptedResponse(
        deltas: [],
        ending: .failed(
          errorCode: Self.scriptExhaustedErrorCode,
          message: "ScriptedStreamingBackend ran out of scripted responses."
        )
      )
  }

  /// Builds the response's chunk sequence as a real `AsyncThrowingStream`.
  ///
  /// `.suspended` / `.failed` are modelled as the stream **throwing**, not as a
  /// flag on a normally-finished stream. That is the fidelity point: the real
  /// `LlamaCppService` throws `LLMError.suspended` into its stream, so the
  /// error-to-`TerminalStatus` mapping this adapter will run in production is
  /// the one exercised here.
  private static func makeStream(
    for response: ScriptedResponse
  ) -> AsyncThrowingStream<ScriptedChunk, Error> {
    // The cursor is boxed in a `Mutex` rather than captured as a plain `var`.
    // `unfolding` takes a `@Sendable` closure, so a bare mutable capture is
    // unsound to the type system even though only the single draining task
    // ever runs this body — and the compiler says so (`#SendableClosureCaptures`).
    // Boxing costs an uncontended lock per chunk and keeps the claim honest.
    let cursor = Mutex(0)
    return AsyncThrowingStream {
      if let delay = response.chunkDelay {
        // Cancellation-aware by construction: a cancelled drain task exits
        // here rather than sleeping out the rest of the script.
        try await Task.sleep(for: delay)
      }

      let index = cursor.withLock { $0 }
      if index < response.deltas.count {
        cursor.withLock { $0 += 1 }
        return ScriptedChunk(delta: response.deltas[index], isFinal: false, completionTokens: nil)
      }

      // Deltas exhausted — the ending decides what the last element is.
      switch response.ending {
      case .completed(let completionTokens):
        guard index == response.deltas.count else { return nil }
        cursor.withLock { $0 += 1 }
        // Clause 1's final chunk: empty delta carrying only the token count,
        // the llama.cpp shape.
        return ScriptedChunk(delta: "", isFinal: true, completionTokens: completionTokens)
      case .suspended:
        throw ScriptedStreamError.suspended
      case .failed(let errorCode, let message):
        throw ScriptedStreamError.failed(errorCode: errorCode, message: message)
      }
    }
  }

  /// Forwards one stream's chunks to `callbacks`, then delivers exactly one
  /// terminal status.
  private static func drain(
    _ stream: AsyncThrowingStream<ScriptedChunk, Error>,
    into callbacks: any StreamCallbacks,
    ending: ScriptedResponse.Ending,
    counters: Counters
  ) async {
    do {
      for try await chunk in stream {
        callbacks.onChunk(
          delta: chunk.delta,
          isFinal: chunk.isFinal,
          completionTokens: chunk.completionTokens.map { KotlinInt(int: Int32($0)) }
        )
      }
      // The loop ran out of elements. Distinguish a genuine end-of-stream from
      // a cancelled one: cancellation reaches this drain by TWO different
      // paths, and only one of them throws.
      //
      //   - Cancelled while the unfolding body is suspended in `Task.sleep`
      //     (any paced response): the sleep throws `CancellationError`, which
      //     propagates out of `for try await` → the `catch` below.
      //   - Cancelled with no suspension point in flight (an unpaced
      //     response): `AsyncThrowingStream` *finishes* instead of throwing,
      //     so the loop simply ends → this guard.
      //
      // Both were confirmed by instrumenting each branch and driving the two
      // cases separately; neither is dead code, and dropping this guard would
      // report a fabricated `Completed` for the unpaced one.
      guard !Task.isCancelled else {
        counters.recordCancellation()
        return
      }
      callbacks.onTerminal(status: TerminalStatusCompleted.shared)
    } catch is CancellationError {
      // A cancelled call delivers no terminal. Synthesising `.failed` here
      // would report a failure to a Kotlin side that asked for the
      // cancellation and, per clause 3, drops late callbacks anyway — turning
      // an orderly teardown into a fake error in every log.
      counters.recordCancellation()
    } catch ScriptedStreamError.suspended {
      callbacks.onTerminal(status: TerminalStatusSuspended.shared)
    } catch ScriptedStreamError.failed(let errorCode, let message) {
      callbacks.onTerminal(status: TerminalStatusFailed(errorCode: errorCode, message: message))
    } catch {
      // Defence in depth: `makeStream` throws only the two cases above, but an
      // unmapped error must still resolve to exactly one terminal rather than
      // silently dropping the call and hanging `LLMCaller`.
      callbacks.onTerminal(
        status: TerminalStatusFailed(
          errorCode: "spike.unmapped_error",
          message: String(describing: error)
        )
      )
    }
  }
}

/// Carries `any StreamCallbacks` across the task boundary.
///
/// One of the K/N shim-budget entries measurement (iii) counts: a Swift
/// protocol existential from Kotlin cannot be made `Sendable` retroactively
/// (conformances may not be added to protocols), so each crossing needs a
/// concrete wrapper asserting the contract by hand.
nonisolated private struct CallbacksBox: @unchecked Sendable {
  let value: any StreamCallbacks

  init(_ value: any StreamCallbacks) {
    self.value = value
  }
}

/// How a scripted stream ends abnormally.
///
/// Stands in for the `LLMError` cases the production adapter maps —
/// `.suspended` most importantly, since that is the one the ADR-003 relay
/// depends on.
nonisolated public enum ScriptedStreamError: Error, Sendable {
  case suspended
  case failed(errorCode: String, message: String?)
}

/// The §5.2 cancellation-composition seam: Kotlin's `invokeOnCancellation`
/// reaches `cancel()`, which cancels the Swift task backing the call.
///
/// In production this is what stops `llama_decode` from running on after
/// `RunHandle.cancel()`; here it stops the scripted drain, which is the same
/// wiring with a cheaper body.
nonisolated private final class TaskStreamHandle: StreamHandle, @unchecked Sendable {
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

/// Call/cancellation tallies, shared between the backend and its drain tasks.
nonisolated private final class Counters: Sendable {
  /// Arrival instants, one per call. The count is *derived* from this rather
  /// than tracked beside it, so an observer can never see a count that has
  /// advanced past the instants it is about to read.
  private let callTimes = Mutex<[ContinuousClock.Instant]>([])
  private let cancels = Mutex(0)

  var callCount: Int { callTimes.withLock { $0.count } }
  var callInstants: [ContinuousClock.Instant] { callTimes.withLock { $0 } }
  var cancellations: Int { cancels.withLock { $0 } }

  func recordCall() {
    // Sampled before taking the lock: the instant should carry when the call
    // arrived, not when it won the mutex.
    let arrival = ContinuousClock.now
    callTimes.withLock { $0.append(arrival) }
  }

  func recordCancellation() {
    cancels.withLock { $0 += 1 }
  }
}
