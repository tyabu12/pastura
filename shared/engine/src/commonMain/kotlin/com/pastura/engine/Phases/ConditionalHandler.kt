package com.pastura.engine

import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.SimulationError
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState

/**
 * Handles `conditional` phases — evaluates a DSL expression against the current
 * simulation state and dispatches to `thenPhases` or `elsePhases`.
 *
 * The only handler that nests. That makes it the first and only consumer of two
 * [PhaseContext] mechanisms the runner has provided since the Stage-2 gate slice
 * with nothing calling them — [PhaseContext.pauseCheck] and a `[outerK, innerN]`
 * [PhaseContext.phasePath] — and the only handler that emits lifecycle events of
 * its own (a convention over the shared `emitter`, not a third field).
 *
 * ## Sub-dispatch
 *
 * Owns its own [subHandlers] map rather than a [PhaseDispatcher]. That is load
 * bearing, not a style choice: [PhaseDispatcher] eagerly constructs every handler,
 * itself included, so a `ConditionalHandler` holding a `PhaseDispatcher()` would
 * recurse forever at construction — the map builds a `ConditionalHandler`, which
 * builds a `PhaseDispatcher`, and so on. The Swift original's class comment claims
 * it "owns a private `PhaseDispatcher`"; it does not, and this port corrects that
 * claim on both sides rather than inheriting it.
 *
 * The map omits **five** of the 14 phase types, for two different reasons:
 *
 * - `conditional` — enforces the depth-1 rule structurally, and avoids the
 *   construction cycle above.
 * - `reflect`, `whisper`, `relationship_update`, `narrate` — not supported inside a
 *   branch (`engine.md` § "Adding a new `PhaseType`" records all four as *reject*).
 *
 * `event_inject` **is** included, so curators can gate event injection on scenario
 * state ("only inject in round 3+").
 *
 * ⚠️ **On this side the missing-key throw is the SOLE enforcement, not a backstop.**
 * Swift's `ScenarioValidator.validateBranch` rejects a disallowed branch phase at
 * load time and the Swift dictionary is merely the runtime backstop. Kotlin has no
 * `ScenarioValidator` yet (Stage-3 freight, #501), so nothing upstream rejects
 * anything: every branch-policy violation reaches dispatch and is caught here or
 * not at all.
 *
 * ## Nested lifecycle events
 *
 * `phaseStarted` / `phaseCompleted` for each sub-phase are emitted **by this
 * handler**, at paths of the form `[outerK, innerN]`, so a consumer can tell a
 * nested phase from a top-level phase of the same `phaseType`. The conditional's
 * own outer pair comes from the runner.
 *
 * Two orderings inside [runBranch] are load-bearing and easy to lose in a port:
 *
 * 1. The sub-handler is **resolved before** `phaseStarted` is emitted, so a
 *    rejected phase type throws without leaving a started-without-completed event
 *    in the stream.
 * 2. The `catch` **emits `phaseCompleted` before rethrowing**, so a throwing
 *    sub-handler still pairs.
 *
 * Note what (2) does *not* extend to: on a throw the runner emits `.error` and
 * returns **without** the outer `phaseCompleted` (`SimulationEngine.kt`'s `RunLoop`,
 * and `SimulationRunner.swift` identically). So the outer pair does not bracket the
 * failure path — the Swift comment asserting it does is wrong, and is corrected in
 * the same change as this port.
 *
 * ## Divergences from the Swift original, all deliberate
 *
 * - **No `Task.isCancelled` poll.** Swift checks it at the loop head and returns
 *   early. Kotlin cancellation *throws*, and [PhaseContext.pauseCheck] — called at
 *   the same loop position — raises it as part of its documented contract, so a
 *   redundant `ensureActive()` here would assert that contract cannot be trusted.
 * - **Cancellation has an observably different event tail.** Swift's two early
 *   returns exit `execute` *normally*, so the runner goes on to emit
 *   `phaseCompleted(.conditional)`; Kotlin unwinds the run instead. A Stage-4 parity
 *   harness comparing transcripts will see this — it is a divergence, not an
 *   implementation detail.
 * - **The `catch` is `Throwable`, wider than a typical port.** [NarrateHandler]
 *   narrowed *its* catch because that catch **absorbs** the error; this one rethrows
 *   unconditionally, so nothing is swallowed at any breadth. Narrower here would let
 *   `CancellationException` escape between the `phaseStarted` emit and the pairing,
 *   producing a dangling `phaseStarted([k, n])` Swift never produces.
 * - **State threads through the loop.** Kotlin handlers return state rather than
 *   mutating `inout`, so each sub-phase's result feeds the next and [execute]
 *   returns the accumulation — see [PhaseHandler].
 *
 * Swift original: `Pastura/Pastura/Engine/Phases/ConditionalHandler.swift`.
 * Ported for the ADR-023 KMP Engine migration (#501, #1342).
 */
internal class ConditionalHandler : PhaseHandler {

    private val evaluator = ConditionEvaluator()

    /**
     * Phase types a conditional branch may contain. See the class doc for why five
     * are absent and why this is a private map rather than a [PhaseDispatcher].
     */
    private val subHandlers: Map<PhaseType, PhaseHandler> = mapOf(
        PhaseType.SPEAK_ALL to SpeakAllHandler(),
        PhaseType.SPEAK_EACH to SpeakEachHandler(),
        PhaseType.VOTE to VoteHandler(),
        PhaseType.CHOOSE to ChooseHandler(),
        PhaseType.SCORE_CALC to ScoreCalcHandler(),
        PhaseType.ASSIGN to AssignHandler(),
        PhaseType.ELIMINATE to EliminateHandler(),
        PhaseType.SUMMARIZE to SummarizeHandler(),
        PhaseType.EVENT_INJECT to EventInjectHandler(),
    )

    override suspend fun execute(context: PhaseContext, state: SimulationState): SimulationState {
        val expression = context.phase.condition ?: ""
        // Throws `ScenarioValidationFailed` on a malformed or empty expression.
        // Reachable here, unlike Swift, where `ScenarioValidator` shadows it at load.
        val evaluation = evaluator.evaluate(expression, state, context.scenario)

        // Warnings first, then the verdict: a consumer reading the stream sees why a
        // runtime-absent operand forced `false` before it sees the `false`.
        for (warning in evaluation.warnings) {
            context.emitter(SimulationEvent.Summary(text = "⚠️ $warning"))
        }

        context.emitter(
            SimulationEvent.ConditionalEvaluated(condition = expression, result = evaluation.value),
        )

        val branch =
            if (evaluation.value) context.phase.thenPhases.orEmpty()
            else context.phase.elsePhases.orEmpty()

        return runBranch(branch, context, state)
    }

    /**
     * Runs the selected branch's sub-phases, threading pause checks, lifecycle
     * events and state through at `[outerK, innerN]` paths.
     *
     * An absent branch is an empty list here, so this is a silent no-op returning
     * [state] unchanged — the `conditionalEvaluated` event is the only trace.
     */
    private suspend fun runBranch(
        phases: List<Phase>,
        context: PhaseContext,
        state: SimulationState,
    ): SimulationState {
        var current = state

        for ((innerIndex, subPhase) in phases.withIndex()) {
            val innerPath = context.phasePath + innerIndex

            // Honours a pause at sub-phase granularity, and raises
            // CancellationException if the run was cancelled — this call is why no
            // separate cancellation poll is needed (see the class doc).
            context.pauseCheck(innerPath)

            // Resolve BEFORE emitting `phaseStarted`, so a rejected phase type leaves
            // no dangling started-without-completed event.
            val handler = subHandlers[subPhase.type] ?: throw SimulationException(
                SimulationError.ScenarioValidationFailed(
                    message = "Phase type '${subPhase.type.serialName()}' is not allowed inside a " +
                        "conditional branch (depth-1 rule).",
                ),
            )

            context.emitter(
                SimulationEvent.PhaseStarted(phaseType = subPhase.type, phasePath = innerPath),
            )

            // Scope each sub-phase's context to itself — the sub-handler sees the
            // nested path as its own `phasePath`. Everything else is the PARENT's
            // instance. `turnGate` most of all (ADR-021 D4): a fresh gate here would
            // reset the run-scoped consecutive-skip counter inside branches. Note
            // `detector` and `logger` are DEFAULTED on `PhaseContext`, so omitting
            // either would compile clean and silently unwire them for nested phases.
            val subContext = PhaseContext(
                scenario = context.scenario,
                phase = subPhase,
                backend = context.backend,
                suspensionRelay = context.suspensionRelay,
                emitter = context.emitter,
                pauseCheck = context.pauseCheck,
                phasePath = innerPath,
                turnGate = context.turnGate,
                detector = context.detector,
                logger = context.logger,
            )

            current = try {
                handler.execute(subContext, current)
            } catch (t: Throwable) {
                // Pair the lifecycle even on a throw, then rethrow so the runner
                // surfaces the error. Deliberately `Throwable` — see the class doc.
                context.emitter(
                    SimulationEvent.PhaseCompleted(phaseType = subPhase.type, phasePath = innerPath),
                )
                throw t
            }

            context.emitter(
                SimulationEvent.PhaseCompleted(phaseType = subPhase.type, phasePath = innerPath),
            )
        }

        return current
    }
}
