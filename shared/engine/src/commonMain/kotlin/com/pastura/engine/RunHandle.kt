package com.pastura.engine

/**
 * The control half of the event/control boundary (ADR-023 §5.1): plain methods
 * a platform caller uses to steer an in-flight simulation.
 *
 * **Implemented by Kotlin, called by the platform** — returned from the engine's
 * `run(...)` entry point, whose other half is an `onEvent: (SimulationEvent) ->
 * Unit` callback.
 *
 * **Why the AsyncStream never crosses.** The inventory that shrinks ADR-004 §6's
 * named risk: Swift `SimulationRunner.run` is the *sole* `AsyncStream`
 * continuation owner (construction at `SimulationRunner.swift:125`, emitter
 * closure `{ continuation.yield($0) }` at `:135`); every downstream handler sees
 * only the two plain closures on `PhaseContext` (`PhaseHandler.swift:24-25`). So
 * the stream is skin-deep on the Swift side — only callbacks need to cross.
 *
 * A thin Swift adapter (`SharedEngineRunner`, PR-C) reconstructs
 * `AsyncStream<SimulationEvent>` exactly as today's shell does — yield from
 * `onEvent`, finish on a terminal event, call [cancel] from `onTermination` — so
 * **the App-facing surface (`SimulationViewModel`) does not change.**
 *
 * **Threading clause (ADR-023 §5.1, measured at the gate).** `onEvent` fires
 * from a Kotlin worker context; the adapter must not assume MainActor. Today's
 * `continuation.yield` is already thread-agnostic, so this costs nothing — but
 * it is a contract clause, not an accident.
 *
 * **Not in this gate slice:** `pauseCheck` stays Kotlin-internal (runner ->
 * handler) and never crosses, per §5.1.
 *
 * Swift counterpart: `Pastura/Pastura/Engine/SimulationRunner.swift`.
 *
 * Ported for the ADR-023 §6 Stage-2 gate slice (#501).
 */
public interface RunHandle {
    /**
     * Request a pause at the next checkpoint.
     *
     * Pausing is **cooperative and coarse**: the runner honours it at round and
     * phase boundaries, not mid-inference. Mirrors Swift `SimulationRunner`'s
     * `isPaused = true`. `SimulationEvent.SimulationPaused` is emitted exactly
     * once per pause cycle, by the runner and never by a handler.
     *
     * Idempotent. To interrupt an in-flight inference instead, the platform uses
     * its own suspend mechanism — see [notifyLLMResumed].
     */
    public fun pause()

    /** Release a [pause]. Idempotent, and safe when not paused. */
    public fun resume()

    /**
     * Cancel the run.
     *
     * Maps to structured `Job` cancellation, which composes down to every
     * in-flight [StreamHandle] (see that type's cancellation-composition
     * clause). The run ends with `SimulationEvent.ErrorEvent(SimulationError.Cancelled)`.
     *
     * Idempotent. Also released from a paused state, so a cancel while paused
     * does not deadlock.
     */
    public fun cancel()

    /**
     * Signal that the platform's suspend cycle has ended and a suspended
     * inference may re-issue (ADR-003 semantics; ADR-023 §5.2 suspension relay).
     *
     * **Why a signal and not the controller.** Swift's `SuspendController` never
     * crosses the boundary (ADR-023 Decision 3). It stays owned by the Swift
     * adapter, which runs `await controller.awaitResume()` and then calls this
     * method; Kotlin's [LLMCaller] is parked on a `CompletableDeferred` that this
     * completes. So no `suspend` crosses, and the controller's ownership simply
     * relocates to the Swift side (§5.2 invariant 4) — the App-lifecycle callers
     * (`BackgroundSimulationManager.requestSuspend`/`resume`) re-point to that
     * instance.
     *
     * **Invariant 3 (ADR-023 §5.2): lost-wakeup safety is a design constraint,
     * not luck.** It holds because `SuspendController` latches `.resumed` with no
     * awaiter and `CompletableDeferred` completes sticky — so this arriving
     * *before* the inference parks is safe. Neither side may be refactored to a
     * rendezvous primitive (e.g. a `Channel`) without re-proving this.
     *
     * Safe to call when nothing is suspended (a no-op), which is what makes the
     * adapter's cleanup paths safe.
     */
    public fun notifyLLMResumed()
}
