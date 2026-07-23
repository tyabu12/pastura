package com.pastura.engine

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
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Kotlin sibling of Swift's `VoteHandlerTests` (+ its `…+TurnDegradation` split),
 * collapsed into one class per the commonTest convention.
 *
 * Vote is a hybrid: it WRITES `lastOutputs` (and clears a stale entry on skip, like
 * [SpeakAllHandler]) but never appends to `conversationLog` (a vote is not an
 * utterance). Off-candidate votes are dropped from the tally yet kept in the raw
 * `votes` map (#524). The ADR-021 turn-gate transient-skip is exercised here; the
 * D3 systemic-error and D4 circuit-breaker cases ride the same shared gate already
 * covered by [SpeakAllHandlerTests] + [TurnFailureGateTests].
 *
 * Ported for the ADR-023 KMP Engine migration (#501, #1249).
 */
class VoteHandlerTests {

    private val handler = VoteHandler()

    private fun scenario(
        agents: List<String> = listOf("Alice", "Bob", "Charlie"),
        language: String = "en",
        simulationLanguage: String? = null,
        prompt: String? = "Vote!",
        excludeSelf: Boolean? = true,
        outputSchema: Map<String, String> = mapOf("vote" to "string"),
    ) = Scenario(
        id = "t",
        name = "T",
        description = "d",
        language = language,
        simulationLanguage = simulationLanguage,
        agentCount = agents.size,
        rounds = 2,
        logWindow = null,
        context = "A test.",
        personas = agents.map { Persona(name = it, description = "$it's persona.") },
        phases = listOf(
            Phase(type = PhaseType.VOTE, prompt = prompt, outputSchema = outputSchema, excludeSelf = excludeSelf),
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

    private fun votes(target: String) =
        ScriptedLLMBackend.Script.completing("""{"vote": "$target"}""")

    private fun voteResultsEvent(events: List<SimulationEvent>) =
        events.filterIsInstance<SimulationEvent.VoteResults>().single()

    private fun initial(s: Scenario) = SimulationState.initial(s).copy(currentRound = 1)

    // MARK: - Core tally

    @Test
    fun collectsVotesFromAllAgents() = runTest {
        val s = scenario()
        val backend = ScriptedLLMBackend(listOf(votes("Bob"), votes("Alice"), votes("Alice")))
        val next = handler.execute(context(s, backend), initial(s))

        assertEquals(2, next.voteResults["Alice"])
        assertEquals(1, next.voteResults["Bob"])
        assertEquals(3, backend.callCount)
    }

    @Test
    fun emitsVoteResultsEvent() = runTest {
        val s = scenario(agents = listOf("Alice", "Bob"))
        val events = mutableListOf<SimulationEvent>()
        val backend = ScriptedLLMBackend(listOf(votes("Bob"), votes("Alice")))
        handler.execute(context(s, backend, events), initial(s))

        val event = voteResultsEvent(events)
        assertEquals("Bob", event.votes["Alice"])
        assertEquals("Alice", event.votes["Bob"])
    }

    @Test
    fun skipsEliminatedAgents() = runTest {
        val s = scenario()
        // Bob eliminated → Alice and Charlie vote; both target the other active pick.
        val backend = ScriptedLLMBackend(listOf(votes("Charlie"), votes("Alice")))
        val state = initial(s).copy(eliminated = mapOf("Bob" to true))
        handler.execute(context(s, backend), state)

        assertEquals(2, backend.callCount)
    }

    @Test
    fun populatesVoteResultsStateVariable() = runTest {
        // Key must be "vote_results" (plural) to match the {vote_results} placeholder
        // documented in PhaseEditorSheet and used by the word_wolf preset.
        val s = scenario()
        val backend = ScriptedLLMBackend(listOf(votes("Bob"), votes("Alice"), votes("Alice")))
        val next = handler.execute(context(s, backend), initial(s))

        assertEquals("""{"Alice": 2, "Bob": 1}""", next.variables["vote_results"])
        assertNull(next.variables["vote_result"])
    }

    // MARK: - Off-candidate tally drop (#524)

    @Test
    fun dropsInvalidVotesFromTally() = runTest {
        // Three voters (exclude_self default true):
        //   Alice → "Alice"   self-vote, invalid (Alice ∉ her candidates)
        //   Bob   → "Ghost"   hallucinated name, invalid
        //   Charlie → "Bob"   valid
        // Reverting the `candidates.contains(votedFor)` guard would put Alice (self)
        // and Ghost back into the tally — this test goes red in that case.
        val s = scenario()
        val events = mutableListOf<SimulationEvent>()
        val backend = ScriptedLLMBackend(listOf(votes("Alice"), votes("Ghost"), votes("Bob")))
        val next = handler.execute(context(s, backend, events), initial(s))

        assertEquals(mapOf("Bob" to 1), next.voteResults)
        assertNull(next.voteResults["Alice"]) // self-vote dropped
        assertNull(next.voteResults["Ghost"]) // hallucinated dropped

        // Divergence is intentional: the raw votes stay visible in the VoteResults
        // event even though they are absent from the tally.
        val event = voteResultsEvent(events)
        assertEquals("Alice", event.votes["Alice"]) // self-vote preserved in votes map
        assertEquals("Ghost", event.votes["Bob"]) // hallucinated preserved in votes map
        assertEquals("Bob", event.votes["Charlie"])
    }

    @Test
    fun dropsVotesForEliminatedAgentsFromTally() = runTest {
        // Disjoint negative control for the `state.eliminated[name] == true` branch of
        // voteCandidates (the #524 self-vote test above covers only the exclude_self
        // branch). Charlie eliminated; Alice votes the eliminated Charlie (invalid —
        // Charlie ∉ Alice's candidates [Bob]), Bob votes Alice (valid). Reverting the
        // eliminated filter would make Charlie a candidate → Alice's vote tallied → red.
        val s = scenario()
        val events = mutableListOf<SimulationEvent>()
        val backend = ScriptedLLMBackend(listOf(votes("Charlie"), votes("Alice")))
        val state = initial(s).copy(eliminated = mapOf("Charlie" to true))
        val next = handler.execute(context(s, backend, events), state)

        assertEquals(mapOf("Alice" to 1), next.voteResults)
        assertNull(next.voteResults["Charlie"]) // vote for an eliminated agent dropped

        // Raw value still observable in the votes map.
        assertEquals("Charlie", voteResultsEvent(events).votes["Alice"])
    }

    // MARK: - Hybrid write semantics (writes lastOutputs, never conversationLog)

    @Test
    fun writesBallotToLastOutputsAndLeavesConversationLogUntouched() = runTest {
        val s = scenario(agents = listOf("Alice", "Bob"))
        val backend = ScriptedLLMBackend(listOf(votes("Bob"), votes("Alice")))
        val before = initial(s)
        val next = handler.execute(context(s, backend), before)

        // lastOutputs written (relationship_update reads lastOutputs[voter].vote).
        assertEquals("Bob", next.lastOutputs["Alice"]?.fields?.get("vote"))
        assertEquals("Alice", next.lastOutputs["Bob"]?.fields?.get("vote"))
        // A vote is not an utterance — never appended to the conversation log.
        assertTrue(next.conversationLog.isEmpty())
        // Input untouched (immutable-state contract).
        assertTrue(before.lastOutputs.isEmpty())
    }

    // MARK: - simulationLanguage override (ADR-010 Step E)

    @Test
    fun voteHonorsSimulationLanguageOverrideJaToEn() = runTest {
        // ja authoring, en simulation override, prompt:null forces the fallback. The
        // captured prompt must contain the English fallback, not the Japanese one.
        val s = scenario(agents = listOf("Alice", "Bob"), language = "ja", simulationLanguage = "en", prompt = null)
        val backend = ScriptedLLMBackend(listOf(votes("Bob"), votes("Alice")))
        handler.execute(context(s, backend), initial(s))

        val prompt = backend.requests[0].user
        assertTrue(prompt.contains("Vote for the person"))
        assertTrue(!prompt.contains("最も怪しい"))
    }

    @Test
    fun voteHonorsSimulationLanguageOverrideEnToJa() = runTest {
        // Reverse: en authoring, ja simulation override.
        val s = scenario(agents = listOf("Alice", "Bob"), language = "en", simulationLanguage = "ja", prompt = null)
        val backend = ScriptedLLMBackend(listOf(votes("Bob"), votes("Alice")))
        handler.execute(context(s, backend), initial(s))

        val prompt = backend.requests[0].user
        assertTrue(prompt.contains("最も怪しい"))
        assertTrue(!prompt.contains("Vote for the person"))
    }

    // MARK: - Prompt wiring (candidates injection)

    @Test
    fun candidatesVariableIsExpandedForEachVoter() = runTest {
        // The {candidates} variable is the voter's candidate list (exclude_self
        // default true), so Alice's prompt lists Bob, Charlie — never herself.
        val s = scenario(prompt = "Candidates: {candidates}")
        val backend = ScriptedLLMBackend(listOf(votes("Bob"), votes("Alice"), votes("Alice")))
        handler.execute(context(s, backend), initial(s))

        assertEquals("Candidates: Bob, Charlie", backend.requests[0].user)
    }

    // MARK: - captureMood round-trip (single-copy fold, #913)

    @Test
    fun capturedMoodSurfacesInTheNextRoundsPrompt() = runTest {
        // Pins the single success-path `state.copy` fold: captureMood must land in
        // the RETURNED state (folded alongside lastOutputs), else round N's mood never
        // reaches round N+1. Perturbing the captureMood fold turns this red.
        val moodPhase = Phase(
            type = PhaseType.VOTE,
            prompt = "Vote!",
            outputSchema = mapOf("vote" to "string", "mood" to "string"),
        )
        val s = scenario(agents = listOf("Alice", "Bob")).copy(phases = listOf(moodPhase))
        val backend = ScriptedLLMBackend(
            listOf(
                ScriptedLLMBackend.Script.completing("""{"vote": "Bob", "mood": "わくわく"}"""),
                ScriptedLLMBackend.Script.completing("""{"vote": "Alice", "mood": "冷静"}"""),
                ScriptedLLMBackend.Script.completing("""{"vote": "Bob", "mood": "不安"}"""),
                ScriptedLLMBackend.Script.completing("""{"vote": "Alice", "mood": "焦り"}"""),
            ),
        )
        val ctx = context(s, backend)

        val afterRound1 = handler.execute(ctx, initial(s))
        assertEquals("わくわく", afterRound1.variables["mood_Alice"])

        handler.execute(ctx, afterRound1)
        // Alice's round-2 prompt (request index 2) must carry her captured mood.
        assertTrue(backend.requests[2].system.contains("わくわく"))
        assertTrue(backend.requests[2].system.contains("Your Current Mood"))
    }

    // MARK: - Empty vote is a skip, NOT a tally drop (parser-guard distinction)

    @Test
    fun emptyVoteIsAbsorbedAsSkipNotTallyDrop() = runTest {
        // The parser rejects a present-but-empty expected key ({"vote":""} —
        // `hasAllExpectedKeys` requires non-empty content), so three empties exhaust
        // the retry budget → RetriesExhausted → the turn gate absorbs it as a skip
        // (ADR-021 D2). It is therefore an ABSTENTION (no ballot, stale lastOutputs
        // cleared), NOT an off-candidate tally drop — the two paths must not be
        // conflated. Asserted through the skip mechanism, not a tally value.
        val s = scenario(agents = listOf("Alice"))
        val backend = ScriptedLLMBackend(listOf(votes(""), votes(""), votes("")))
        val events = mutableListOf<SimulationEvent>()
        val state = initial(s).copy(
            lastOutputs = mapOf("Alice" to TurnOutput(fields = mapOf("vote" to "stale"))),
        )
        val next = handler.execute(context(s, backend, events), state)

        // Abstention: no ballot in the tally or the votes map, stale output cleared.
        assertTrue(next.voteResults.isEmpty())
        assertNull(voteResultsEvent(events).votes["Alice"])
        assertNull(next.lastOutputs["Alice"])

        // Mechanism: absorbed as a turn skip (no AgentOutput), not a guard-dropped tally.
        assertTrue(events.filterIsInstance<SimulationEvent.AgentOutput>().isEmpty())
        val skipped = events.filterIsInstance<SimulationEvent.TurnSkipped>()
        assertEquals(1, skipped.size)
        assertEquals("Alice", skipped.single().agent)
        assertEquals(PhaseType.VOTE, skipped.single().phaseType)
    }

    // MARK: - Turn degradation (ADR-021 D1/D2)

    @Test
    fun transientFailureAbstainsAndOthersStillVote() = runTest {
        // Alice's call fails transiently (turn-degradable); Bob and Charlie still
        // vote. Alice's ballot is absent from both the votes map and the tally
        // (abstention), and her stale lastOutputs entry is cleared (ADR-021 D2).
        val s = scenario()
        val backend = ScriptedLLMBackend(
            listOf(
                ScriptedLLMBackend.Script(terminal = TerminalStatus.Failed(errorCode = "transient blip")),
                votes("Alice"),
                votes("Alice"),
            ),
        )
        val events = mutableListOf<SimulationEvent>()
        val before = initial(s).copy(
            lastOutputs = mapOf("Alice" to TurnOutput(fields = mapOf("vote" to "stale"))),
        )
        val next = handler.execute(context(s, backend, events), before)

        // Only Bob and Charlie's ballots land; both voted "Alice".
        assertEquals(2, next.voteResults["Alice"])
        assertEquals(1, next.voteResults.size)

        // No AgentOutput for the skipped voter; exactly one TurnSkipped.
        val outputs = events.filterIsInstance<SimulationEvent.AgentOutput>().map { it.agent }
        assertEquals(listOf("Bob", "Charlie"), outputs)

        val skipped = events.filterIsInstance<SimulationEvent.TurnSkipped>()
        assertEquals(1, skipped.size)
        assertEquals("Alice", skipped.single().agent)
        assertEquals(PhaseType.VOTE, skipped.single().phaseType)

        // Abstention: no ballot for Alice in the emitted votes map, stale output cleared.
        val event = voteResultsEvent(events)
        assertNull(event.votes["Alice"])
        assertEquals("Alice", event.votes["Bob"])
        assertNull(next.lastOutputs["Alice"])
        assertEquals("Alice", next.lastOutputs["Bob"]?.fields?.get("vote"))
    }
}
