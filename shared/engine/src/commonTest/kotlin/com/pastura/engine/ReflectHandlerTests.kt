package com.pastura.engine

import com.pastura.models.Persona
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Kotlin sibling of Swift's `ReflectHandlerTests` (+ its `…+TurnDegradation`
 * split), collapsed into one class per the commonTest convention.
 *
 * The distinctive reflect contract vs the speak handlers: the note is stored under
 * `notes_<name>` (non-empty guard) but is NEVER written to `conversationLog` or
 * `lastOutputs`. The ADR-021 turn-gate transient-skip is exercised here; the D3
 * systemic-error and D4 circuit-breaker cases ride the same shared gate already
 * covered by [SpeakAllHandlerTests] + [TurnFailureGateTests] — Swift's
 * `ReflectHandler` degradation coverage is likewise a single transient case.
 *
 * Ported for the ADR-023 KMP Engine migration (#501, #1242).
 */
class ReflectHandlerTests {

    private val handler = ReflectHandler()

    private fun scenario(
        agents: List<String> = listOf("Alice", "Bob"),
        language: String = "en",
        prompt: String? = "Reflect.",
    ) = Scenario(
        id = "t",
        name = "T",
        description = "d",
        language = language,
        agentCount = agents.size,
        rounds = 2,
        logWindow = null,
        context = "A test.",
        personas = agents.map { Persona(name = it, description = "$it's persona.") },
        phases = listOf(Phase(type = PhaseType.REFLECT, prompt = prompt, outputSchema = mapOf("note" to "string"))),
    )

    private fun context(
        scenario: Scenario,
        backend: LLMBackend,
        events: MutableList<SimulationEvent> = mutableListOf(),
    ) = PhaseContext(
        scenario = scenario,
        phase = scenario.phases[0],
        backend = backend,
        suspensionRelay = SuspensionRelay(),
        emitter = { events += it },
        pauseCheck = { },
        phasePath = listOf(0),
        turnGate = TurnFailureGate(),
    )

    private fun note(text: String) =
        ScriptedLLMBackend.Script.completing("""{"note": "$text"}""")

    // MARK: - Note persistence

    @Test
    fun storesNoteUnderNotesKeyForEachAgent() = runTest {
        val s = scenario()
        val backend = ScriptedLLMBackend(listOf(note("Alice suspects Bob"), note("Bob trusts no one")))
        val next = handler.execute(context(s, backend), SimulationState.initial(s).copy(currentRound = 1))

        assertEquals("Alice suspects Bob", next.variables["notes_Alice"])
        assertEquals("Bob trusts no one", next.variables["notes_Bob"])
    }

    @Test
    fun emitsAgentOutputWithReflectPhaseType() = runTest {
        val s = scenario()
        val events = mutableListOf<SimulationEvent>()
        val backend = ScriptedLLMBackend(listOf(note("a"), note("b")))
        handler.execute(context(s, backend, events), SimulationState.initial(s).copy(currentRound = 1))

        val reflectAgents = events.filterIsInstance<SimulationEvent.AgentOutput>()
            .filter { it.phaseType == PhaseType.REFLECT }
            .map { it.agent }
        assertEquals(listOf("Alice", "Bob"), reflectAgents)
    }

    // MARK: - Privacy: never touches conversationLog / lastOutputs

    @Test
    fun doesNotAppendToConversationLog() = runTest {
        val s = scenario(agents = listOf("Alice"))
        val backend = ScriptedLLMBackend(listOf(note("private memo")))
        val next = handler.execute(context(s, backend), SimulationState.initial(s).copy(currentRound = 1))
        assertTrue(next.conversationLog.isEmpty())
    }

    @Test
    fun doesNotUpdateLastOutputs() = runTest {
        val s = scenario(agents = listOf("Alice"))
        val backend = ScriptedLLMBackend(listOf(note("private memo")))
        val next = handler.execute(context(s, backend), SimulationState.initial(s).copy(currentRound = 1))
        assertNull(next.lastOutputs["Alice"])
    }

    // MARK: - Eliminated agents

    @Test
    fun skipsEliminatedAgents() = runTest {
        val s = scenario(agents = listOf("Alice", "Bob", "Charlie"))
        val backend = ScriptedLLMBackend(listOf(note("Alice note"), note("Charlie note")))
        val state = SimulationState.initial(s).copy(
            currentRound = 1,
            eliminated = mapOf("Bob" to true),
        )
        val next = handler.execute(context(s, backend), state)

        assertEquals(2, backend.callCount)
        assertNull(next.variables["notes_Bob"])
        assertEquals("Alice note", next.variables["notes_Alice"])
        assertEquals("Charlie note", next.variables["notes_Charlie"])
    }

    // MARK: - Empty-inference exhaustion must not erase a prior memo

    @Test
    fun emptyNoteDoesNotErasePreExistingNote() = runTest {
        // An all-empty inference never reaches the note write on the success path:
        // the parser rejects a present-but-empty expected key (`{"note":""}` —
        // `hasAllExpectedKeys` requires non-empty content), so three empties
        // exhaust the retry budget → RetriesExhausted → the turn gate absorbs it as
        // a skip (ADR-021 D2), and the prior memo survives via that skip. (Three
        // empties = MAX_RETRIES (2) + the initial attempt.) Asserted through the
        // skip mechanism, not the handler's defensive non-empty guard — which this
        // path can't reach, so a guard-only assertion would be coverage theater.
        val s = scenario(agents = listOf("Alice"))
        val backend = ScriptedLLMBackend(listOf(note(""), note(""), note("")))
        val events = mutableListOf<SimulationEvent>()
        val state = SimulationState.initial(s).copy(
            currentRound = 1,
            variables = mapOf("notes_Alice" to "prior round memo"),
        )
        val next = handler.execute(context(s, backend, events), state)

        assertEquals("prior round memo", next.variables["notes_Alice"])
        // Mechanism: absorbed as a turn skip (no AgentOutput), not a guard-dropped
        // write. Perturbing the handler's `?: return state` skip arm turns this red.
        assertTrue(events.filterIsInstance<SimulationEvent.AgentOutput>().isEmpty())
        val skipped = events.filterIsInstance<SimulationEvent.TurnSkipped>()
        assertEquals(1, skipped.size)
        assertEquals("Alice", skipped.single().agent)
        assertEquals(PhaseType.REFLECT, skipped.single().phaseType)
    }

    // MARK: - Turn degradation (ADR-021 D1/D2)

    @Test
    fun transientFailureSkipsAndPreservesPriorNote() = runTest {
        // Alice's call fails transiently (turn-degradable); her prior-round memo
        // must survive (no overwrite, no clear — reflect never writes lastOutputs),
        // and Bob still updates his note.
        val s = scenario(agents = listOf("Alice", "Bob"))
        val backend = ScriptedLLMBackend(
            listOf(
                ScriptedLLMBackend.Script(terminal = TerminalStatus.Failed(errorCode = "transient blip")),
                note("Bob's fresh memo"),
            ),
        )
        val events = mutableListOf<SimulationEvent>()
        val state = SimulationState.initial(s).copy(
            currentRound = 2,
            variables = mapOf("notes_Alice" to "Alice's prior memo"),
        )
        val next = handler.execute(context(s, backend, events), state)

        // Prior memo preserved on skip; Bob's fresh note written.
        assertEquals("Alice's prior memo", next.variables["notes_Alice"])
        assertEquals("Bob's fresh memo", next.variables["notes_Bob"])

        // No AgentOutput for the skipped agent; exactly one TurnSkipped.
        val outputs = events.filterIsInstance<SimulationEvent.AgentOutput>().map { it.agent }
        assertEquals(listOf("Bob"), outputs, "the failing agent emits no AgentOutput")

        val skipped = events.filterIsInstance<SimulationEvent.TurnSkipped>()
        assertEquals(1, skipped.size)
        assertEquals("Alice", skipped.single().agent)
        assertEquals(PhaseType.REFLECT, skipped.single().phaseType)
    }
}
