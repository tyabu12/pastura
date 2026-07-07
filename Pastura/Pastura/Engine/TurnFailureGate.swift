import Foundation
import os

/// Run-scoped containment gate for LLM turn failures (ADR-021 D1–D4).
///
/// LLM phase handlers route each agent turn's `LLMCaller.call` through
/// ``attempt(agent:phaseType:emitter:work:)``. A transiently-failed turn is
/// contained as a *skip* — the handler omits that agent's contribution and
/// continues (degrade by omission, ADR-021 D2) — while systemic errors,
/// cancellation, and the D4 circuit breaker propagate and abort the run
/// through the existing catch-all in `SimulationRunner.executePhases`.
///
/// One instance is created per run by ``SimulationRunner`` and shared by
/// every ``PhaseContext``. Handlers that dispatch nested sub-phases
/// (`ConditionalHandler`) must thread the parent context's gate into the
/// sub-phase contexts — a fresh gate inside a branch would silently reset
/// the consecutive-skip counter. The reference semantics plus the
/// `OSAllocatedUnfairLock` are what make the counter run-scoped;
/// `PhaseContext` itself is a value type rebuilt per phase. The counter is
/// deliberately NOT part of `SimulationState`: a resumed run starts at 0.
nonisolated public final class TurnFailureGate: Sendable {
  /// Consecutive skipped turns that trip the D4 circuit breaker. A UX
  /// bound — each skip already costs up to a full retry budget of
  /// inference latency, so a systemically-dead backend must not grind
  /// through the rest of the scenario — not a per-model tuning contract.
  public static let consecutiveSkipLimit = 3

  private let consecutiveSkips = OSAllocatedUnfairLock<Int>(initialState: 0)

  public init() {}

  /// Runs one turn's LLM work with ADR-021 failure containment.
  ///
  /// - Returns: The work's value on success (any success resets the
  ///   consecutive-skip counter, D4), or `nil` when the turn was skipped —
  ///   the gate has already emitted
  ///   ``SimulationEvent/turnSkipped(agent:phaseType:cause:)`` and the
  ///   handler should move on to the next agent/pair, writing nothing for
  ///   this turn.
  /// - Throws: The original error, typed, for systemic failures
  ///   (`LLMError.invalidGrammar` / `.notLoaded`), cancellation, and any
  ///   unclassified throw (preserving the pre-ADR-021 abort);
  ///   `SimulationError.turnFailureLimitReached` when this failure would be
  ///   the ``consecutiveSkipLimit``-th consecutive skip (no `.turnSkipped`
  ///   is emitted for the tripping failure).
  public func attempt<T: Sendable>(
    agent: String,
    phaseType: PhaseType,
    emitter: @Sendable (SimulationEvent) -> Void,
    work: () async throws -> T
  ) async throws -> T? {
    do {
      let value = try await work()
      consecutiveSkips.withLock { $0 = 0 }
      return value
    } catch {
      guard Self.isTurnDegradable(error) else { throw error }
      let count = consecutiveSkips.withLock { count in
        count += 1
        return count
      }
      if count >= Self.consecutiveSkipLimit {
        throw SimulationError.turnFailureLimitReached(consecutiveCount: count)
      }
      emitter(.turnSkipped(agent: agent, phaseType: phaseType, cause: Self.cause(for: error)))
      return nil
    }
  }

  /// ADR-021 D3: only the transient class is contained. Systemic errors
  /// escape `LLMCaller` typed (`streamFailureError`) precisely so they fall
  /// through this predicate; cancellation and unclassified throws likewise
  /// propagate untouched.
  private static func isTurnDegradable(_ error: Error) -> Bool {
    switch error {
    case SimulationError.retriesExhausted, SimulationError.llmGenerationFailed:
      return true
    default:
      return false
    }
  }

  /// Diagnostic (non-localized) cause carried on `.turnSkipped` — the same
  /// register as `llmGenerationFailed`'s payload. The App layer renders its
  /// own localized narration; this string is for logs/harness transcripts.
  private static func cause(for error: Error) -> String {
    if case SimulationError.llmGenerationFailed(let description) = error {
      return description
    }
    return "retries exhausted"
  }
}
