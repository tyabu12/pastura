package com.pastura.engine

import com.pastura.models.PayoffRule
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState

/**
 * Prisoner's dilemma scoring logic — a **legacy shim** over [PairwisePayoffLogic]
 * (ADR-027).
 *
 * Kept indefinitely, NOT because prisoner's dilemma is special, but because a
 * user's "Copy & Edit" clone on a shipped device may carry
 * `logic: prisoners_dilemma` in its saved YAML; deleting the case would make
 * that record unopenable. New scenarios should use `pairwise_payoff` with a YAML
 * `payoff:` table.
 *
 * The shim hands [PairwisePayoffLogic] the fixed English payoff table below.
 * That table is the game's rule set — it must **not** be trimmed: dropping the
 * `[betray, betray] → [1, 1]` row would score mutual defection as 0 in shipped
 * content (ADR-027).
 *
 * Swift original:
 * `Pastura/Pastura/Engine/ScoringLogic/PrisonersDilemmaLogic.swift`.
 */
internal class PrisonersDilemmaLogic {

    fun calculate(
        state: SimulationState,
        emitter: (SimulationEvent) -> Unit,
    ): SimulationState = PairwisePayoffLogic().calculate(state, legacyTable, emitter)

    internal companion object {
        /**
         * The legacy prisoner's-dilemma payoff matrix. Exhaustive over
         * `{cooperate, betray}²`, so for all shipped content every pairing
         * matches a row — the shim is behaviourally identical to the
         * pre-ADR-027 hardcoded `switch`.
         */
        val legacyTable: List<PayoffRule> = listOf(
            PayoffRule(`when` = listOf("cooperate", "cooperate"), points = listOf(3, 3)),
            PayoffRule(`when` = listOf("cooperate", "betray"), points = listOf(0, 5)),
            PayoffRule(`when` = listOf("betray", "cooperate"), points = listOf(5, 0)),
            PayoffRule(`when` = listOf("betray", "betray"), points = listOf(1, 1)),
        )
    }
}
