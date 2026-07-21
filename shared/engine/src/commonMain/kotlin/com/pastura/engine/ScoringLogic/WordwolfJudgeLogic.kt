package com.pastura.engine

import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState

/**
 * Word wolf judge scoring logic.
 *
 * Checks if the most-voted agent matches `state.variables["wolf_name"]`. Emits a
 * summary describing the result in the caller-supplied effective Engine language
 * (the caller passes `scenario.engineLanguage`, ADR-010 D5 / D6 row 1). Does NOT
 * mutate scores → returns `state` unchanged.
 *
 * **String formatting divergence from Swift (commonMain stdlib trap):** the
 * Swift original uses `String(format: "…%@…%lld票…", name, count)`. Java-style
 * `String.format` is not available in commonMain, so this reproduces the SAME
 * output via Kotlin string interpolation (`%@`→`$name`, `%lld`→`$count`). The
 * four templates and the empty-votes messages are byte-for-byte identical to the
 * Swift literals.
 *
 * Swift original:
 * `Pastura/Pastura/Engine/ScoringLogic/WordwolfJudgeLogic.swift`.
 */
internal class WordwolfJudgeLogic {

    fun calculate(
        state: SimulationState,
        language: String,
        emitter: (SimulationEvent) -> Unit,
    ): SimulationState {
        if (state.voteResults.isEmpty()) {
            emitter(
                SimulationEvent.Summary(
                    text = pickLanguage(language, ja = "投票結果がありません", en = "No votes recorded"),
                ),
            )
            return state
        }

        // Most-voted agent via the shared canonical tie-break (count desc, name
        // desc) — a bare `max` left ties resolved by hash order, so a tied
        // word-wolf game reported "wolf found" vs "wolf escaped" per launch (#1057).
        val mostVoted = VoteTally.winner(state.voteResults)?.first ?: ""
        val wolf = state.variables["wolf_name"] ?: "?"
        val voteCount = state.voteResults[mostVoted] ?: 0

        val text = if (mostVoted == wolf) {
            pickLanguage(
                language,
                ja = "最多得票: $mostVoted (${voteCount}票) — 多数派の勝ち！ウルフを見破った！",
                en = "Most votes: $mostVoted ($voteCount) — Majority wins! The wolf was found.",
            )
        } else {
            pickLanguage(
                language,
                ja = "最多得票: $mostVoted (${voteCount}票) — ウルフの勝ち！逃げ切った！",
                en = "Most votes: $mostVoted ($voteCount) — The wolf wins! Escaped detection.",
            )
        }
        emitter(SimulationEvent.Summary(text = text))
        return state
    }
}
