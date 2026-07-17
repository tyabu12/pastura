package com.pastura.engine

import com.pastura.models.Scenario
import com.pastura.models.SimulationError
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState
import kotlin.concurrent.Volatile
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
 * | `ScenarioValidator` preflight + `ScenarioSemanticLinter` (ADR-024) | Stage-3 ports (§4). Nothing gates a scenario on this side yet, which is why the ported code must not assume validator floors — see `PromptBuilder`. |
 * | Resume (`resumingFrom` seed / `startRound`) | needs the Data layer's persisted state; D2 keeps Data in Swift |
 * | `LanguageDetector` / `EngineLogger` injection | Stage-3 freight; absent from `PhaseContext` |
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
        // Release the pause gate FIRST. A run parked on the gate would otherwise
        // observe cancellation only when something resumed it — and nothing would.
        // `ensureActive()` at the checkpoint then converts this into the standard
        // cancellation path.
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
 * `@Volatile` for cross-thread visibility: written by the platform thread calling
 * [RunHandle.pause] / [RunHandle.resume], read by the run coroutine.
 */
private class PauseGate {

    @Volatile
    private var paused: CompletableDeferred<Unit>? = null

    val isPaused: Boolean get() = paused != null

    fun setPaused(value: Boolean) {
        if (value) {
            if (paused == null) paused = CompletableDeferred()
        } else {
            val current = paused
            paused = null
            current?.complete(Unit)
        }
    }

    /** Unblock a parked run so its next checkpoint can observe cancellation. */
    fun releaseForCancellation() = setPaused(false)

    /** Park until resumed. Returns immediately when not paused. */
    suspend fun awaitResume() {
        paused?.await()
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
                    ),
                    state = state,
                )
            } catch (e: SimulationException) {
                onEvent(SimulationEvent.ErrorEvent(error = e.error))
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
     * @return `true` when the run was cancelled and the caller must stop.
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
