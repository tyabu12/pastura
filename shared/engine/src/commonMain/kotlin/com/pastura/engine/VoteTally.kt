package com.pastura.engine

import com.pastura.models.RankingOrder

/**
 * Vote-tally helpers shared across the engine's most-voted-agent sites.
 *
 * Consolidates the canonical tie-break so a future change can't reintroduce the
 * per-launch divergence #1056/#1057 fixed: `EliminateHandler`,
 * [WordwolfJudgeLogic], and `ConditionEvaluator`'s `vote_winner` derivation all
 * resolve a tie to the same agent.
 *
 * Swift original: `Pastura/Pastura/Engine/VoteTally.swift`. Ported for the
 * ADR-023 Stage-3 PR-1 score_calc slice (#501).
 */
internal object VoteTally {
    /**
     * The winning agent by the canonical deterministic tie-break:
     * (count desc, name desc). Returns `null` for empty input.
     *
     * Delegates to [RankingOrder] (Models) so the comparator has a single
     * definition shared with the result card and viewer-prediction scoring
     * (#1087). Returns the full `(key, value)` pair so a call site that needs
     * the vote count can read `.second` without a second lookup.
     */
    fun winner(voteResults: Map<String, Int>): Pair<String, Int>? {
        val key = RankingOrder.leader(voteResults, voteResults.keys.toList()) ?: return null
        val value = voteResults[key] ?: return null
        return key to value
    }
}
