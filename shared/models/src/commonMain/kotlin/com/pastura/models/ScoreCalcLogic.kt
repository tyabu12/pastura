package com.pastura.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Identifier for a built-in scoring logic used by `score_calc` phases.
 *
 * The actual implementations live in `Engine/ScoringLogic/`. Custom
 * (author-supplied) logic is Phase 2 scope.
 *
 * Kotlin port of `Pastura/Pastura/Models/ScoreCalcLogic.swift`, which is the
 * single source of truth for the built-in set.
 */
@Serializable
public enum class ScoreCalcLogic {
    /**
     * Prisoner's dilemma payoff matrix.
     * cooperate/cooperate = 3,3 | cooperate/betray = 0,5 | betray/betray = 1,1
     */
    @SerialName("prisoners_dilemma")
    PRISONERS_DILEMMA,

    /** Count votes per agent and add to scores. */
    @SerialName("vote_tally")
    VOTE_TALLY,

    /** Check if the most-voted agent matches the minority (word wolf) agent. */
    @SerialName("wordwolf_judge")
    WORDWOLF_JUDGE,

    /**
     * Reward agents whose last `choose` action matched the injected event's
     * favored action. Deterministic, code-enforced event-conditional scoring
     * for `choose` games — decouples "who read the event best" from an LLM
     * peer vote. See `EventReactivePayoffLogic` and #931.
     */
    @SerialName("event_reactive")
    EVENT_REACTIVE,

    /**
     * Generic two-player payoff table authored in scenario YAML (`payoff:`),
     * matched positionally against a round-robin `choose`'s pairings. Supersedes
     * the hardcoded matrix of [PRISONERS_DILEMMA] (kept as a legacy shim) and
     * unblocks localized option tokens + chicken / stag-hunt variants with no
     * engine change. See `PairwisePayoffLogic`, [PayoffRule], and ADR-027.
     */
    @SerialName("pairwise_payoff")
    PAIRWISE_PAYOFF,
}
