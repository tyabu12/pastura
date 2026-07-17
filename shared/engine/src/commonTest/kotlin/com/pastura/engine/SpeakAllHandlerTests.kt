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
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Kotlin sibling of Swift's `SpeakAllHandlerTests`, scoped to the ported subset.
 *
 * ADR-021 turn-gate cases are absent because the gate itself is a named deferral
 * (see [SpeakAllHandler]'s doc) — not because they were forgotten.
 *
 * Ported for the ADR-023 §6 Stage-2 gate slice (#501).
 */
class SpeakAllHandlerTests {

    private val handler = SpeakAllHandler()

    private fun scenario(
        agents: List<String> = listOf("Alice", "Bob"),
        language: String = "en",
        logWindow: Int? = null,
        prompt: String? = "Speak.",
    ) = Scenario(
        id = "t",
        name = "T",
        description = "d",
        language = language,
        agentCount = agents.size,
        rounds = 2,
        logWindow = logWindow,
        context = "A test.",
        personas = agents.map { Persona(name = it, description = "$it's persona.") },
        phases = listOf(Phase(type = PhaseType.SPEAK_ALL, prompt = prompt, outputSchema = mapOf("statement" to "string"))),
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
        pauseCheck = { false },
        phasePath = listOf(0),
    )

    private fun says(text: String) =
        ScriptedLLMBackend.Script.completing("""{"statement": "$text"}""")

    // MARK: - Core loop

    @Test
    fun everyActiveAgentSpeaksOnce() = runTest {
        val s = scenario()
        val backend = ScriptedLLMBackend(listOf(says("from Alice"), says("from Bob")))
        val next = handler.execute(context(s, backend), SimulationState.initial(s))

        assertEquals(2, backend.callCount)
        assertEquals(listOf("Alice", "Bob"), next.conversationLog.map { it.agentName })
        assertEquals(listOf("from Alice", "from Bob"), next.conversationLog.map { it.content })
    }

    @Test
    fun agentsSpeakInPersonaOrder() = runTest {
        val s = scenario(agents = listOf("Carol", "Alice", "Bob"))
        val backend = ScriptedLLMBackend(listOf(says("1"), says("2"), says("3")))
        handler.execute(context(s, backend), SimulationState.initial(s))
        // Persona order, NOT sorted — the scoreboard sorts, the speaking order does not.
        assertEquals(listOf("Carol", "Alice", "Bob"), backend.requests.map { r ->
            listOf("Carol", "Alice", "Bob").first { r.system.contains("Name: $it") }
        })
    }

    @Test
    fun eliminatedAgentsAreSkipped() = runTest {
        val s = scenario(agents = listOf("Alice", "Bob", "Carol"))
        val backend = ScriptedLLMBackend(listOf(says("a"), says("c")))
        val state = SimulationState.initial(s).copy(
            eliminated = mapOf("Alice" to false, "Bob" to true, "Carol" to false),
        )
        val next = handler.execute(context(s, backend), state)

        assertEquals(2, backend.callCount)
        assertEquals(listOf("Alice", "Carol"), next.conversationLog.map { it.agentName })
    }

    @Test
    fun anAgentAbsentFromTheEliminatedMapIsActive() = runTest {
        // Swift guards on `!= true`, so a missing key means active. `== false`
        // would silently skip an agent the map never mentioned.
        val s = scenario(agents = listOf("Alice"))
        val backend = ScriptedLLMBackend(listOf(says("hi")))
        val next = handler.execute(context(s, backend), SimulationState.initial(s).copy(eliminated = emptyMap()))
        assertEquals(1, backend.callCount)
        assertEquals(1, next.conversationLog.size)
    }

    // MARK: - State folding (immutable — the inout swap)

    @Test
    fun outputsLandInLastOutputsAndTheInputIsUntouched() = runTest {
        val s = scenario()
        val backend = ScriptedLLMBackend(listOf(says("a"), says("b")))
        val before = SimulationState.initial(s)
        val next = handler.execute(context(s, backend), before)

        assertEquals("a", next.lastOutputs["Alice"]?.fields?.get("statement"))
        assertEquals("b", next.lastOutputs["Bob"]?.fields?.get("statement"))
        assertTrue(before.lastOutputs.isEmpty(), "the handler must not mutate its input")
        assertTrue(before.conversationLog.isEmpty())
    }

    @Test
    fun conversationEntriesCarryTheCurrentRoundAndPhaseType() = runTest {
        val s = scenario()
        val backend = ScriptedLLMBackend(listOf(says("a"), says("b")))
        val next = handler.execute(context(s, backend), SimulationState.initial(s).copy(currentRound = 3))
        assertTrue(next.conversationLog.all { it.round == 3 })
        assertTrue(next.conversationLog.all { it.phaseType == PhaseType.SPEAK_ALL })
    }

    @Test
    fun laterAgentsSeeEarlierAgentsInTheSameRoundsLog() = runTest {
        // speak_all agents share a round and the log accumulates WITHIN it, so
        // Bob's prompt must already carry Alice's line. A handler that folded state
        // only after the loop would still pass every other test here and silently
        // break this one — which is why it is asserted separately.
        //
        // The log reaches a prompt only through the `{conversation_log}` variable:
        // there is no implicit injection, and the default "Speak." prompt has no
        // placeholder. That is a scenario-authoring contract, not a handler one.
        val s = scenario(prompt = "Log: {conversation_log}")
        val backend = ScriptedLLMBackend(listOf(says("Alice speaks"), says("Bob speaks")))
        handler.execute(context(s, backend), SimulationState.initial(s))

        assertTrue(backend.requests[0].user.contains("(none yet)"), "Alice speaks into an empty log")
        assertTrue(backend.requests[1].user.contains("Alice: Alice speaks"), "Bob must see Alice's line")
    }

    @Test
    fun aPromptWithoutThePlaceholderNeverReceivesTheLog() {
        // The flip side, pinned so the contract above is not mistaken for implicit
        // injection: an author who omits {conversation_log} gets no log at all.
        runTest {
            val s = scenario(prompt = "Speak.")
            val backend = ScriptedLLMBackend(listOf(says("a"), says("b")))
            handler.execute(context(s, backend), SimulationState.initial(s))
            assertEquals("Speak.", backend.requests[1].user)
        }
    }

    // MARK: - Prompt wiring

    @Test
    fun promptTemplateVariablesAreExpanded() = runTest {
        val s = scenario(prompt = "Log so far: {conversation_log} / Scores: {scoreboard}")
        val backend = ScriptedLLMBackend(listOf(says("a"), says("b")))
        handler.execute(context(s, backend), SimulationState.initial(s))

        val first = backend.requests[0].user
        assertTrue(first.contains("(none yet)"), "empty log placeholder must be expanded")
        assertTrue(first.contains("""{"Alice": 0, "Bob": 0}"""), "scoreboard must be expanded and sorted")
        assertFalse(first.contains("{conversation_log}"))
    }

    @Test
    fun defaultPromptIsUsedWhenThePhaseDeclaresNone() = runTest {
        val s = scenario(prompt = null)
        val backend = ScriptedLLMBackend(listOf(says("a"), says("b")))
        handler.execute(context(s, backend), SimulationState.initial(s))
        assertEquals("Share your opinion.", backend.requests[0].user)
    }

    @Test
    fun defaultPromptDispatchesOnEngineLanguage() = runTest {
        val s = scenario(language = "ja", prompt = null)
        val backend = ScriptedLLMBackend(listOf(says("a"), says("b")))
        handler.execute(context(s, backend), SimulationState.initial(s))
        assertEquals("あなたの意見を述べてください。", backend.requests[0].user)
    }

    @Test
    fun logWindowReachesTheConversationLogFormatter() = runTest {
        // The slice-path reason Scenario.logWindow had to be synced at all.
        val s = scenario(agents = listOf("A", "B", "C"), logWindow = 1, prompt = "Log: {conversation_log}")
        val backend = ScriptedLLMBackend(listOf(says("1"), says("2"), says("3")))
        handler.execute(context(s, backend), SimulationState.initial(s))

        // C's prompt sees only B's line (window = 1), not A's.
        val third = backend.requests[2].user
        assertTrue(third.contains("B: 2"))
        assertFalse(third.contains("A: 1"), "window=1 must trim the older entry")
    }

    @Test
    fun personaSecretReachesOnlyItsOwnAgentsSystemPrompt() = runTest {
        // The #914 secrecy invariant, at the handler level.
        val s = Scenario(
            id = "t", name = "T", description = "d", language = "en",
            agentCount = 2, rounds = 1, context = "A test.",
            personas = listOf(
                Persona(name = "Alice", description = "Bold.", secret = "I am the wolf."),
                Persona(name = "Bob", description = "Cautious."),
            ),
            phases = listOf(Phase(type = PhaseType.SPEAK_ALL, prompt = "Speak.", outputSchema = mapOf("statement" to "string"))),
        )
        val backend = ScriptedLLMBackend(listOf(says("a"), says("b")))
        val next = handler.execute(context(s, backend), SimulationState.initial(s))

        assertTrue(backend.requests[0].system.contains("I am the wolf."), "the owner must see it")
        assertFalse(backend.requests[1].system.contains("I am the wolf."), "no other agent may see it")
        // And it must not leak into shared state.
        assertFalse(next.conversationLog.any { it.content.contains("wolf") })
    }

    // MARK: - Events

    @Test
    fun emitsAgentOutputPerAgent() = runTest {
        val s = scenario()
        val events = mutableListOf<SimulationEvent>()
        val backend = ScriptedLLMBackend(listOf(says("a"), says("b")))
        handler.execute(context(s, backend, events), SimulationState.initial(s))

        val outputs = events.filterIsInstance<SimulationEvent.AgentOutput>()
        assertEquals(listOf("Alice", "Bob"), outputs.map { it.agent })
        assertTrue(outputs.all { it.phaseType == PhaseType.SPEAK_ALL })
        assertEquals("a", outputs[0].output.fields["statement"])
    }

    // MARK: - Failure propagates (ADR-021 turn gate is a named deferral)

    @Test
    fun anLlmFailureAbortsTheRunRatherThanSkippingTheTurn() = runTest {
        // Pins the DEFERRAL, so its restoration in Stage 3 is a deliberate,
        // test-visible change rather than a silent behaviour shift. Swift routes
        // this through TurnFailureGate and skips only the failing agent's turn.
        val s = scenario()
        val backend = ScriptedLLMBackend(
            listOf(ScriptedLLMBackend.Script(terminal = TerminalStatus.Failed(errorCode = "boom"))),
        )
        assertFailsWith<SimulationException> {
            handler.execute(context(s, backend), SimulationState.initial(s))
        }
        assertEquals(1, backend.callCount, "Bob never speaks — Swift would have let him")
    }

    @Test
    fun aMissingMainFieldFoldsAsEmptyContentRatherThanThrowing() = runTest {
        val s = scenario()
        val backend = ScriptedLLMBackend(
            listOf(ScriptedLLMBackend.Script.completing("""{"other": "x"}"""), says("b")),
        )
        // Schema-less phase so the parser guard does not reject first.
        val phaseless = s.copy(phases = listOf(Phase(type = PhaseType.SPEAK_ALL, prompt = "Speak.")))
        val next = handler.execute(context(phaseless, backend), SimulationState.initial(phaseless))
        assertEquals("", next.conversationLog[0].content)
        assertNull(next.lastOutputs["Alice"]?.fields?.get("statement"))
    }
}
