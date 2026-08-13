package com.pastura.engine

import com.pastura.models.Pairing
import com.pastura.models.Persona
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState
import com.pastura.models.TurnOutput
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Kotlin port of `Pastura/PasturaTests/Engine/Phases/RelationshipUpdateHandlerTests.swift`
 * — the zero-inference affinity-matrix code phase (#910). Signals are seeded directly
 * onto [SimulationState] (`lastOutputs` for votes, `pairings` for choose actions) the
 * way the surrounding phases would, then the handler's deterministic deltas are asserted
 * via the emitted [SimulationEvent.RelationshipUpdate] matrix and the persisted
 * `variables`.
 *
 * Because Kotlin [SimulationState] is immutable, the two multi-round cases thread
 * round-1's **returned** state into round 2 and read every `variables[...]` assertion off
 * the returned state — a naive port that reused the input `state` would silently drop
 * cross-round accumulation while still compiling (the AssignHandler silent-drop trap).
 *
 * Beyond the 9 Swift cases, [placementDiagnosticFiresWhenNoSignal] /
 * [placementDiagnosticSilentWhenSignalPresent] are a negative control on the no-signal
 * `.debug` diagnostic — the Swift suite only asserts the empty matrix, never that the
 * guard actually fires (see `knowledge-layering.md` § "Claims you author are assertions too").
 *
 * Ported for the ADR-023 Stage-3 code-phase port (#501).
 */
class RelationshipUpdateHandlerTests {

    private val handler = RelationshipUpdateHandler()

    private fun scenario(
        agentNames: List<String> = listOf("Alice", "Bob"),
        voteAgainst: Int? = null,
        actionDeltas: Map<String, Int>? = null,
    ) = Scenario(
        id = "t",
        name = "T",
        description = "d",
        language = "en",
        agentCount = agentNames.size,
        rounds = 1,
        context = "A test.",
        personas = agentNames.map { Persona(name = it, description = "$it's persona.") },
        phases = listOf(
            Phase(type = PhaseType.RELATIONSHIP_UPDATE, voteAgainst = voteAgainst, actionDeltas = actionDeltas),
        ),
    )

    private fun context(
        scenario: Scenario,
        events: MutableList<SimulationEvent> = mutableListOf(),
        logger: EngineLogger = NoopEngineLogger(),
    ) = PhaseContext(
        scenario = scenario,
        phase = scenario.phases[0],
        backend = ScriptedLLMBackend(emptyList()),
        suspensionRelay = SuspensionRelay(),
        emitter = { events += it },
        pauseCheck = { },
        phasePath = listOf(0),
        turnGate = TurnFailureGate(),
        logger = logger,
    )

    private fun emittedMatrix(events: List<SimulationEvent>): Map<String, Map<String, Int>>? =
        events.filterIsInstance<SimulationEvent.RelationshipUpdate>().firstOrNull()?.relationships

    @Test
    fun appliesVoteAgainstDelta() = runTest {
        val s = scenario(voteAgainst = -1)
        // Alice voted Bob, Bob voted Alice.
        val state = SimulationState.initial(s).copy(
            currentRound = 1,
            lastOutputs = mapOf(
                "Alice" to TurnOutput(fields = mapOf("vote" to "Bob")),
                "Bob" to TurnOutput(fields = mapOf("vote" to "Alice")),
            ),
        )
        val events = mutableListOf<SimulationEvent>()
        handler.execute(context(s, events), state)

        val matrix = assertNotNull(emittedMatrix(events))
        // Each target grows wary of the agent who voted against them.
        assertEquals(-1, matrix["Bob"]?.get("Alice"))
        assertEquals(-1, matrix["Alice"]?.get("Bob"))
    }

    @Test
    fun ignoresSelfVoteAndHallucinatedTarget() = runTest {
        val s = scenario(voteAgainst = -1)
        val state = SimulationState.initial(s).copy(
            currentRound = 1,
            lastOutputs = mapOf(
                "Alice" to TurnOutput(fields = mapOf("vote" to "Alice")), // self-vote
                "Bob" to TurnOutput(fields = mapOf("vote" to "Ghost")), // not a persona
            ),
        )
        val events = mutableListOf<SimulationEvent>()
        handler.execute(context(s, events), state)

        val matrix = assertNotNull(emittedMatrix(events))
        assertTrue(matrix.isEmpty())
    }

    @Test
    fun appliesActionDeltasPerPartner() = runTest {
        val s = scenario(actionDeltas = mapOf("cooperate" to 1, "betray" to -2))
        val state = SimulationState.initial(s).copy(
            currentRound = 1,
            pairings = listOf(
                Pairing(agent1 = "Alice", agent2 = "Bob", action1 = "cooperate", action2 = "betray"),
            ),
        )
        val events = mutableListOf<SimulationEvent>()
        handler.execute(context(s, events), state)

        val matrix = assertNotNull(emittedMatrix(events))
        // Alice sees Bob's action (betray -> -2); Bob sees Alice's (cooperate -> +1).
        assertEquals(-2, matrix["Alice"]?.get("Bob"))
        assertEquals(1, matrix["Bob"]?.get("Alice"))
    }

    @Test
    fun accumulatesAcrossRounds() = runTest {
        val s = scenario(voteAgainst = -1)
        val round1State = SimulationState.initial(s).copy(
            currentRound = 1,
            lastOutputs = mapOf("Alice" to TurnOutput(fields = mapOf("vote" to "Bob"))),
        )
        // Thread round-1's RETURNED state into round 2 — the raw matrix persists in
        // `variables`, so a fresh `initial` state would drop the accumulation.
        val afterRound1 = handler.execute(context(s), round1State)

        // Second round: same vote again.
        val round2State = afterRound1.copy(
            currentRound = 2,
            lastOutputs = mapOf("Alice" to TurnOutput(fields = mapOf("vote" to "Bob"))),
        )
        val events2 = mutableListOf<SimulationEvent>()
        handler.execute(context(s, events2), round2State)

        val matrix = assertNotNull(emittedMatrix(events2))
        assertEquals(-2, matrix["Bob"]?.get("Alice"))
    }

    @Test
    fun skipsEliminatedPerceiver() = runTest {
        val s = scenario(agentNames = listOf("Alice", "Bob", "Charlie"), voteAgainst = -1)
        val initial = SimulationState.initial(s)
        val state = initial.copy(
            currentRound = 1,
            eliminated = initial.eliminated + ("Bob" to true),
            lastOutputs = mapOf(
                "Alice" to TurnOutput(fields = mapOf("vote" to "Bob")), // target eliminated -> dropped
                "Charlie" to TurnOutput(fields = mapOf("vote" to "Alice")),
            ),
        )
        val events = mutableListOf<SimulationEvent>()
        handler.execute(context(s, events), state)

        val matrix = assertNotNull(emittedMatrix(events))
        assertNull(matrix["Bob"]) // eliminated — no row
        assertEquals(-1, matrix["Alice"]?.get("Charlie"))
    }

    @Test
    fun writesProseSummaryWhenThresholdCrossed() = runTest {
        val s = scenario(voteAgainst = -2) // one round reaches |2|
        val state = SimulationState.initial(s).copy(
            currentRound = 1,
            lastOutputs = mapOf("Alice" to TurnOutput(fields = mapOf("vote" to "Bob"))),
        )
        val result = handler.execute(context(s), state)

        val summary = assertNotNull(result.variables["relationships_Bob"])
        assertTrue(summary.contains("Alice"))
        assertTrue(summary.isNotEmpty())
        // Raw matrix persisted for cross-round accumulation.
        assertTrue(result.variables["relationships_raw_Bob"]?.contains("Alice") == true)
    }

    @Test
    fun noSignalEmitsEmptyMatrixWithoutCrashing() = runTest {
        val s = scenario(voteAgainst = -1)
        // No lastOutputs votes, no pairings — misordered/placeholder phase.
        val state = SimulationState.initial(s).copy(currentRound = 1)
        val events = mutableListOf<SimulationEvent>()
        handler.execute(context(s, events), state)

        val matrix = assertNotNull(emittedMatrix(events))
        assertTrue(matrix.isEmpty())
    }

    @Test
    fun appliesBothVoteAndActionSignalsInSamePhase() = runTest {
        // Regression: a short-circuiting `||` over the two side-effecting apply
        // helpers dropped the action signal whenever a vote was also present. A
        // phase may declare both rules and both signals may be live at once.
        val s = scenario(voteAgainst = -1, actionDeltas = mapOf("cooperate" to 1, "betray" to -2))
        val state = SimulationState.initial(s).copy(
            currentRound = 1,
            lastOutputs = mapOf(
                "Alice" to TurnOutput(fields = mapOf("vote" to "Bob")),
                "Bob" to TurnOutput(fields = mapOf("vote" to "Alice")),
            ),
            pairings = listOf(
                Pairing(agent1 = "Alice", agent2 = "Bob", action1 = "cooperate", action2 = "betray"),
            ),
        )
        val events = mutableListOf<SimulationEvent>()
        handler.execute(context(s, events), state)

        val matrix = assertNotNull(emittedMatrix(events))
        // Alice: vote (-1) + Bob's betray action (-2) = -3. A `||` short-circuit
        // would drop the action term and leave -1.
        assertEquals(-3, matrix["Alice"]?.get("Bob"))
        // Bob: vote (-1) + Alice's cooperate action (+1) = 0.
        assertEquals(0, matrix["Bob"]?.get("Alice"))
    }

    @Test
    fun prunesEliminatedAgentFromProseButKeepsRawHistory() = runTest {
        val s = scenario(voteAgainst = -2)
        // Round 1: Bob votes Alice, so Alice grows wary of Bob (|2| crosses threshold).
        val round1State = SimulationState.initial(s).copy(
            currentRound = 1,
            lastOutputs = mapOf("Bob" to TurnOutput(fields = mapOf("vote" to "Alice"))),
        )
        val afterRound1 = handler.execute(context(s), round1State)
        assertTrue(afterRound1.variables["relationships_Alice"]?.contains("Bob") == true)

        // Bob is eliminated; re-run with no fresh signal, threading the returned state.
        val round2State = afterRound1.copy(
            eliminated = afterRound1.eliminated + ("Bob" to true),
            lastOutputs = emptyMap(),
        )
        val result = handler.execute(context(s), round2State)

        // Prose no longer mentions the eliminated agent, but the raw matrix keeps
        // the accumulated history (for the event payload / Phase-3 viz).
        assertEquals("", result.variables["relationships_Alice"])
        assertTrue(result.variables["relationships_raw_Alice"]?.contains("Bob") == true)
    }

    // MARK: - Negative control on the no-signal placement diagnostic (beyond Swift's 9)

    /** Records every [EngineLogger.log] call for negative-control assertions. */
    private class CapturingEngineLogger : EngineLogger {
        data class Entry(val level: EngineLogLevel, val category: String, val message: String)

        val entries = mutableListOf<Entry>()
        override fun log(level: EngineLogLevel, category: String, message: String, privacy: EngineLogPrivacy) {
            entries += Entry(level, category, message)
        }
    }

    @Test
    fun placementDiagnosticFiresWhenNoSignal() = runTest {
        val s = scenario(voteAgainst = -1)
        // No lastOutputs, no pairings — the misordered/placeholder case the guard targets.
        val state = SimulationState.initial(s).copy(currentRound = 1)
        val logger = CapturingEngineLogger()
        handler.execute(context(s, logger = logger), state)

        val diagnostics = logger.entries.filter { it.category == "RelationshipUpdate" }
        assertEquals(1, diagnostics.size)
        assertEquals(EngineLogLevel.DEBUG, diagnostics.single().level)
    }

    @Test
    fun placementDiagnosticSilentWhenSignalPresent() = runTest {
        val s = scenario(voteAgainst = -1)
        // A live vote signal — the guard must NOT fire (negative control; without it
        // the "fires when no signal" assertion above passes even for an always-log bug).
        val state = SimulationState.initial(s).copy(
            currentRound = 1,
            lastOutputs = mapOf("Alice" to TurnOutput(fields = mapOf("vote" to "Bob"))),
        )
        val logger = CapturingEngineLogger()
        handler.execute(context(s, logger = logger), state)

        assertTrue(logger.entries.none { it.category == "RelationshipUpdate" })
    }
}
