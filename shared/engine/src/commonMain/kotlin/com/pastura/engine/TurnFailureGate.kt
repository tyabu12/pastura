package com.pastura.engine

import com.pastura.models.PhaseType
import com.pastura.models.SimulationError
import com.pastura.models.SimulationEvent
import kotlin.concurrent.atomics.AtomicInt
import kotlin.concurrent.atomics.ExperimentalAtomicApi
import kotlin.concurrent.atomics.incrementAndFetch

/**
 * Run-scoped containment gate for LLM turn failures (ADR-021 D1–D4).
 *
 * LLM phase handlers route each agent turn's `LLMCaller.call` through [attempt].
 * A transiently-failed turn is contained as a *skip* — the handler omits that
 * agent's contribution and continues (degrade by omission, ADR-021 D2) — while
 * systemic errors, cancellation, and the D4 circuit breaker propagate and abort
 * the run through the existing catch-all in `SimulationRunner.executePhases`.
 *
 * One instance is created per run by the runner and shared by every
 * `PhaseContext`. Handlers that dispatch nested sub-phases (`ConditionalHandler`)
 * must thread the parent context's gate into the sub-phase contexts — a fresh
 * gate inside a branch would silently reset the consecutive-skip counter. The
 * reference semantics plus the [AtomicInt] are what make the counter run-scoped;
 * `PhaseContext` itself is a value type rebuilt per phase. The counter is
 * deliberately NOT part of `SimulationState`: a resumed run starts at 0.
 *
 * Swift original: `Pastura/Pastura/Engine/TurnFailureGate.swift`.
 */
@OptIn(ExperimentalAtomicApi::class)
internal class TurnFailureGate {

    companion object {
        /**
         * Consecutive skipped turns that trip the D4 circuit breaker. A UX bound
         * — each skip already costs up to a full retry budget of inference
         * latency, so a systemically-dead backend must not grind through the rest
         * of the scenario — not a per-model tuning contract.
         */
        const val consecutiveSkipLimit = 3
    }

    // Atomic mirrors the fidelity argument of `SimulationEngine.kt`'s PauseGate:
    // Swift guards this counter with a `Mutex`, so the port keeps the mutation
    // atomic rather than degrading it to a bare `Int`.
    private val consecutiveSkips = AtomicInt(0)

    /**
     * Runs one turn's LLM work with ADR-021 failure containment.
     *
     * @return The work's value on success (any success resets the
     *   consecutive-skip counter, D4), or `null` when the turn was skipped — the
     *   gate has already emitted [SimulationEvent.TurnSkipped] and the handler
     *   should move on to the next agent/pair, writing nothing for this turn.
     * @throws SimulationException The original error, wrapped, for systemic
     *   failures, plus [SimulationError.TurnFailureLimitReached] when this failure
     *   would be the [consecutiveSkipLimit]-th consecutive skip (no
     *   [SimulationEvent.TurnSkipped] is emitted for the tripping failure).
     *   `CancellationException` and any non-degradable throw propagate untouched.
     */
    suspend fun <T> attempt(
        agent: String,
        phaseType: PhaseType,
        emitter: (SimulationEvent) -> Unit,
        work: suspend () -> T,
    ): T? {
        return try {
            val value = work()
            consecutiveSkips.store(0)
            value
        } catch (e: Throwable) {
            // Deliberately rethrows CancellationException (structured-concurrency-
            // cooperative) and any non-degradable throw before touching the
            // counter — faithful to Swift's `default: throw`. An explicit
            // try/catch (not `runCatching`, which swallows CancellationException).
            if (!isTurnDegradable(e)) throw e
            val count = consecutiveSkips.incrementAndFetch()
            if (count >= consecutiveSkipLimit) {
                throw SimulationException(SimulationError.TurnFailureLimitReached(count))
            }
            emitter(SimulationEvent.TurnSkipped(agent = agent, phaseType = phaseType, cause = cause(e)))
            null
        }
    }

    /**
     * ADR-021 D3: only the transient class is contained. Systemic errors escape
     * `LLMCaller` wrapped precisely so they fall through this predicate;
     * cancellation and unclassified throws likewise propagate untouched. Unwraps
     * [SimulationException] — Kotlin [SimulationError] is not a [Throwable], so a
     * type-match on it directly could never fire.
     */
    private fun isTurnDegradable(e: Throwable): Boolean =
        e is SimulationException &&
            (e.error is SimulationError.RetriesExhausted || e.error is SimulationError.LlmGenerationFailed)

    /**
     * Diagnostic (non-localized) cause carried on [SimulationEvent.TurnSkipped] —
     * the same register as `llmGenerationFailed`'s payload. The App layer renders
     * its own localized narration; this string is for logs/harness transcripts.
     */
    private fun cause(e: Throwable): String {
        val err = (e as? SimulationException)?.error
        return if (err is SimulationError.LlmGenerationFailed) err.description else "retries exhausted"
    }
}
