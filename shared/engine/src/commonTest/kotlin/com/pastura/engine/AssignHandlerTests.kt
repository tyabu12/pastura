package com.pastura.engine

import com.pastura.models.AnyCodableValue
import com.pastura.models.AssignTarget
import com.pastura.models.Persona
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Kotlin port of `Pastura/PasturaTests/Engine/Phases/AssignHandlerTests.swift`.
 *
 * `assign` is a deterministic code phase with two modes:
 * - `target: all` writes per-agent `assigned_<name>` vars + `assigned_topic` and
 *   emits exactly ONE [SimulationEvent.SharedAssignment] for the round.
 * - `target: random_one` (word wolf) writes per-agent `assigned_<name>` vars +
 *   `wolf_name` and emits N per-agent [SimulationEvent.Assignment]s.
 *
 * Because Kotlin [SimulationState] is immutable, EVERY assertion reads the
 * **returned** state's `variables`, never the input — a helper that mutates a local
 * copy but returns the un-updated `state` compiles cleanly and silently drops every
 * assignment. That is the single load-bearing correctness catch for this handler.
 *
 * The random-mode tests assert **structural invariants** (`wolf_name` ∈ agent
 * names, wolf → minority / others → majority, exactly one wolf), not a seeded pick
 * — so no determinism scaffolding is needed, matching Swift.
 *
 * Ported for the ADR-023 Stage-3 code-phase port (#501).
 */
class AssignHandlerTests {

    private val handler = AssignHandler()

    private fun scenario(
        agents: List<String>,
        target: AssignTarget,
        source: String,
        extraData: Map<String, AnyCodableValue>,
    ) = Scenario(
        id = "t",
        name = "T",
        description = "d",
        language = "en",
        agentCount = agents.size,
        rounds = 2,
        context = "A test.",
        personas = agents.map { Persona(name = it, description = "$it's persona.") },
        phases = listOf(Phase(type = PhaseType.ASSIGN, source = source, target = target)),
        extraData = extraData,
    )

    private fun context(
        scenario: Scenario,
        events: MutableList<SimulationEvent> = mutableListOf(),
    ) = PhaseContext(
        scenario = scenario,
        phase = scenario.phases[0],
        backend = ScriptedLLMBackend(emptyList()),
        suspensionRelay = SuspensionRelay(),
        emitter = { events += it },
        pauseCheck = { },
        phasePath = listOf(0),
        turnGate = TurnFailureGate(),
    )

    @Test
    fun assignsToAllAgents() = runTest {
        val s = scenario(
            agents = listOf("Alice", "Bob"),
            target = AssignTarget.ALL,
            source = "topics",
            extraData = mapOf("topics" to AnyCodableValue.ArrayValue(listOf("Topic A", "Topic B"))),
        )
        val state = SimulationState.initial(s).copy(currentRound = 1)
        val result = handler.execute(context(s), state)

        assertEquals("Topic A", result.variables["assigned_topic"])
        assertEquals("Topic A", result.variables["assigned_Alice"])
        assertEquals("Topic A", result.variables["assigned_Bob"])
    }

    @Test
    fun assignsRoundIndexedItem() = runTest {
        val s = scenario(
            agents = listOf("Alice"),
            target = AssignTarget.ALL,
            source = "topics",
            extraData = mapOf("topics" to AnyCodableValue.ArrayValue(listOf("First", "Second", "Third"))),
        )
        val state = SimulationState.initial(s).copy(currentRound = 2) // Should get "Second" (index 1)
        val result = handler.execute(context(s), state)

        assertEquals("Second", result.variables["assigned_topic"])
    }

    @Test
    fun assignsRandomOneForWordwolf() = runTest {
        val s = scenario(
            agents = listOf("Alice", "Bob", "Charlie"),
            target = AssignTarget.RANDOM_ONE,
            source = "words",
            extraData = mapOf(
                "words" to AnyCodableValue.ArrayOfDictionariesValue(
                    listOf(mapOf("majority" to "りんご", "minority" to "みかん")),
                ),
            ),
        )
        val state = SimulationState.initial(s).copy(currentRound = 1)
        val result = handler.execute(context(s), state)

        // One agent should be the wolf.
        val wolfName = result.variables["wolf_name"]
        assertNotNull(wolfName)
        assertTrue(listOf("Alice", "Bob", "Charlie").contains(wolfName))

        // Wolf gets minority, others get majority.
        assertEquals("みかん", result.variables["assigned_$wolfName"])
        val nonWolves = listOf("Alice", "Bob", "Charlie").filter { it != wolfName }
        for (name in nonWolves) {
            assertEquals("りんご", result.variables["assigned_$name"])
        }
    }

    @Test
    fun emitsSingleSharedAssignmentForAll() = runTest {
        // assignAll (target: all) gives every agent the SAME お題, so it emits ONE
        // SharedAssignment for the round — never N per-agent Assignment events
        // (#939). This guards the Engine emit shape against a regression back to
        // per-agent events.
        val s = scenario(
            agents = listOf("Alice", "Bob"),
            target = AssignTarget.ALL,
            source = "topics",
            extraData = mapOf("topics" to AnyCodableValue.ArrayValue(listOf("Topic"))),
        )
        val events = mutableListOf<SimulationEvent>()
        val state = SimulationState.initial(s).copy(currentRound = 1)
        handler.execute(context(s, events), state)

        val sharedValues = events.filterIsInstance<SimulationEvent.SharedAssignment>().map { it.value }
        assertEquals(listOf("Topic"), sharedValues)

        // No per-agent Assignment events for the shared case.
        assertTrue(events.filterIsInstance<SimulationEvent.Assignment>().isEmpty())
    }

    @Test
    fun emitsPerAgentAssignmentsForWordwolf() = runTest {
        // Word wolf (target: random_one) gives each agent a DIFFERENT secret, so it
        // keeps emitting one Assignment per agent — the counterpart to the
        // single-shared shape above (#939).
        val s = scenario(
            agents = listOf("Alice", "Bob", "Charlie"),
            target = AssignTarget.RANDOM_ONE,
            source = "words",
            extraData = mapOf(
                "words" to AnyCodableValue.ArrayOfDictionariesValue(
                    listOf(mapOf("majority" to "りんご", "minority" to "みかん")),
                ),
            ),
        )
        val events = mutableListOf<SimulationEvent>()
        val state = SimulationState.initial(s).copy(currentRound = 1)
        handler.execute(context(s, events), state)

        val perAgent = events.filterIsInstance<SimulationEvent.Assignment>().map { it.agent }
        assertEquals(3, perAgent.size)
        assertEquals(setOf("Alice", "Bob", "Charlie"), perAgent.toSet())

        // No shared-assignment event for the per-agent word-wolf case.
        assertTrue(events.filterIsInstance<SimulationEvent.SharedAssignment>().isEmpty())
    }
}
