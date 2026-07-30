package com.pastura.engine

import com.pastura.models.ConversationEntry
import com.pastura.models.Persona
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState
import com.pastura.models.TurnOutput
import kotlinx.coroutines.test.runTest
import kotlin.coroutines.cancellation.CancellationException
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/**
 * Kotlin sibling of Swift's `NarrateHandlerTests`, collapsed into one class per the
 * commonTest convention.
 *
 * `narrate` is the one LLM phase that is **not** an agent turn: one inference per
 * round, no participation, and degradation by omission instead of through
 * [TurnFailureGate]. The cases below pin, in ADR-023 §12 terms, the mechanisms a
 * green-but-wrong port would silently lose.
 *
 * ## §12 condition-4 perturbation record
 *
 * Each mechanism was broken in isolation and the named **dedicated claimant**
 * confirmed to redden (a claimant that stayed green would be a measurement defect,
 * not a redundant test). Three mutations also break the happy path and so redden
 * most of the suite; that **incidental** breakage is listed separately, because a
 * wide red set is not evidence about the axis. Measured 2026-07-30, #1330.
 *
 * | Mechanism broken | Dedicated claimant | Incidental |
 * |---|---|---|
 * | Empty-log guard → `isNotEmpty()` | [skipsEmissionOnEmptyLog] | 12 others (inverting also skips the happy path) |
 * | Catch arm `return state` → `throw e` | [degradesByOmissionOnFailure] | 1 ([emptyCommentaryIsAbsorbedByTheCatchArmNotTheGuard], which routes through the same arm) |
 * | Catch breadth → `catch (e: Throwable)` | [aSystemicThrowEscapesRatherThanDegrading], [cancellationEscapesRatherThanBeingSwallowed] | none |
 * | `emitter = {}` → `context.emitter` | [suppressesTheNarratorsAgentAttributedEvents] | none |
 * | Final `return state` → a persisting `copy` | [narratorIsNotAParticipant] | none |
 * | Descriptor section dropped | [injectsNarratorDescriptorIntoSystemPrompt] | none |
 * | Schema field renamed | [requestsCommentarySchema] | 8 others (the parse then fails) |
 * | A second inference added | [singleInferenceRegardlessOfAgentCount] | 10 others (the script list runs out) |
 * | Empty-commentary guard **deleted** | *(none — expected green)* | none |
 *
 * The last row is the point of the exercise, not a gap: the guard is unreachable on
 * this side, so nothing can redden. Confirmed by measurement rather than asserted —
 * see [emptyCommentaryIsAbsorbedByTheCatchArmNotTheGuard].
 *
 * Note what the "one inference" row does **not** establish. Its assertion is
 * `callCount == 1`, so it catches any multiplication of the call but does not by
 * itself prove agent-count *independence*; that claim rests on `callCount == 1`
 * **together with** the 3-agent pin in [scenario], which is why the pin is asserted
 * in the test body rather than left implicit.
 *
 * Ported for the ADR-023 KMP Engine migration (#501, #1330).
 */
class NarrateHandlerTests {

    private val handler = NarrateHandler()

    /**
     * Three agents pinned explicitly: [singleInferenceRegardlessOfAgentCount] relies
     * on `agentCount > 1` to prove per-round rather than per-agent inference, so it
     * must not silently weaken to `1 == 1`.
     */
    private fun scenario(
        narrator: String? = null,
        prompt: String? = null,
        language: String = "en",
        maxSentences: Int? = null,
        agents: List<String> = listOf("Alice", "Bob", "Charlie"),
        context: String = "A test.",
    ) = Scenario(
        id = "t",
        name = "T",
        description = "d",
        language = language,
        simulationLanguage = null,
        agentCount = agents.size,
        rounds = 2,
        logWindow = null,
        context = context,
        personas = agents.map { Persona(name = it, description = "$it's persona.") },
        phases = listOf(
            Phase(
                type = PhaseType.NARRATE,
                prompt = prompt,
                narrator = narrator,
                maxSentences = maxSentences,
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

    /**
     * A state whose conversation log is non-empty, so narrate has facts to ground on
     * and does not hit the empty-log skip.
     *
     * `conversationLog` defaults to `emptyList()` on [SimulationState.initial] — only
     * `eliminated` is seeded — so replacing it wholesale here cannot hide an
     * absent-key hole (`.claude/rules/kmp-interop.md` Pattern 4). narrate never reads
     * `eliminated` regardless.
     */
    private fun stateWithLog(s: Scenario) = SimulationState.initial(s).copy(
        currentRound = 1,
        conversationLog = listOf(
            ConversationEntry(
                agentName = "Alice",
                content = "I accuse Bob.",
                phaseType = PhaseType.SPEAK_ALL,
                round = 1,
            ),
            ConversationEntry(
                agentName = "Bob",
                content = "That is absurd.",
                phaseType = PhaseType.SPEAK_ALL,
                round = 1,
            ),
        ),
    )

    private fun narrates(commentary: String) =
        ScriptedLLMBackend.Script.completing("""{"commentary": "$commentary"}""")

    private fun narrations(events: List<SimulationEvent>) =
        events.filterIsInstance<SimulationEvent.Narration>()

    private fun skips(events: List<SimulationEvent>) =
        events.filterIsInstance<SimulationEvent.TurnSkipped>()

    // MARK: - Happy path

    @Test
    fun emitsNarrationOnSuccess() = runTest {
        val s = scenario()
        val backend = ScriptedLLMBackend(listOf(narrates("Alice went on the attack!")))
        val events = mutableListOf<SimulationEvent>()

        handler.execute(context(s, backend, events), stateWithLog(s))

        assertEquals(listOf("Alice went on the attack!"), narrations(events).map { it.text })
    }

    @Test
    fun singleInferenceRegardlessOfAgentCount() = runTest {
        // 3 agents, but narrate must call the backend exactly ONCE: the narrator is
        // not a participant, so cost is agent-count-independent. A per-persona loop
        // would issue 3 calls and exhaust the single script.
        val s = scenario()
        val backend = ScriptedLLMBackend(listOf(narrates("A tense round.")))

        handler.execute(context(s, backend), stateWithLog(s))

        assertEquals(3, s.personas.size, "the per-round claim needs agentCount > 1 to mean anything")
        assertEquals(1, backend.callCount)
    }

    @Test
    fun narratorIsNotAParticipant() = runTest {
        // Whole-state equality, deliberately: it is trivially true today (execute
        // returns its input `state`), and that is the point — it becomes a real
        // change-detector the moment someone adds a `state.copy(...)` that persists
        // something, which is the failure mode a ReflectHandler-shaped port invites.
        // Do NOT delete this as tautological; see the class KDoc's perturbation record.
        val s = scenario()
        val backend = ScriptedLLMBackend(listOf(narrates("What a move.")))
        val events = mutableListOf<SimulationEvent>()
        val before = stateWithLog(s).copy(
            lastOutputs = mapOf("Alice" to TurnOutput(fields = mapOf("statement" to "I accuse Bob."))),
        )

        val after = handler.execute(context(s, backend, events), before)

        assertEquals(before, after, "narrate must persist nothing at all")
        // Spelled out too, so a failure names the field rather than dumping two states.
        assertEquals(before.conversationLog, after.conversationLog)
        assertEquals(before.lastOutputs, after.lastOutputs)
        assertEquals(before.variables, after.variables)
        // Never an AgentOutput — that is what would put the narrator in votes,
        // scores, and the scoreboard.
        assertTrue(events.filterIsInstance<SimulationEvent.AgentOutput>().isEmpty())
        assertEquals(1, narrations(events).size)
    }

    @Test
    fun suppressesTheNarratorsAgentAttributedEvents() = runTest {
        // `emitter = {}` into LLMCaller: the ONLY event reaching the real emitter is
        // the final Narration. Handing LLMCaller `context.emitter` instead would leak
        // InferenceStarted / InferenceCompleted / AgentOutputStream under the reserved
        // "narrator" name and render it as a participant row.
        val s = scenario()
        val backend = ScriptedLLMBackend(listOf(narrates("Quiet round.")))
        val events = mutableListOf<SimulationEvent>()

        handler.execute(context(s, backend, events), stateWithLog(s))

        assertEquals(1, events.size, "expected only the Narration, got: $events")
        assertTrue(events.single() is SimulationEvent.Narration)
    }

    // MARK: - The three skip paths

    @Test
    fun skipsEmissionOnEmptyLog() = runTest {
        // Round 1 before any speak phase: nothing to narrate, so no inference and no
        // event — the hallucination edge is answered by skipping, not inventing.
        // An empty script list is correct HERE precisely because zero calls are
        // expected: any call at all trips the harness's exhaustion signal.
        val s = scenario()
        val backend = ScriptedLLMBackend(emptyList())
        val events = mutableListOf<SimulationEvent>()

        handler.execute(context(s, backend, events), SimulationState.initial(s).copy(currentRound = 1))

        assertEquals(0, backend.callCount)
        assertTrue(narrations(events).isEmpty())
    }

    @Test
    fun degradesByOmissionOnFailure() = runTest {
        // A generation failure emits no Narration, no TurnSkipped, and execute does
        // NOT throw: narrate degrades by omission and bypasses the agent-attributed
        // TurnFailureGate, so an ADR-021 breaker increment must not happen either
        // (#909 critic Axis 4).
        //
        // A `Failed` terminal, NOT `ScriptedLLMBackend(emptyList())`. Exhaustion
        // throws IllegalStateException as a deliberate *test-harness bug* signal
        // (LLMBackendTestSupport), so porting Swift's `MockLLMService(responses: [])`
        // 1:1 would either fail this test or pressure the handler's catch wide open —
        // manufacturing the very defect `cancellationEscapesRatherThanBeingSwallowed`
        // guards. `Failed` is not retried by LLMCaller, so one script suffices.
        val s = scenario()
        val backend = ScriptedLLMBackend(
            listOf(ScriptedLLMBackend.Script(terminal = TerminalStatus.Failed(errorCode = "transient blip"))),
        )
        val events = mutableListOf<SimulationEvent>()

        val after = handler.execute(context(s, backend, events), stateWithLog(s))

        assertTrue(narrations(events).isEmpty())
        assertTrue(skips(events).isEmpty(), "narrate must never emit TurnSkipped: $events")
        assertEquals(stateWithLog(s), after)
    }

    @Test
    fun emptyCommentaryIsAbsorbedByTheCatchArmNotTheGuard() = runTest {
        // Swift's sibling case is named `skipsEmissionOnEmptyCommentary` and drives
        // the handler's `commentary.isEmpty()` guard. **In Kotlin it cannot.** The
        // parser applies `hasAllExpectedKeys` on every successful parse when the
        // schema declares keys, and narrate always declares `{ commentary }`, so
        // `{"commentary": ""}` throws JsonParseFailed on each of the 3 attempts and
        // arrives as RetriesExhausted at the catch arm instead.
        //
        // So this asserts the observable (no Narration emitted), never the guard.
        // Deleting the guard leaves this test green — that is a fact about the
        // divergence, not a coverage gap, and the guard stays as defensive parity per
        // the ReflectHandler precedent. Do not "strengthen" this into guard coverage;
        // no input reaches it from here.
        val s = scenario()
        val backend = ScriptedLLMBackend(List(LLMCaller.MAX_RETRIES + 1) { narrates("") })
        val events = mutableListOf<SimulationEvent>()

        handler.execute(context(s, backend, events), stateWithLog(s))

        assertEquals(LLMCaller.MAX_RETRIES + 1, backend.callCount, "expected the full retry budget")
        assertTrue(narrations(events).isEmpty())
        assertTrue(skips(events).isEmpty())
    }

    // MARK: - Catch breadth (negative controls for the narrowed catch)

    @Test
    fun aSystemicThrowEscapesRatherThanDegrading() = runTest {
        // The catch is `SimulationException`, so a fault outside that class must
        // propagate rather than be silently absorbed as "no commentary this round".
        val s = scenario()
        val events = mutableListOf<SimulationEvent>()

        assertFailsWith<NarrateProbeError> {
            handler.execute(context(s, NarrateThrowingBackend(), events), stateWithLog(s))
        }
        assertTrue(narrations(events).isEmpty())
    }

    @Test
    fun cancellationEscapesRatherThanBeingSwallowed() = runTest {
        // The motivating case for narrowing the catch. Kotlin cancellation is a
        // *throw*, and narrate has no TurnFailureGate to rethrow it (the gate catches
        // Throwable but re-throws anything non-degradable). A broad catch here would
        // absorb a user's cancel and let the run continue to the next suspension
        // point — silently, with no diagnostic. Swift's bare `catch` is safe only
        // because its runner polls `Task.isCancelled`.
        val s = scenario()
        val events = mutableListOf<SimulationEvent>()

        assertFailsWith<CancellationException> {
            handler.execute(context(s, NarrateCancellingBackend(), events), stateWithLog(s))
        }
        assertTrue(narrations(events).isEmpty())
    }

    // MARK: - Prompt construction

    @Test
    fun injectsNarratorDescriptorIntoSystemPrompt() = runTest {
        // The optional `narrator:` descriptor shapes the commentator's voice and is
        // injected into the Engine-owned system prompt.
        val s = scenario(narrator = "熱血なスポーツ実況")
        val backend = ScriptedLLMBackend(listOf(narrates("ok")))

        handler.execute(context(s, backend), stateWithLog(s))

        assertContains(backend.requests.single().system, "熱血なスポーツ実況")
    }

    @Test
    fun omitsTheDescriptorSectionWhenNarratorIsAbsent() = runTest {
        // Guards the `isNotEmpty()` branch: a blank descriptor must not emit an empty
        // "Commentator persona:" heading with nothing after it.
        val s = scenario(narrator = "   ")
        val backend = ScriptedLLMBackend(listOf(narrates("ok")))

        handler.execute(context(s, backend), stateWithLog(s))

        assertTrue("Commentator persona" !in backend.requests.single().system)
    }

    @Test
    fun groundsTheUserPromptInTheConversationLog() = runTest {
        // The log IS the factuality grounding — the default template expands
        // {conversation_log}, so a dropped expansion would leave the model narrating
        // an unseen round.
        val s = scenario()
        val backend = ScriptedLLMBackend(listOf(narrates("ok")))

        handler.execute(context(s, backend), stateWithLog(s))

        val user = backend.requests.single().user
        assertContains(user, "I accuse Bob.")
        assertContains(user, "That is absurd.")
        assertTrue("{conversation_log}" !in user, "the placeholder must be expanded, not passed through")
    }

    @Test
    fun clampsMaxSentencesIntoTheSwiftValidatorRange() = runTest {
        // `max_sentences: 0` is rejected Swift-side by ScenarioValidator, which is not
        // ported — so un-clamped this renders "at most 0 sentence(s)", an
        // unsatisfiable instruction. Asserts the clamped floor of 1.
        val s = scenario(maxSentences = 0)
        val backend = ScriptedLLMBackend(listOf(narrates("ok")))

        handler.execute(context(s, backend), stateWithLog(s))

        val system = backend.requests.single().system
        assertContains(system, "at most 1 sentence(s)")
        assertTrue("at most 0" !in system)
    }

    @Test
    fun requestsCommentarySchema() = runTest {
        // Engine-fixed single-field `{ commentary }` schema — not author-declared, so
        // the backend receives exactly that constraint regardless of the phase YAML.
        val s = scenario()
        val backend = ScriptedLLMBackend(listOf(narrates("ok")))

        handler.execute(context(s, backend), stateWithLog(s))

        val schema = backend.requests.single().schema
        assertEquals(listOf("commentary"), schema?.fields?.map { it.name })
    }
}

/**
 * Stands in for a fault narrate must not absorb.
 *
 * Extends [Exception] deliberately, mirroring `SpeakEachHandlerTests`'
 * `SystemicProbeError`: it must stay disjoint from `CancellationException` (itself
 * an `IllegalStateException`), or a later "simplify to IllegalStateException" edit
 * would silently reclassify this as the cancellation path.
 */
private class NarrateProbeError : Exception("systemic")

/** A backend whose call is a systemic fault rather than a generation failure. */
private class NarrateThrowingBackend : LLMBackend {
    override fun generateStream(request: GenerationRequest, callbacks: StreamCallbacks): StreamHandle =
        throw NarrateProbeError()
}

/** A backend that cancels, so the handler's catch breadth is measurable. */
private class NarrateCancellingBackend : LLMBackend {
    override fun generateStream(request: GenerationRequest, callbacks: StreamCallbacks): StreamHandle =
        throw CancellationException("cancelled mid-narration")
}
