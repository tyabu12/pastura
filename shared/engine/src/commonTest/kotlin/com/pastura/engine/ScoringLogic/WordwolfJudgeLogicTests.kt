package com.pastura.engine

import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Kotlin sibling of Swift's `WordwolfJudgeLogicTests`.
 *
 * Includes rendered-string-equality assertions (ja + en) that pin the Swift
 * `String(format:)` → Kotlin interpolation parity.
 *
 * Ported for the ADR-023 Stage-3 PR-1 score_calc slice (#501).
 */
class WordwolfJudgeLogicTests {

    private val logic = WordwolfJudgeLogic()

    private fun summaries(
        state: SimulationState,
        language: String,
    ): List<String> {
        val events = mutableListOf<SimulationEvent>()
        logic.calculate(state, language) { events += it }
        return events.filterIsInstance<SimulationEvent.Summary>().map { it.text }
    }

    @Test
    fun majorityWinsWhenWolfMostVoted() {
        val state = SimulationState(
            voteResults = mapOf("Wolf" to 3, "Other" to 1),
            variables = mapOf("wolf_name" to "Wolf"),
        )
        val out = summaries(state, "ja")
        assertEquals(1, out.size)
        // Rendered-string parity (ja, wolf found).
        assertEquals("最多得票: Wolf (3票) — 多数派の勝ち！ウルフを見破った！", out[0])
    }

    @Test
    fun wolfWinsWhenNotDetected() {
        val state = SimulationState(
            voteResults = mapOf("Innocent" to 3, "Wolf" to 1),
            variables = mapOf("wolf_name" to "Wolf"),
        )
        assertTrue(summaries(state, "ja")[0].contains("ウルフの勝ち"))
    }

    @Test
    fun tieResolvesToStableWinner() {
        // Canonical tie-break (count desc, name desc) → Bob wins; Bob != wolf
        // (Alice) → wolf escapes deterministically on every call.
        fun run(): String {
            val state = SimulationState(
                voteResults = mapOf("Alice" to 2, "Bob" to 2),
                variables = mapOf("wolf_name" to "Alice"),
            )
            return summaries(state, "ja").firstOrNull() ?: ""
        }
        val first = run()
        assertTrue(first.contains("Bob"))
        assertTrue(first.contains("ウルフの勝ち"))
        assertFalse(first.contains("Alice"))
        assertEquals(first, run())
        assertEquals(first, run())
    }

    @Test
    fun handlesEmptyVoteResults() {
        // Both empty-votes literals pinned (rendered-string parity), symmetric
        // with the win/lose templates below.
        assertEquals("投票結果がありません", summaries(SimulationState(), "ja")[0])
        assertEquals("No votes recorded", summaries(SimulationState(), "en")[0])
    }

    @Test
    fun majorityWinsInEnglish() {
        val state = SimulationState(
            voteResults = mapOf("Wolf" to 3, "Other" to 1),
            variables = mapOf("wolf_name" to "Wolf"),
        )
        val out = summaries(state, "en")
        assertEquals(1, out.size)
        // Rendered-string parity (en, wolf found).
        assertEquals("Most votes: Wolf (3) — Majority wins! The wolf was found.", out[0])
        assertFalse(out[0].contains("多数派の勝ち"))
    }

    @Test
    fun wolfWinsInEnglish() {
        val state = SimulationState(
            voteResults = mapOf("Innocent" to 3, "Wolf" to 1),
            variables = mapOf("wolf_name" to "Wolf"),
        )
        val out = summaries(state, "en")
        assertEquals(1, out.size)
        assertEquals("Most votes: Innocent (3) — The wolf wins! Escaped detection.", out[0])
        assertFalse(out[0].contains("ウルフの勝ち"))
    }
}
