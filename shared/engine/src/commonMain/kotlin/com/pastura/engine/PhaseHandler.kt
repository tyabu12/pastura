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
 * ## Knowingly absent — remaining named deferral
 *
 * `detector` / `logger` are now fields below — B0b wired their [LLMCaller]
 * consumers (language-adherence retry + the `StreamingDiag` channel). But being a
 * field is not the same as being fed: the sole production constructor —
 * `SimulationEngine`'s `RunLoop`, `SimulationEngine.kt` — still builds this context
 * with the defaults (`detector = null`, `logger = NoopEngineLogger`). So in the
 * real Kotlin run path the adherence check is **dormant** and `StreamingDiag` emits
 * nowhere; threading the real `NLLanguageDetector` + OSLog adapter across the K/N
 * boundary is later Stage-3 freight (#501). Named here, not a silent gap. (The
 * ADR-021 `turnGate`, once one of these, is now fed by the runner — B0a.)
 *
 * Swift original: `Pastura/Pastura/Engine/PhaseHandler.swift`.
 * Ported for the ADR-023 §6 Stage-2 gate slice (#501).
 *
 * @property scenario  The scenario being run.
 * @property phase     The phase this handler is executing.
 * @property backend   The platform LLM backend (§5.2).
 * @property phasePath This handler's position in the scenario. Top-level handlers
 *   run with `[K]`; sub-phases inside a conditional run with `[K, N]`, built by
 *   [ConditionalHandler] — the only nesting handler.
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
     * a pause is honoured at sub-phase granularity. [ConditionalHandler] is the sole
     * consumer, and relies on the throw above as its *only* cancellation check — it
     * deliberately carries no `ensureActive()` of its own. Weakening this contract
     * would therefore leave a branch of **code phases** with no cancellation check
     * at all; a branch containing an LLM sub-phase would still unwind at
     * [LLMCaller]'s own suspension points, and that asymmetry is exactly what would
     * make the gap easy to miss.
     */
    val pauseCheck: suspend (phasePath: List<Int>) -> Unit,
    val phasePath: List<Int>,
    /**
     * Run-scoped ADR-021 turn-failure containment. LLM phase handlers route each
     * agent turn's `LLMCaller.call` through [TurnFailureGate.attempt] so a
     * turn-degradable failure *skips* that agent's turn (degrade by omission, D2)
     * while systemic errors, cancellation, and the D4 breaker abort the run.
     *
     * **No default — mirrors Swift `PhaseContext`'s `turnGate`, for the same
     * reason.** The gate carries a run-scoped consecutive-skip counter, so exactly
     * ONE instance is created per run and shared by every phase's context (the
     * runner's `RunLoop` does this); a per-context default would silently reset the
     * counter each phase. Code phases never touch it — the same shape as Swift,
     * where the code phases ignore it too.
     */
    val turnGate: TurnFailureGate,
    /**
     * Optional language-of-output detector for the ADR-010 Step E adherence check
     * (see [LLMCaller.call]). `null` = skip the check — the seam is unwired in the
     * Kotlin run path today (see § "Knowingly absent"), and the concrete
     * `NLLanguageDetector` stays Swift App-side per ADR-010 D8. Defaulted so
     * construction sites that don't feed it stay unchanged.
     */
    val detector: LanguageDetector? = null,
    /**
     * Diagnostic seam threaded to [LLMCaller] (the `StreamingDiag` channel). The
     * concrete `OSLogEngineLogger` stays Swift App-side; [NoopEngineLogger] is the
     * default so the Engine stays OSLog-free and non-App consumers (tests, the
     * ADR-013 harness) need no wiring. Defaulted for the same construction-site
     * reason as [detector].
     */
    val logger: EngineLogger = NoopEngineLogger(),
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
