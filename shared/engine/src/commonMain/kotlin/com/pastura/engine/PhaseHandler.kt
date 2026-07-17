package com.pastura.engine

import com.pastura.models.Phase
import com.pastura.models.Scenario
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState

/**
 * The read-only parameters every phase handler receives.
 *
 * **`internal`, unlike Swift's `public` — deliberate.** Swift marks
 * `PhaseContext`/`PhaseHandler` public for future SPM module extraction
 * (CLAUDE.md § Access Modifiers). Kotlin's equivalent concern is the *exported
 * K/N surface*, and this type must not be on it: §5.1 states `pauseCheck` "stays
 * Kotlin-internal (runner -> handler), never crossing", and no Swift code ever
 * implements a [PhaseHandler]. Keeping the handler contract `internal` keeps the
 * boundary to exactly the §5.1/§5.2 types, which is also what gate measurement
 * (iii) — the K/N shim-budget re-measure — is counting. `commonTest` still sees
 * these (test source sets are associated with `commonMain`).
 *
 * ## Divergences from the Swift original, all deliberate
 *
 * - **`backend` replaces `llm: LLMService`** — the §5.2 boundary type.
 * - **`suspensionRelay` replaces `suspendController`.** Swift threads a
 *   `SuspendController` through here as a pass-through for `LLMCaller`; that
 *   object never crosses K/N (ADR-023 Decision 3) and its ownership relocates to
 *   the Swift adapter (§5.2 invariant 4). Kotlin threads the waiting half instead
 *   — same pass-through shape, so handlers still just forward it to
 *   `LLMCaller.call` without interacting with it.
 * - **No `state: inout`.** Kotlin [SimulationState] is an immutable `data class`,
 *   so [PhaseHandler.execute] returns the next state rather than mutating in
 *   place (the #1063 Stage-2-pre precedent).
 *
 * ## Knowingly absent from this gate slice
 *
 * Each is a *named* deferral, tracked on #501 — not a silent field drop:
 *
 * - **`turnGate`** (ADR-021 `TurnFailureGate`) — a turn-degradable LLM failure
 *   aborts the run here instead of skipping the agent's turn. Pulling it in would
 *   also pull `turnSkipped` + `turnFailureLimitReached` onto the slice path.
 * - **`detector`** (`LanguageDetector`) — ADR-010 Step E language-adherence retry
 *   is named Stage-3 freight in ADR-023 §6.
 * - **`logger`** (`EngineLogger`, the #501 S0.2 seam) — nothing in the slice logs;
 *   the Kotlin engine has no OSLog to keep out.
 *
 * Swift original: `Pastura/Pastura/Engine/PhaseHandler.swift`.
 * Ported for the ADR-023 §6 Stage-2 gate slice (#501).
 *
 * @property scenario  The scenario being run.
 * @property phase     The phase this handler is executing.
 * @property backend   The platform LLM backend (§5.2).
 * @property phasePath This handler's position in the scenario. Top-level handlers
 *   run with `[K]`; sub-phases inside a conditional would run with `[K, N]`. No
 *   nesting handler is in this slice, so it is always single-element here.
 */
internal class PhaseContext(
    val scenario: Scenario,
    val phase: Phase,
    val backend: LLMBackend,
    /**
     * Pass-through for [LLMCaller] only. Handlers must not interact with it —
     * just forward it, exactly as Swift handlers forward `suspendController`.
     */
    val suspensionRelay: SuspensionRelay,
    /**
     * Emits a simulation event. Reaches the platform via the §5.1 `onEvent`
     * callback, so it may be called from any coroutine context.
     */
    val emitter: (SimulationEvent) -> Unit,
    /**
     * Honours a pending pause request, suspending until resumed.
     *
     * A narrow bridge onto the runner's internal `checkPaused`, so that
     * `SimulationEvent.SimulationPaused` has exactly one emitter — the runner,
     * never a handler.
     *
     * **Returns `Unit`, where Swift returns `Bool`.** Swift's `Bool` means
     * "cancelled while paused — return early", because Swift polls
     * `Task.isCancelled` and must hand the verdict back. Kotlin cancellation
     * *throws*: this call raises `CancellationException`, which unwinds the handler
     * on its own. A `Bool` here would be vestigial, and worse — a handler could
     * ignore it and keep running after cancellation, which the throw makes
     * structurally impossible.
     *
     * Handlers that dispatch nested sub-phases must call this between each one so
     * a pause is honoured at sub-phase granularity. No such handler exists in this
     * slice, so nothing calls it yet — it is part of the contract the runner
     * provides and Stage 3's `ConditionalHandler` consumes.
     */
    val pauseCheck: suspend (phasePath: List<Int>) -> Unit,
    val phasePath: List<Int>,
)

/**
 * A handler that executes one type of simulation phase.
 *
 * Each [com.pastura.models.PhaseType] has a corresponding handler registered in
 * [PhaseDispatcher]. LLM phases call the backend; code phases operate
 * deterministically on state.
 *
 * Swift original: `Pastura/Pastura/Engine/PhaseHandler.swift`.
 */
internal interface PhaseHandler {
    /**
     * Execute this phase for the current round.
     *
     * @param context The read-only phase context.
     * @param state   The state at phase entry.
     * @return The state after this phase. Swift mutates `inout`; Kotlin returns a
     *   `copy`, so callers must use the return value — a handler's changes are
     *   invisible otherwise.
     * @throws SimulationException on a failure that should abort the run.
     */
    suspend fun execute(context: PhaseContext, state: SimulationState): SimulationState
}
