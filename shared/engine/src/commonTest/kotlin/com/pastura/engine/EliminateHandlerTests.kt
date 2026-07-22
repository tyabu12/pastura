package com.pastura.engine

import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Kotlin port of `Pastura/PasturaTests/Engine/Phases/EliminateHandlerTests.swift`.
 *
 * `eliminate` is a deterministic code phase: it removes the most-voted agent via
 * the shared canonical tie-break ([VoteTally.winner]: count desc, name desc). The
 * tie parity case pins the #1056 invariant — the agent `EliminateHandler` removes
 * on a tie must equal the one `ConditionEvaluator` resolves `vote_winner` to.
 *
 * Because Kotlin [SimulationState] is immutable, every assertion reads the
 * **returned** state's `eliminated`, never the input — a handler that builds a
 * `.copy` but returns the original would silently drop the change.
 *
 * Ported for the ADR-023 Stage-3 code-phase port (#501).
 */
class EliminateHandlerTests {

    private val handler = EliminateHandler()

    private fun scenario(agents: List<String> = listOf("Alice", "Bob")) =
        makeTestScenario(agentNames = agents)

    private fun context(
        scenario: com.pastura.models.Scenario,
        events: MutableList<SimulationEvent> = mutableListOf(),
    ) = PhaseContext(
        scenario = scenario,
        phase = Phase(type = PhaseType.ELIMINATE),
        backend = ScriptedLLMBackend(emptyList()),
        suspensionRelay = SuspensionRelay(),
        emitter = { events += it },
        pauseCheck = { },
        phasePath = listOf(0),
        turnGate = TurnFailureGate(),
    )

    @Test
    fun eliminatesMostVotedAgent() = runTest {
        val s = scenario()
        val state = SimulationState.initial(s).copy(voteResults = mapOf("Alice" to 2, "Bob" to 1))
        val next = handler.execute(context(s), state)

        assertEquals(true, next.eliminated["Alice"])
        assertTrue(next.eliminated["Bob"] != true)
    }

    @Test
    fun emitsEliminationEvent() = runTest {
        val s = scenario()
        val events = mutableListOf<SimulationEvent>()
        val state = SimulationState.initial(s).copy(voteResults = mapOf("Bob" to 3))
        handler.execute(context(s, events), state)

        val eliminations = events.filterIsInstance<SimulationEvent.Elimination>()
        assertEquals(1, eliminations.size)
        assertEquals("Bob", eliminations[0].agent)
        assertEquals(3, eliminations[0].voteCount)
    }

    @Test
    fun handlesEmptyVoteResults() = runTest {
        val s = scenario()
        val events = mutableListOf<SimulationEvent>()
        val state = SimulationState.initial(s)
        val next = handler.execute(context(s, events), state)

        // No one eliminated, no events.
        assertTrue(next.eliminated.values.all { it == false })
        assertTrue(events.isEmpty())
    }

    @Test
    fun handlesTiedVotes() = runTest {
        val s = scenario()
        val state = SimulationState.initial(s).copy(voteResults = mapOf("Alice" to 2, "Bob" to 2))
        val next = handler.execute(context(s), state)

        // Canonical tie-break: (count desc, name desc) — Bob sorts before Alice,
        // matching ConditionEvaluator's `vote_winner` derivation (#1056).
        assertEquals(true, next.eliminated["Bob"])
        assertTrue(next.eliminated["Alice"] != true)
        assertEquals(1, next.eliminated.values.count { it })
    }

    @Test
    fun tieWinnerMatchesVoteWinner() = runTest {
        // The agent EliminateHandler removes on a tie must be the SAME agent
        // ConditionEvaluator resolves `vote_winner` to — otherwise an `eliminate`
        // phase and a `conditional` reading `vote_winner` in the same round
        // silently disagree about who won (#1056).
        val s = scenario()
        val state = SimulationState.initial(s).copy(voteResults = mapOf("Alice" to 2, "Bob" to 2))
        val next = handler.execute(context(s), state)

        // EliminateHandler eliminates Bob (canonical tie-break).
        assertEquals(true, next.eliminated["Bob"])

        // ConditionEvaluator resolves `vote_winner` to the same agent (Bob).
        val evaluator = ConditionEvaluator()
        assertTrue(evaluator.evaluate("vote_winner == \"Bob\"", state, s).value)
        assertTrue(!evaluator.evaluate("vote_winner == \"Alice\"", state, s).value)
    }
}
