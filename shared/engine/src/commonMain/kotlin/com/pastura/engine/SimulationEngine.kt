package com.pastura.engine

import com.pastura.models.Scenario
import com.pastura.models.SimulationError
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState
import kotlin.concurrent.atomics.AtomicReference
import kotlin.concurrent.atomics.ExperimentalAtomicApi
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch

/**
 * The engine's §5.1 entry point — the one type Swift calls to run a simulation.
 *
 * ```kotlin
 * val handle = SimulationEngine().run(scenario, backend) { event -> /* … */ }
 * handle.pause(); handle.resume(); handle.cancel(); handle.notifyLLMResumed()
 * ```
 *
 * **Plain function + callback, no suspend/Flow** (ADR-023 Decision 2). [run]
 * returns immediately with a [RunHandle]; the simulation proceeds on a coroutine
 * this type owns, and events arrive on `onEvent`. A thin Swift adapter
 * (`SharedEngineRunner`, PR-C) reconstructs `AsyncStream<SimulationEvent>` from
 * that callback exactly as today's shell does, so the App-facing surface
 * (`SimulationViewModel`) does not change.
 *
 * **Threading clause (§5.1, measured at the gate).** `onEvent` fires from a Kotlin
 * worker context — the adapter must not assume MainActor. Today's
 * `continuation.yield` is already thread-agnostic, so this costs nothing, but it
 * is a contract clause rather than an accident.
 *
 * ## Scope: the ADR-023 §6 Stage-2 gate slice's *minimal* runner loop
 *
 * **Knowingly absent** — named units, tracked on #501:
 *
 * | Absent | Why |
 * |---|---|
 * | `ScenarioValidator` preflight + `ScenarioSemanticLinter` (ADR-024) | Stage-3 ports — §4's `Load + validate` row, which the linter joined on 2026-07-19 (before that, §4 did not mention it and this row's `(§4)` citation pointed at nothing). Nothing gates a scenario on this side yet, which is why the ported code must not assume validator floors — see `PromptBuilder`. |
 * | Resume (`resumingFrom` seed / `startRound`) | needs the Data layer's persisted state; D2 keeps Data in Swift |
 * | `LanguageDetector` / `EngineLogger` injection | injection is Stage-3 freight — absent from `PhaseContext`. §4 ports both **seams only** (`LanguageDetector` in PR-3, `EngineLogger` in PR-2); the concrete `OSLogEngineLogger` / `NLLanguageDetector` stay in Swift App/ |
 *
 * Swift original: `Pastura/Pastura/Engine/SimulationRunner.swift`.
 */
public class SimulationEngine {

    /**
     * Start a simulation.
     *
     * **Returns immediately.** The run proceeds on its own coroutine; drive it via
     * the returned handle and observe it via [onEvent].
     *
     * @param scenario The scenario to execute.
     * @param backend  The platform LLM backend (§5.2).
     * @param onEvent  Receives every [SimulationEvent]. Called from a Kotlin worker
     *   context — see the threading clause above. The final event is always
     *   `SimulationCompleted` or `ErrorEvent`.
     * @return A handle for pause / resume / cancel / suspension-resume signalling.
     */
    public fun run(
        scenario: Scenario,
        backend: LLMBackend,
        onEvent: (SimulationEvent) -> Unit,
    ): RunHandle {
        val relay = SuspensionRelay()
        val gate = PauseGate()
        // SupervisorJob + Default: CPU/IO-bound orchestration, never the main
        // dispatcher — the boundary explicitly does not assume a UI thread.
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

        val job = scope.launch {
            try {
                RunLoop(scenario, backend, relay, gate, onEvent).execute()
            } catch (e: CancellationException) {
                // Swift's runner checks `Task.isCancelled` at each checkpoint and
                // emits `.error(.cancelled)`. Kotlin's idiomatic equivalent throws,
                // so the terminal event is emitted once HERE — at the boundary —
                // rather than at every checkpoint. That also covers cancellation
                // while parked on the pause gate or on the suspension relay, which
                // a per-checkpoint `isCancelled` poll would miss.
                onEvent(SimulationEvent.ErrorEvent(error = SimulationError.Cancelled))
                throw e // never swallow: the Job must still complete as cancelled
            }
        }
        return RunHandleImpl(job, gate, relay)
    }
}

/**
 * [RunHandle] over a coroutine [Job].
 *
 * Every method is idempotent and safe from any thread, because the Swift adapter's
 * lifecycle callbacks can race normal completion.
 */
private class RunHandleImpl(
    private val job: Job,
    private val gate: PauseGate,
    private val relay: SuspensionRelay,
) : RunHandle {

    override fun pause() = gate.setPaused(true)

    override fun resume() = gate.setPaused(false)

    override fun cancel() {
        // Release the gate first so a paused run stops at a checkpoint rather than
        // inside `await`. NOT required for correctness — see
        // `PauseGate.releaseForCancellation`, which records the measurement.
        gate.releaseForCancellation()
        job.cancel()
    }

    override fun notifyLLMResumed() = relay.notifyResumed()
}

/**
 * The coroutine-native replacement for Swift's `isPaused` +
 * `CheckedContinuation` + `OSAllocatedUnfairLock` pause mechanism.
 *
 * Swift stores a continuation under a lock and resumes it from the `isPaused`
 * setter. Kotlin uses the same sticky-completion trick as [SuspensionRelay]: a
 * `CompletableDeferred` that exists while paused and completes on resume, so
 * `await` is a no-op when not paused and a park when paused. Zero CPU either way —
 * matching Swift's "no polling" property.
 *
 * **The transition must be ATOMIC, not merely visible.** `@Volatile` alone gives
 * visibility; the check-then-act in [setPaused] also needs atomicity, and Swift's
 * equivalent is fully serialized under its lock — so a plain `@Volatile` field
 * would be a fidelity regression, not just a Kotlin nit. The lost-update it admits:
 * T1 `setPaused(false)` reads `d1` and stalls; T2 `setPaused(true)` sees non-null
 * and no-ops; T1 writes `null`. Net — the last call was `pause()`, the gate ends
 * UNPAUSED, and the user's pause is silently dropped. Reachable in production:
 * [RunHandleImpl.cancel] calls `setPaused(false)` from a different thread than the
 * adapter's `pause()`. A CAS loop closes it; two `pause()` racers dropping a
 * redundant deferred is harmless, a dropped `pause()` is not.
 */
@OptIn(ExperimentalAtomicApi::class)
private class PauseGate {

    private val paused = AtomicReference<CompletableDeferred<Unit>?>(null)

    val isPaused: Boolean get() = paused.load() != null

    fun setPaused(value: Boolean) {
        while (true) {
            val current = paused.load()
            if (value) {
                if (current != null) return // already paused — idempotent
                if (paused.compareAndSet(null, CompletableDeferred())) return
            } else {
                if (current == null) return // already running — idempotent
                if (paused.compareAndSet(current, null)) {
                    current.complete(Unit)
                    return
                }
            }
        }
    }

    /**
     * Unblock a parked run before cancelling it.
     *
     * **NOT load-bearing — measured.** An earlier comment here claimed a run parked
     * on the gate would otherwise never observe cancellation. That is false:
     * `CompletableDeferred.await()` is a cancellable suspension point, so
     * `job.cancel()` alone unparks it. Verified by deleting this call and re-running
     * `cancelWhilePausedDoesNotDeadlock` — still green. Kept as ordering robustness
     * (it stops the run at a checkpoint rather than relying on `await`'s
     * cancellability), not as a deadlock fix.
     */
    fun releaseForCancellation() = setPaused(false)

    /**
     * Park until resumed. Returns immediately when not paused.
     *
     * Not a park-forever TOCTOU against a concurrent resume: [setPaused] clears the
     * reference BEFORE completing the deferred, so a resume landing between the
     * `isPaused` check and here makes this read `null` and return. A resume landing
     * after this read completes the deferred it is already awaiting.
     */
    suspend fun awaitResume() {
        paused.load()?.await()
    }
}

/**
 * The round/phase loop.
 *
 * Emit order mirrors Swift's `runRoundLoop` exactly — Stage 4 compares
 * canonicalized event transcripts, so the ORDER is contract, not style.
 */
private class RunLoop(
    private val scenario: Scenario,
    private val backend: LLMBackend,
    private val relay: SuspensionRelay,
    private val gate: PauseGate,
    private val onEvent: (SimulationEvent) -> Unit,
) {

    private val dispatcher = PhaseDispatcher()

    // One gate per run: this RunLoop is constructed once per `run()`, so a plain
    // property makes the gate run-scoped and shared by every phase's PhaseContext,
    // keeping its ADR-021 D4 consecutive-skip counter run-scoped. See
    // TurnFailureGate's doc — a fresh gate per phase would silently reset it.
    private val turnGate = TurnFailureGate()

    suspend fun execute() {
        var state = SimulationState.initial(scenario)

        for (round in 1..scenario.rounds) {
            checkPaused(round, emptyList())

            // Swift counts `eliminated.values.filter { !$0 }` — agents present in
            // the map and NOT eliminated. An agent absent from the map is not
            // counted, which is why `initial` seeds every agent to false.
            val activeCount = state.eliminated.values.count { !it }
            if (activeCount < 2) {
                onEvent(
                    SimulationEvent.Summary(
                        text = "Simulation ended early: fewer than 2 active agents remaining",
                    ),
                )
                break
            }

            state = state.copy(
                conversationLog = emptyList(),
                pairings = emptyList(),
                currentRound = round,
                variables = state.variables + ("current_round" to round.toString()),
            )

            onEvent(SimulationEvent.RoundStarted(round = round, totalRounds = scenario.rounds))

            val afterPhases = executePhases(state, round) ?: return
            state = afterPhases

            onEvent(SimulationEvent.RoundCompleted(round = round, scores = state.scores))
            // Resumable checkpoint: `state.currentRound == round` here, so a paused
            // run can later resume from `currentRound + 1`. Emitted only after the
            // round FULLY completes — a pause mid-round leaves the prior round's
            // checkpoint as the resume point (round-boundary continuation).
            onEvent(SimulationEvent.RoundCheckpoint(state = state))
        }

        onEvent(SimulationEvent.SimulationCompleted)
    }

    /** @return the next state, or `null` when a phase errored and the run must stop. */
    private suspend fun executePhases(entryState: SimulationState, round: Int): SimulationState? {
        var state = entryState
        for ((phaseIndex, phase) in scenario.phases.withIndex()) {
            val phasePath = listOf(phaseIndex)
            checkPaused(round, phasePath)

            onEvent(SimulationEvent.PhaseStarted(phaseType = phase.type, phasePath = phasePath))

            state = try {
                val handler = dispatcher.handler(phase.type)
                handler.execute(
                    context = PhaseContext(
                        scenario = scenario,
                        phase = phase,
                        backend = backend,
                        suspensionRelay = relay,
                        emitter = onEvent,
                        pauseCheck = { nested -> checkPaused(round, nested) },
                        phasePath = phasePath,
                        turnGate = turnGate,
                    ),
                    state = state,
                )
            } catch (e: CancellationException) {
                // Must precede the Throwable arm — CancellationException IS a
                // Throwable, and swallowing it would break cancellation.
                throw e
            } catch (e: SimulationException) {
                onEvent(SimulationEvent.ErrorEvent(error = e.error))
                return null
            } catch (e: Throwable) {
                // Mirrors Swift's catch-all: `error as? SimulationError ??
                // .llmGenerationFailed(description: readableDescription(error))`.
                //
                // Load-bearing despite nothing in commonMain throwing anything else:
                // `LLMBackend` / `StreamCallbacks` are PLATFORM-implemented, so a
                // throw out of a Swift/ObjC adapter lands exactly here. Without this
                // arm it would escape RunLoop, miss the launch boundary's
                // CancellationException-only catch, and reach a scope with no
                // CoroutineExceptionHandler — which on Kotlin/Native TERMINATES THE
                // PROCESS (an app crash where Swift emits an ErrorEvent), and would
                // also break run()'s "the final event is always SimulationCompleted
                // or ErrorEvent" contract, hanging PR-C's AsyncStream forever.
                onEvent(
                    SimulationEvent.ErrorEvent(
                        error = SimulationError.LlmGenerationFailed(
                            description = e.message ?: e.toString(),
                        ),
                    ),
                )
                return null
            }

            onEvent(SimulationEvent.PhaseCompleted(phaseType = phase.type, phasePath = phasePath))
        }
        return state
    }

    /**
     * Honour a pending pause, and report cancellation.
     *
     * Emits `SimulationPaused` exactly once per pause cycle. The runner is the
     * SOLE emitter of that event — handlers reach this only through
     * [PhaseContext.pauseCheck], never by emitting it themselves.
     *
     * Cancellation surfaces as a thrown `CancellationException` (from
     * [ensureActive]), not as a return value — see [PhaseContext.pauseCheck] for
     * why the Swift `Bool` does not port.
     */
    private suspend fun checkPaused(round: Int, phasePath: List<Int>) {
        // Throws CancellationException, which the run boundary turns into
        // `ErrorEvent(Cancelled)` — see SimulationEngine.run.
        coroutineContext.ensureActive()
        if (!gate.isPaused) return

        onEvent(SimulationEvent.SimulationPaused(round = round, phasePath = phasePath))
        gate.awaitResume()
        coroutineContext.ensureActive()
    }
}
