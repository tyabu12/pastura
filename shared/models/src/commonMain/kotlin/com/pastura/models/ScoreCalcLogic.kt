package com.pastura.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Identifier for a built-in scoring logic used by `score_calc` phases.
 *
 * MVP includes exactly 3 scoring logics. The actual implementations
 * live in `Engine/ScoringLogic/`. Custom logic is Phase 2 scope.
 *
 * Kotlin port of `Pastura/Pastura/Models/ScoreCalcLogic.swift`.
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
}
