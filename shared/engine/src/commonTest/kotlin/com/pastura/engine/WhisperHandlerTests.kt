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
 * Kotlin sibling of Swift's `WhisperHandlerTests` (+ its `…+TurnDegradation` split),
 * collapsed into one class per the commonTest convention.
 *
 * Whisper pairs off active agents (rotated by round; an odd agent sits out), runs
 * `subRounds` exchanges per pair, emits each utterance as an `AgentOutput` carrying a
 * reserved `whisper_to` field (never touching `conversationLog` / `lastOutputs`), and
 * writes each participant's view of the exchange to `whispers_<name>`. The four
 * hardest invariants are each perturbation-verified: pairing rotation, sat-out clear,
 * ADR-021 skip early-break, and empty-transcript non-overwrite.
 *
 * Ported for the ADR-023 KMP Engine migration (#501, #1252).
 */
class WhisperHandlerTests {

    private val handler = WhisperHandler()

    private fun scenario(
        agents: List<String>,
        language: String = "en",
        prompt: String? = "Whisper!",
        subRounds: Int? = null,
    ) = Scenario(
        id = "t",
        name = "T",
        description = "d",
        language = language,
        simulationLanguage = null,
        agentCount = agents.size,
        rounds = 2,
        logWindow = null,
        context = "A test.",
        personas = agents.map { Persona(name = it, description = "$it's persona.") },
        phases = listOf(
            Phase(
                type = PhaseType.WHISPER,
                prompt = prompt,
                outputSchema = mapOf("statement" to "string", "inner_thought" to "string"),
                subRounds = subRounds,
            ),
        ),
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

    private fun stmt(text: String) =
        ScriptedLLMBackend.Script.completing("""{"statement": "$text", "inner_thought": "t"}""")

    /** An empty-statement response: the parser rejects it (non-empty expected key), so
     *  three in a row exhaust the retry budget → the turn gate absorbs it as a skip. */
    private fun emptyStmt() =
        ScriptedLLMBackend.Script.completing("""{"statement": "", "inner_thought": "t"}""")

    private fun failed() =
        ScriptedLLMBackend.Script(terminal = TerminalStatus.Failed(errorCode = "transient blip"))

    private fun initial(s: Scenario, round: Int = 1) =
        SimulationState.initial(s).copy(currentRound = round)

    private data class WhisperOut(val agent: String, val whisperTo: String?, val statement: String?)

    /** Extracts `(agent, whisper_to, statement)` for each whisper `AgentOutput`, in order. */
    private fun whisperOutputs(events: List<SimulationEvent>): List<WhisperOut> =
        events.filterIsInstance<SimulationEvent.AgentOutput>()
            .filter { it.phaseType == PhaseType.WHISPER }
            .map { WhisperOut(it.agent, it.output.fields["whisper_to"], it.output.statement) }

    // MARK: - Pairing & attribution

    @Test
    fun fourAgentsRoundOnePairsAdjacentWithAttribution() = runTest {
        val s = scenario(listOf("Alice", "Bob", "Carol", "Dave"))
        val backend = ScriptedLLMBackend(listOf(stmt("A to B"), stmt("B to A"), stmt("C to D"), stmt("D to C")))
        val events = mutableListOf<SimulationEvent>()
        handler.execute(context(s, backend, events), initial(s))

        val outputs = whisperOutputs(events)
        assertEquals(listOf("Alice", "Bob", "Carol", "Dave"), outputs.map { it.agent })
        assertEquals(listOf("Bob", "Alice", "Dave", "Carol"), outputs.map { it.whisperTo })
    }

    @Test
    fun roundTwoRotationShiftsPairs() = runTest {
        // PERTURBATION (pairing rotation): offset = (2-1) % 4 = 1 → rotated
        // [Bob, Carol, Dave, Alice] → pairs (Bob,Carol),(Dave,Alice). Reverting
        // `rotate` to `by 0` (declaration order) turns the two lists below red.
        val s = scenario(listOf("Alice", "Bob", "Carol", "Dave"))
        val backend = ScriptedLLMBackend(listOf(stmt("1"), stmt("2"), stmt("3"), stmt("4")))
        val events = mutableListOf<SimulationEvent>()
        handler.execute(context(s, backend, events), initial(s, round = 2))

        val outputs = whisperOutputs(events)
        assertEquals(listOf("Bob", "Carol", "Dave", "Alice"), outputs.map { it.agent })
        assertEquals(listOf("Carol", "Bob", "Alice", "Dave"), outputs.map { it.whisperTo })
    }

    @Test
    fun eliminatedAgentsNeverPaired() = runTest {
        // Bob eliminated → active [Alice, Carol, Dave] → pair (Alice, Carol); Dave sits
        // out; Bob is not a participant. Neither Bob nor Dave gets a channel.
        val s = scenario(listOf("Alice", "Bob", "Carol", "Dave"))
        val backend = ScriptedLLMBackend(listOf(stmt("A to C"), stmt("C to A")))
        val events = mutableListOf<SimulationEvent>()
        val state = initial(s).copy(eliminated = mapOf("Bob" to true))
        val next = handler.execute(context(s, backend, events), state)

        val outputs = whisperOutputs(events)
        assertEquals(listOf("Alice", "Carol"), outputs.map { it.agent })
        assertEquals(listOf("Carol", "Alice"), outputs.map { it.whisperTo })
        assertNull(next.variables["whispers_Bob"])
        assertNull(next.variables["whispers_Dave"])
    }

    // MARK: - Privacy (never conversationLog / lastOutputs)

    @Test
    fun doesNotTouchConversationLogOrLastOutputs() = runTest {
        val s = scenario(listOf("Alice", "Bob"))
        val backend = ScriptedLLMBackend(listOf(stmt("A to B"), stmt("B to A")))
        val next = handler.execute(context(s, backend), initial(s))

        assertTrue(next.conversationLog.isEmpty())
        assertTrue(next.lastOutputs.isEmpty())
    }

    // MARK: - Per-participant channels

    @Test
    fun writesPerParticipantChannelWithoutCrossPairLeak() = runTest {
        val s = scenario(listOf("Alice", "Bob", "Carol", "Dave"))
        val backend = ScriptedLLMBackend(listOf(stmt("A to B"), stmt("B to A"), stmt("C to D"), stmt("D to C")))
        val next = handler.execute(context(s, backend), initial(s))

        for (name in listOf("Alice", "Bob", "Carol", "Dave")) {
            assertTrue(next.variables["whispers_$name"] != null, "$name has a channel")
        }
        val aliceChannel = next.variables["whispers_Alice"]!!
        assertTrue(aliceChannel.contains("A to B"))
        assertTrue(aliceChannel.contains("B to A"))
        // No leak of the other pair's content.
        assertTrue(!aliceChannel.contains("C to D"))
        assertTrue(!aliceChannel.contains("D to C"))
        assertTrue(aliceChannel.contains("Bob")) // partner-identifying line
    }

    @Test
    fun oddAgentSitsOutAndStaleChannelCleared() = runTest {
        // PERTURBATION (sat-out clear): five agents → rotated [Alice..Eve]; Eve (last)
        // sits out. Her stale channel must be cleared. Removing the sat-out
        // `removeValue` fold leaves "stale" behind → this assertion goes red.
        val s = scenario(listOf("Alice", "Bob", "Carol", "Dave", "Eve"))
        val backend = ScriptedLLMBackend(listOf(stmt("A to B"), stmt("B to A"), stmt("C to D"), stmt("D to C")))
        val events = mutableListOf<SimulationEvent>()
        val state = initial(s).copy(variables = mapOf("whispers_Eve" to "stale from a prior round"))
        val next = handler.execute(context(s, backend, events), state)

        assertEquals(4, backend.callCount)
        assertNull(next.variables["whispers_Eve"])
        assertEquals(setOf("Alice", "Bob", "Carol", "Dave"), whisperOutputs(events).map { it.agent }.toSet())
    }

    @Test
    fun singleActiveAgentIsNoOp() = runTest {
        // Only Alice active (Bob/Carol/Dave eliminated) → nothing to pair. No LLM call,
        // no AgentOutput, and — crucially — NO channel is cleared (Alice keeps hers).
        val s = scenario(listOf("Alice", "Bob", "Carol", "Dave"))
        val backend = ScriptedLLMBackend(emptyList())
        val events = mutableListOf<SimulationEvent>()
        val state = initial(s).copy(
            eliminated = mapOf("Bob" to true, "Carol" to true, "Dave" to true),
            variables = mapOf("whispers_Alice" to "untouched"),
        )
        val next = handler.execute(context(s, backend, events), state)

        assertEquals(0, backend.callCount)
        assertTrue(whisperOutputs(events).isEmpty())
        assertEquals("untouched", next.variables["whispers_Alice"])
    }

    // MARK: - sub_rounds exchange accumulation

    @Test
    fun subRoundsAccumulatesExchangeTranscript() = runTest {
        // Two exchanges per pair; the second speaker's prompt must carry the first
        // exchange's running transcript (threaded via {whisper_exchange}).
        val s = scenario(listOf("Alice", "Bob", "Carol", "Dave"), prompt = "Whisper. So far: {whisper_exchange}", subRounds = 2)
        val backend = ScriptedLLMBackend(
            listOf(
                stmt("A1"), stmt("B1"), stmt("A2"), stmt("B2"), // pair (Alice, Bob)
                stmt("C1"), stmt("D1"), stmt("C2"), stmt("D2"), // pair (Carol, Dave)
            ),
        )
        val next = handler.execute(context(s, backend), initial(s))

        assertEquals(8, backend.callCount)
        val aliceChannel = next.variables["whispers_Alice"]!!
        for (token in listOf("A1", "B1", "A2", "B2")) {
            assertTrue(aliceChannel.contains(token), "channel carries $token")
        }
        // Alice's 2nd utterance (request index 2) saw the first exchange's transcript.
        val secondSpeakerPrompt = backend.requests[2].user
        assertTrue(secondSpeakerPrompt.contains("A1"))
        assertTrue(secondSpeakerPrompt.contains("B1"))
    }

    // MARK: - Prompt hardening (#908): default template still names partner + exchange

    @Test
    fun defaultTemplateAlwaysNamesPartnerAndExchange() = runTest {
        // prompt = null → the handler's built-in default (no placeholders). The
        // appended context block still delivers the partner and running exchange.
        val s = scenario(listOf("Alice", "Bob"), prompt = null)
        val backend = ScriptedLLMBackend(listOf(stmt("A to B"), stmt("B to A")))
        handler.execute(context(s, backend), initial(s))

        // Alice speaks first — her prompt names Bob even without a template token.
        assertTrue(backend.requests[0].user.contains("Bob"))
        // Bob speaks second — his prompt names Alice AND carries the exchange so far.
        val bobPrompt = backend.requests[1].user
        assertTrue(bobPrompt.contains("Alice"))
        assertTrue(bobPrompt.contains("A to B"))
    }

    // MARK: - ADR-021 skip (early-break + empty-transcript preservation)

    @Test
    fun firstTurnSkipPreservesPriorChannel() = runTest {
        // PERTURBATION (empty-transcript non-overwrite): Alice's opening utterance is
        // empty three times → parser rejects → RetriesExhausted → the gate absorbs it
        // as a skip → the pair breaks with an EMPTY transcript. The `isNotEmpty()`
        // guard must then leave the prior round's channel intact. Removing that guard
        // writes a header-only "Whispering with Bob" over PRIOR_SENTINEL → red.
        // Asserted through the SKIP mechanism (TurnSkipped, no AgentOutput), not the
        // handler's guard alone.
        val s = scenario(listOf("Alice", "Bob"))
        val backend = ScriptedLLMBackend(listOf(emptyStmt(), emptyStmt(), emptyStmt()))
        val events = mutableListOf<SimulationEvent>()
        val state = initial(s).copy(variables = mapOf("whispers_Alice" to "PRIOR_SENTINEL"))
        val next = handler.execute(context(s, backend, events), state)

        // Prior channel untouched (empty transcript never overwrites).
        assertEquals("PRIOR_SENTINEL", next.variables["whispers_Alice"])
        // Mechanism: absorbed as a turn skip (no AgentOutput), not a silent guard drop.
        assertTrue(events.filterIsInstance<SimulationEvent.AgentOutput>().isEmpty())
        val skipped = events.filterIsInstance<SimulationEvent.TurnSkipped>()
        assertEquals(1, skipped.size)
        assertEquals("Alice", skipped.single().agent)
        assertEquals(PhaseType.WHISPER, skipped.single().phaseType)
    }

    @Test
    fun skipEndsPairExchangeEarly() = runTest {
        // PERTURBATION (skip early-break): sub_rounds = 3. The first exchange
        // completes (A1, B1); the second exchange's Alice turn fails transiently →
        // skip → `break` stops the pair, so the THIRD exchange never starts. Only
        // three calls run. Replacing the `?: break` with a `continue` would advance to
        // the third exchange (Alice again), attempt a fourth call, and exhaust the
        // scripted backend — a different failure. The completed exchange still
        // overwrites the channel. (sub_rounds must exceed 2 so the skip lands on a
        // non-final exchange; at 2 the skip is on the last one and break vs continue
        // are indistinguishable.)
        val s = scenario(listOf("Alice", "Bob"), subRounds = 3)
        val backend = ScriptedLLMBackend(listOf(stmt("A1"), stmt("B1"), failed()))
        val events = mutableListOf<SimulationEvent>()
        val next = handler.execute(context(s, backend, events), initial(s))

        assertEquals(3, backend.callCount) // Bob's exchange-2 turn was never attempted
        val outputs = whisperOutputs(events)
        assertEquals(listOf("Alice", "Bob"), outputs.map { it.agent }) // exchange 1 only
        val skipped = events.filterIsInstance<SimulationEvent.TurnSkipped>()
        assertEquals(1, skipped.size)
        assertEquals("Alice", skipped.single().agent)
        // The completed exchange still overwrites the channel.
        val aliceChannel = next.variables["whispers_Alice"]!!
        assertTrue(aliceChannel.contains("A1"))
        assertTrue(aliceChannel.contains("B1"))
    }
}
