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
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Kotlin sibling of Swift's `SpeakEachHandlerTests` (+ its `…+TurnDegradation`
 * split), collapsed into one class per the commonTest convention.
 *
 * `speak_each` is the accumulating speak phase and the engine's **sole** seeder of
 * the DRY anti-repetition sampler (#1105). The cases below pin, in ADR-023 §12
 * terms, the mechanisms a green-but-wrong port would silently lose — the sub-round
 * loop and its untrusted-input clamp, the within-phase accumulation that reaches
 * the next speaker's *prompt* (not merely the log), the per-agent seed selection
 * and its blank filter, `captureMood`, and both ADR-021 degradation arms.
 *
 * **Why the seed cases assert against `backend.requests`**: this handler is the
 * only producer of `antiRepetitionSeeds`, so no consumer test can catch a dropped
 * seed — a backend handed `emptyList()` behaves exactly like one serving a phase
 * that legitimately does not seed. Asserting at `LLMCaller` level would pin the
 * plumbing while leaving the decision of *what* to seed untested.
 *
 * Ported for the ADR-023 KMP Engine migration (#501, #1307).
 */
class SpeakEachHandlerTests {

    private val handler = SpeakEachHandler()

    private fun scenario(
        agents: List<String> = listOf("Alice", "Bob"),
        language: String = "en",
        simulationLanguage: String? = null,
        prompt: String? = "Talk",
        subRounds: Int? = null,
        outputSchema: Map<String, String> = mapOf("statement" to "string"),
        logWindow: Int? = null,
    ) = Scenario(
        id = "t",
        name = "T",
        description = "d",
        language = language,
        simulationLanguage = simulationLanguage,
        agentCount = agents.size,
        rounds = 2,
        logWindow = logWindow,
        context = "A test.",
        personas = agents.map { Persona(name = it, description = "$it's persona.") },
        phases = listOf(
            Phase(
                type = PhaseType.SPEAK_EACH,
                prompt = prompt,
                outputSchema = outputSchema,
                subRounds = subRounds,
            ),
        ),
    )

    private fun context(
        s: Scenario,
        backend: LLMBackend,
        events: MutableList<SimulationEvent> = mutableListOf(),
    ) = PhaseContext(
        scenario = s,
        phase = s.phases[0],
        backend = backend,
        suspensionRelay = SuspensionRelay(),
        emitter = { events += it },
        pauseCheck = { },
        phasePath = listOf(0),
        turnGate = TurnFailureGate(),
    )

    private fun says(statement: String) =
        ScriptedLLMBackend.Script.completing("""{"statement": "$statement"}""")

    private fun failing() =
        ScriptedLLMBackend.Script(terminal = TerminalStatus.Failed(errorCode = "transient blip"))

    private fun initial(s: Scenario) = SimulationState.initial(s).copy(currentRound = 1)

    private fun skips(events: List<SimulationEvent>) =
        events.filterIsInstance<SimulationEvent.TurnSkipped>()

    private fun outputs(events: List<SimulationEvent>) =
        events.filterIsInstance<SimulationEvent.AgentOutput>()

    // MARK: - Sub-round loop

    @Test
    fun executesSubRoundsInOrder() = runTest {
        // 2 agents x 2 sub-rounds = 4 calls, personas in declaration order within
        // each sub-round.
        val s = scenario(subRounds = 2)
        val backend = ScriptedLLMBackend(listOf(says("A1"), says("B1"), says("A2"), says("B2")))
        val next = handler.execute(context(s, backend), initial(s))

        assertEquals(4, backend.callCount)
        assertEquals(
            listOf("Alice", "Bob", "Alice", "Bob"),
            next.conversationLog.map { it.agentName },
        )
    }

    @Test
    fun defaultsToOneSubRound() = runTest {
        val s = scenario()
        val backend = ScriptedLLMBackend(listOf(says("hi"), says("hey")))
        handler.execute(context(s, backend), initial(s))
        assertEquals(2, backend.callCount)
    }

    @Test
    fun skipsEliminatedAgents() = runTest {
        // Alice's `false` entry is written explicitly. `SimulationState.initial`
        // seeds EVERY agent to `false`, so a bare `mapOf("Bob" to true)` would
        // *replace* that map and leave Alice absent — under which a wrong
        // `eliminated[name] != null` guard still passes this test while skipping
        // everyone against real state.
        val s = scenario()
        val backend = ScriptedLLMBackend(listOf(says("only Alice")))
        val state = initial(s).copy(eliminated = mapOf("Alice" to false, "Bob" to true))
        handler.execute(context(s, backend), state)
        assertEquals(1, backend.callCount)
    }

    @Test
    fun anAgentAbsentFromTheEliminatedMapIsActive() = runTest {
        // The other polarity the impl comment argues for: a missing key reads
        // `null`, which is not `true`, so the agent speaks. `!= false` would skip
        // every agent the map never mentions.
        val s = scenario()
        val backend = ScriptedLLMBackend(listOf(says("A"), says("B")))
        handler.execute(context(s, backend), initial(s).copy(eliminated = emptyMap()))
        assertEquals(2, backend.callCount)
    }

    // MARK: - subRounds clamp (untrusted YAML guard, #1064)

    @Test
    fun zeroSubRoundsRunsOncePerPersona() = runTest {
        // Swift clamps because `1...0` forms an invalid ClosedRange and TRAPS.
        // Kotlin's `1..0` is merely EMPTY, so an unclamped port would run zero
        // inferences and emit an empty phase — no crash, no diagnostic. That
        // quieter failure is what this pins: reverting `maxOf(1, …)` turns the
        // expected 2 into 0.
        val s = scenario(subRounds = 0)
        val backend = ScriptedLLMBackend(listOf(says("A1"), says("B1")))
        handler.execute(context(s, backend), initial(s))
        assertEquals(2, backend.callCount)
    }

    // Adds no discrimination over the zero case in Kotlin (`1..0` and `1..-1`
    // are both empty ranges); kept as the Swift-parity pair, where the two inputs
    // were distinct trap arguments.
    @Test
    fun negativeSubRoundsRunsOncePerPersona() = runTest {
        val s = scenario(subRounds = -1)
        val backend = ScriptedLLMBackend(listOf(says("A1"), says("B1")))
        handler.execute(context(s, backend), initial(s))
        assertEquals(2, backend.callCount)
    }

    // MARK: - Accumulation within sub-rounds (the speak_all difference)

    @Test
    fun accumulatesConversationWithinSubRounds() = runTest {
        val s = scenario(prompt = "{conversation_log}", subRounds = 2)
        val backend = ScriptedLLMBackend(
            listOf(says("first"), says("second"), says("third"), says("fourth")),
        )
        val next = handler.execute(context(s, backend), initial(s))

        assertEquals(4, next.conversationLog.size)
        assertEquals("first", next.conversationLog[0].content)
        assertEquals("fourth", next.conversationLog[3].content)
    }

    @Test
    fun eachSpeakerSeesTheEarlierSpeakersOfTheSameSubRoundInItsPrompt() = runTest {
        // The mechanism the log assertion above does NOT reach. Accumulation is
        // produced by threading each turn's returned state into the next turn, so
        // reading `state` (the phase-start value) instead of the threaded `current`
        // would leave the log correct at the end while every prompt saw an empty
        // conversation. Asserting the PROMPT is what separates the two.
        val s = scenario(prompt = "Log: {conversation_log}")
        val backend = ScriptedLLMBackend(listOf(says("alice speaks"), says("bob speaks")))
        handler.execute(context(s, backend), initial(s))

        assertEquals(2, backend.requests.size)
        assertFalse(
            backend.requests[0].user.contains("alice speaks"),
            "the first speaker must not see itself",
        )
        assertContains(backend.requests[1].user, "alice speaks")
    }

    @Test
    fun logWindowTrimsTheAccumulatedLogTheNextSpeakerSees() = runTest {
        // The window trims the SAME log the #911 address rule tells the agent to
        // refer to (ADR-024 lint R17: keep `log_window >= agentCount` for
        // accumulating scenarios). speak_each is where that interaction bites, so
        // the axis belongs here and not only on the speak_all sibling.
        val s = scenario(
            agents = listOf("A", "B", "C"),
            prompt = "Log: {conversation_log}",
            logWindow = 1,
        )
        val backend = ScriptedLLMBackend(listOf(says("1"), says("2"), says("3")))
        handler.execute(context(s, backend), initial(s))

        val third = backend.requests[2].user
        assertContains(third, "B: 2")
        assertFalse(third.contains("A: 1"), "window=1 must trim the older entry")
    }

    // MARK: - Anti-repetition seeding (#1105) — sole producer in the engine

    @Test
    fun seedsOwnPriorStatementPerAgentAcrossSubRounds() = runTest {
        // Call order: Alice-r1, Bob-r1, Alice-r2, Bob-r2. Each agent's second turn
        // seeds ITS OWN first-turn statement — not the globally-last one, which is
        // the tempting simplification and would seed Alice-r2 with "bob-r1".
        val s = scenario(subRounds = 2)
        val backend = ScriptedLLMBackend(
            listOf(says("alice-r1"), says("bob-r1"), says("alice-r2"), says("bob-r2")),
        )
        handler.execute(context(s, backend), initial(s))

        assertEquals(
            listOf(emptyList(), emptyList(), listOf("alice-r1"), listOf("bob-r1")),
            backend.requests.map { it.antiRepetitionSeeds },
        )
    }

    @Test
    fun whitespaceOnlyPriorDoesNotSeed() = runTest {
        // An empty or "..." statement is already caught upstream by the
        // empty-field retry, but a blank-but-nonempty one reaches `lastOutputs`.
        // Dropping the `isNotBlank()` filter makes the second seed `["   "]`.
        // Depends on `LLMCaller.hasEmptyFields` treating `"   "` as non-empty (it
        // tests `== "..."` / `isEmpty()`, no trim). If that is ever hardened this
        // fails as "ScriptedLLMBackend exhausted" rather than as a seed mismatch.
        val s = scenario(agents = listOf("Alice"), subRounds = 2)
        val backend = ScriptedLLMBackend(listOf(says("   "), says("alice-r2")))
        handler.execute(context(s, backend), initial(s))

        assertEquals(
            listOf(emptyList(), emptyList()),
            backend.requests.map { it.antiRepetitionSeeds },
        )
    }

    @Test
    fun seedsThePriorStatementCarriedInFromAnEarlierPhase() = runTest {
        // `lastOutputs` survives across phases, so the FIRST sub-round is not
        // unconditionally unseeded — it seeds whatever the agent last said. Pins
        // that the seed reads state rather than a phase-local accumulator.
        val s = scenario(agents = listOf("Alice"))
        val backend = ScriptedLLMBackend(listOf(says("fresh")))
        val state = initial(s).copy(
            lastOutputs = mapOf("Alice" to TurnOutput(fields = mapOf("statement" to "from an earlier phase"))),
        )
        handler.execute(context(s, backend), state)

        assertEquals(listOf("from an earlier phase"), backend.requests.single().antiRepetitionSeeds)
    }

    // MARK: - captureMood (#913)

    @Test
    fun capturesMoodIntoTheReservedStateVariable() = runTest {
        // No Swift sibling — `SpeakEachHandler.swift` calls `captureMood` on its
        // success path but no Swift test covers it, so a faithful port of the Swift
        // suite alone stays green with the call dropped entirely. The write also has
        // to survive the SAME `state.copy` as the log and `lastOutputs` writes; a
        // second copy off the original would silently discard one of the three.
        // Same shape as `ChooseHandlerTests`' fold assertion — see that suite's
        // § "State threading" reasoning.
        val s = scenario(
            agents = listOf("Alice"),
            outputSchema = mapOf("statement" to "string", "mood" to "string"),
        )
        val backend = ScriptedLLMBackend(
            listOf(ScriptedLLMBackend.Script.completing("""{"statement": "hi", "mood": "uneasy"}""")),
        )
        val next = handler.execute(context(s, backend), initial(s))

        assertEquals("uneasy", next.variables["mood_Alice"])
        // The other two success-path writes must have survived the same copy.
        assertEquals(1, next.conversationLog.size)
        assertEquals("hi", next.lastOutputs["Alice"]?.fields?.get("statement"))
        // `nextVariables` is derived from the PERSISTED `state.variables`, never
        // from the throwaway prompt map. Reusing the latter would persist every
        // reserved-namespace token — leaking one agent's `assigned` / `my_whispers`
        // into the next agent's `appendPrivateSections` read — and no other
        // assertion in this suite would move.
        assertEquals(setOf("mood_Alice"), next.variables.keys)
    }

    // MARK: - simulationLanguage override on the fallback prompt (ADR-010 Step E)

    @Test
    fun honorsSimulationLanguageOverrideJaToEn() = runTest {
        // `prompt = null` forces the pickLanguage fallback, which is the only text
        // the override can move here.
        val s = scenario(language = "ja", simulationLanguage = "en", prompt = null)
        val backend = ScriptedLLMBackend(listOf(says("hello"), says("world")))
        handler.execute(context(s, backend), initial(s))

        val user = backend.requests[0].user
        assertContains(user, "Conversation so far")
        assertFalse(user.contains("これまでの会話"))
    }

    @Test
    fun honorsSimulationLanguageOverrideEnToJa() = runTest {
        val s = scenario(language = "en", simulationLanguage = "ja", prompt = null)
        val backend = ScriptedLLMBackend(listOf(says("hello"), says("world")))
        handler.execute(context(s, backend), initial(s))

        val user = backend.requests[0].user
        assertContains(user, "これまでの会話")
        assertFalse(user.contains("Conversation so far"))
    }

    // MARK: - Turn degradation (ADR-021 D1/D2/D3)

    @Test
    fun transientFailureSkipsTurnAndOthersStillSpeak() = runTest {
        // Alice's call fails turn-degradably; Bob and Charlie still speak in the
        // same sub-round. The stale prior-round `lastOutputs` for Alice is cleared
        // so a downstream consumer cannot read a decision that never happened.
        val s = scenario(agents = listOf("Alice", "Bob", "Charlie"))
        val backend = ScriptedLLMBackend(
            listOf(failing(), says("hello from Bob"), says("hello from Charlie")),
        )
        val events = mutableListOf<SimulationEvent>()
        val state = initial(s).copy(
            lastOutputs = mapOf("Alice" to TurnOutput(fields = mapOf("statement" to "stale"))),
        )
        val next = handler.execute(context(s, backend, events), state)

        assertEquals(listOf("Bob", "Charlie"), outputs(events).map { it.agent })
        assertEquals(listOf("Bob", "Charlie"), next.conversationLog.map { it.agentName })

        val skipped = skips(events)
        assertEquals(1, skipped.size)
        assertEquals("Alice", skipped.single().agent)
        assertEquals(PhaseType.SPEAK_EACH, skipped.single().phaseType)

        assertNull(next.lastOutputs["Alice"])
        assertEquals("hello from Bob", next.lastOutputs["Bob"]?.fields?.get("statement"))
        assertEquals("hello from Charlie", next.lastOutputs["Charlie"]?.fields?.get("statement"))
    }

    @Test
    fun aSkippedTurnLeavesTheNextSubRoundUnseeded() = runTest {
        // The seed reads `lastOutputs`, and the D2 skip clears it — so the agent's
        // next sub-round seeds empty rather than re-seeding a pre-failure
        // statement. Both mechanisms are Swift-faithful; this pins their
        // interaction, which neither one's own test observes.
        val s = scenario(agents = listOf("Alice"), subRounds = 3)
        val backend = ScriptedLLMBackend(listOf(says("first"), failing(), says("third")))
        handler.execute(context(s, backend), initial(s))

        assertEquals(
            listOf(emptyList(), listOf("first"), emptyList()),
            backend.requests.map { it.antiRepetitionSeeds },
        )
    }

    @Test
    fun theHandlerAddsNoCatchOfItsOwnAroundATurn() = runTest {
        // NOT an ADR-021 D3 classification test, despite the shape. The error is
        // thrown from the backend, i.e. outside `LLMCaller`'s mapping, so widening
        // `TurnFailureGate.isTurnDegradable` — the actual D3 regression — leaves
        // this green. D3 classification is `TurnFailureGateTests.systemicError
        // RethrowsTypedWithoutSkip`, and `SpeakAllHandlerTests` records why no
        // handler-level D3 case exists yet (every failure a ScriptedLLMBackend can
        // produce maps to the degradable `LlmGenerationFailed` until the Stage-3
        // `StreamFailure` taxonomy lands).
        //
        // What it DOES pin is narrower and still worth having: this handler wraps
        // its turn in no `try`/`catch` of its own, so nothing here can swallow a
        // non-degradable throw into a skip. Restore the real D3 case with the
        // taxonomy (#501).
        val s = scenario()
        val events = mutableListOf<SimulationEvent>()

        assertFailsWith<SystemicProbeError> {
            handler.execute(context(s, ThrowingBackend(), events), initial(s))
        }
        assertTrue(skips(events).isEmpty())
        assertTrue(outputs(events).isEmpty())
    }
}

/**
 * Stands in for a fault the gate must not degrade.
 *
 * Extends [Exception] deliberately, mirroring `TurnFailureGateTests`' `ProbeError`:
 * it must stay disjoint from `CancellationException` (itself an
 * `IllegalStateException`), or a later "simplify to IllegalStateException" edit
 * would silently reclassify this as the cancellation path.
 */
private class SystemicProbeError : Exception("systemic")

/** A backend whose call is a systemic fault rather than a generation failure. */
private class ThrowingBackend : LLMBackend {
    override fun generateStream(request: GenerationRequest, callbacks: StreamCallbacks): StreamHandle =
        throw SystemicProbeError()
}
