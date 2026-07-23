package com.pastura.engine

import com.pastura.models.ScoreCalcLogic
import com.pastura.models.SimulationError
import com.pastura.models.SimulationState

/**
 * Handles `score_calc` phases by dispatching to built-in scoring logics.
 *
 * Switches on `phase.logic` to delegate to the appropriate scoring implementation.
 *
 * A code phase — it never touches [PhaseContext.turnGate] (no LLM turn), matching
 * Swift, where the code phases ignore it too.
 *
 * **No `state: inout`.** Kotlin [SimulationState] is an immutable `data class`, so
 * this RETURNS the state produced by the dispatched logic rather than mutating in
 * place. Every `ScoringLogic.calculate(...)` already returns the next state, so
 * the `when` expression's value is returned directly — returning the input `state`
 * instead would compile cleanly and silently drop every score change.
 *
 * The `when` is an EXPRESSION with **no `else`** so a future sixth
 * [ScoreCalcLogic] case compile-breaks here, matching Swift's no-`default` switch.
 *
 * Swift original: `Pastura/Pastura/Engine/Phases/ScoreCalcHandler.swift`.
 */
internal class ScoreCalcHandler : PhaseHandler {

    override suspend fun execute(context: PhaseContext, state: SimulationState): SimulationState {
        val logic = context.phase.logic ?: throw SimulationException(
            SimulationError.ScenarioValidationFailed(
                message = "score_calc phase missing 'logic' field",
            ),
        )

        return when (logic) {
            ScoreCalcLogic.PRISONERS_DILEMMA ->
                PrisonersDilemmaLogic().calculate(state, context.emitter)

            ScoreCalcLogic.VOTE_TALLY ->
                VoteTallyLogic().calculate(state, context.emitter)

            ScoreCalcLogic.WORDWOLF_JUDGE ->
                WordwolfJudgeLogic().calculate(
                    state,
                    language = context.scenario.engineLanguage,
                    emitter = context.emitter,
                )

            ScoreCalcLogic.EVENT_REACTIVE ->
                // v1 uses the companion-variable convention keyed off the default
                // event variable name (`current_event__favors`). Honoring a custom
                // `as:` on the event_inject phase (via a phase-level
                // `favored_variable:` field) is deferred — see #931.
                EventReactivePayoffLogic().calculate(
                    state,
                    favoredVariable = EventInjectHandler.favoredVariableName(
                        EventInjectHandler.defaultVariableName,
                    ),
                    emitter = context.emitter,
                )

            ScoreCalcLogic.PAIRWISE_PAYOFF ->
                // An absent `payoff:` is an empty table (all pairings score nothing) —
                // flagged by the semantic linter (R20a), not a dispatch-time throw.
                PairwisePayoffLogic().calculate(
                    state,
                    payoff = context.phase.payoff ?: emptyList(),
                    emitter = context.emitter,
                )
        }
    }
}
