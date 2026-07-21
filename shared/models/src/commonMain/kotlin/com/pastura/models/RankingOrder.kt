package com.pastura.models

/**
 * Deterministic "who is #1" ordering shared by the result card
 * (`SimulationResultCard`) and viewer-prediction scoring (`ViewerPredictionLogic`),
 * introduced in #915 so the displayed leader and the scored leader can never
 * diverge.
 *
 * Highest value wins; ties break by name descending, giving a stable
 * run-to-run winner (a bare `max` would pick a hash-order-dependent tie-winner
 * that could disagree with the card).
 *
 * Name **descending** is the canonical order shared with the engine's vote
 * tie-break (`VoteTally.winner`, #1056/#1057): the displayed/predicted leader
 * then matches the agent the engine actually eliminates on a top-slot tie
 * (#1087).
 *
 * Kotlin port of `Pastura/Pastura/Models/RankingOrder.swift`.
 *
 * Not `@Serializable` — a namespace of pure functions, not a serialized data
 * type. Its Swift↔Kotlin parity is behavioural (see `RankingOrderTests`), since
 * golden JSON parity has nothing to encode here.
 */
public object RankingOrder {
    /**
     * Whether `lhs` outranks `rhs`: higher value first, then name descending as
     * the deterministic tiebreak.
     */
    public fun isOrderedBefore(
        lhsName: String,
        lhsValue: Int,
        rhsName: String,
        rhsValue: Int,
    ): Boolean = if (lhsValue != rhsValue) lhsValue > rhsValue else lhsName > rhsName

    /**
     * The single leader among [roster] by [values] (missing keys count as 0),
     * or `null` when [roster] is empty.
     */
    public fun leader(values: Map<String, Int>, roster: List<String>): String? {
        if (roster.isEmpty()) return null
        return roster.sortedWith { a, b ->
            when {
                isOrderedBefore(a, values[a] ?: 0, b, values[b] ?: 0) -> -1
                isOrderedBefore(b, values[b] ?: 0, a, values[a] ?: 0) -> 1
                else -> 0
            }
        }.first()
    }
}
