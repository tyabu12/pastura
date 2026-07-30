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
 * not a redundant test). Two mutations also break the happy path and so redden most
 * of the suite; that **incidental** breakage is listed separately, because a wide red
 * set is not evidence about the axis. Counts are measured, not derived —
 * re-measure rather than reason if you change a fixture. Measured 2026-07-30, #1330.
 *
 * | Mechanism broken | Mutation | Dedicated claimant | Incidental |
 * |---|---|---|---|
 * | Empty-log guard | `if (…isEmpty())` → `if (false)` | [skipsEmissionOnEmptyLog] | none |
 * | Catch arm degrades | `return state` → `error(…)` | [degradesByOmissionOnFailure] | 1 — [emptyCommentaryIsAbsorbedByTheCatchArmNotTheGuard] routes through the same arm |
 * | Catch breadth | `SimulationException` → `Throwable` | [aSystemicThrowEscapesRatherThanDegrading], [cancellationEscapesRatherThanBeingSwallowed] | none |
 * | Emitter swallowing | `emitter = {}` → `context.emitter` | [suppressesTheNarratorsAgentAttributedEvents] | none |
 * | Persists nothing | final `return state` → a `copy` writing a probe var | [narratorIsNotAParticipant] | none |
 * | Descriptor gate — **closed** | `if (trimmed.isNotEmpty())` → `if (false)` | [injectsNarratorDescriptorIntoSystemPrompt] | none |
 * | Descriptor gate — **open** | same → `if (true)` | [omitsTheDescriptorSectionWhenNarratorIsBlank] | none |
 * | `max_sentences` clamp (divergence 6) | `.coerceIn(1, 6)` deleted | [clampsMaxSentencesIntoTheSwiftValidatorRange], [clampsMaxSentencesToTheUpperBoundToo] | none |
 * | Log grounding | `variables["conversation_log"] = …` dropped | [groundsTheUserPromptInTheConversationLog] | none |
 * | Engine-fixed schema | field `"commentary"` → `"comment"` | [requestsCommentarySchema] | 10 (every response then fails to parse) |
 * | One inference per round | a 2nd `call` immediately **before the `try`** | [singleInferenceRegardlessOfAgentCount] | 11 (it consumes script #1) |
 * | Empty-commentary guard | block **deleted** | *(none — expected green)* | none |
 *
 * Four things this table encodes that a first draft of it got wrong:
 *
 * 1. **The last row is the point, not a gap.** The guard is unreachable on this side,
 *    so nothing can redden. Measured, not assumed — see
 *    [emptyCommentaryIsAbsorbedByTheCatchArmNotTheGuard].
 * 2. **Both gate polarities are measured.** `if (false)` removes the descriptor
 *    *append*; only `if (true)` breaks the *gate*, and that is what
 *    [omitsTheDescriptorSectionWhenNarratorIsBlank] guards. Testing one polarity
 *    leaves the other test green by construction.
 * 3. **The mutation column is load-bearing, down to the exact site.** The "one
 *    inference" row's incidental count holds only for an extra call placed
 *    *outside* the `try`, where its own `SimulationException` is unguarded and so
 *    reddens the two catch-arm tests as well. Placed *inside* the `try` — which is
 *    what the realistic regression, a per-persona loop, would look like — those two
 *    stay green and the count is lower. "Before the real call" alone does not
 *    identify the mutation.
 * 4. **A claimant must fail on its own assertion.** [requestsCommentarySchema] is
 *    scripted with the full retry budget precisely so a renamed field reddens it at
 *    `assertEquals`, not via the harness's script-exhaustion error — which would be
 *    the same failure mode as all 10 incidentals and therefore no evidence at all.
 *
 * **Coverage of the table itself**: 12 axes, 13 of the 16 tests are a dedicated
 * claimant, and every mechanism named in the handler's "Divergences" list has a row —
 * including the clamp, which was only ever *incidental* until this was checked. The
 * three non-claimants are deliberate: [emitsNarrationOnSuccess] pins the happy path
 * (it is the baseline the other rows perturb), [usesTheHandlersOwnDefaultWhenMaxSentencesIsAbsent]
 * pins a value no mutation can isolate while both defaults are 3 (see its comment),
 * and [emptyCommentaryIsAbsorbedByTheCatchArmNotTheGuard] is the *subject* of the
 * expected-green row rather than a claimant for it — by construction it has none.
 *
 * What the "one inference" row does **not** establish: its assertion is
 * `callCount == 1`, which catches any multiplication of the call but does not by
 * itself prove agent-count *independence*. That claim rests on `callCount == 1`
 * **together with** the 3-agent pin, which is why the pin is asserted in the test
 * body rather than left implicit.
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
        // not a participant, so cost is agent-count-independent.
        //
        // Over-scripted on purpose (same reasoning as requestsCommentarySchema): with
        // a single script an extra call throws the harness's exhaustion
        // `IllegalStateException` before `assertEquals` runs, so the assertion below
        // could never be the detector and the red would carry no count. Serving the
        // extra call makes the failure message name the real one (`expected 1, got 2`).
        val s = scenario()
        val backend = ScriptedLLMBackend(List(LLMCaller.MAX_RETRIES + 1) { narrates("A tense round.") })

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
        //
        // Scripted with ONE response even though zero calls are expected, so that
        // `assertEquals(0, …)` below is what detects a disabled guard rather than the
        // harness's exhaustion throw. `emptyList()` would be the tighter expression of
        // "no call" but would make the written assertion structurally unreachable.
        val s = scenario()
        val backend = ScriptedLLMBackend(listOf(narrates("should not fire")))
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

        // Asserting the message, not just the type: `CancellationException` is an
        // `IllegalStateException` on JVM and so is `ScriptedLLMBackend`'s exhaustion
        // signal, so pinning the text keeps this from ever passing on a harness fault.
        val e = assertFailsWith<CancellationException> {
            handler.execute(context(s, NarrateCancellingBackend(), events), stateWithLog(s))
        }
        assertEquals("cancelled mid-narration", e.message)
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
    fun omitsTheDescriptorSectionWhenNarratorIsBlank() = runTest {
        // Pins the GATE on the descriptor section, not merely its rendering: a blank
        // descriptor must not emit an empty "Commentator persona:" heading with
        // nothing after it. Claimant for the `if (true)` perturbation — forcing the
        // gate open is what this catches, where forcing it CLOSED (`if (false)`) is
        // caught by injectsNarratorDescriptorIntoSystemPrompt. Both polarities are
        // measured; see the class KDoc.
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
    fun clampsMaxSentencesToTheUpperBoundToo() = runTest {
        // The floor alone would leave `coerceIn(1, 100)` green while the clamp's name
        // promises the validator's 1..6 range. Pins the ceiling.
        val s = scenario(maxSentences = 99)
        val backend = ScriptedLLMBackend(listOf(narrates("ok")))

        handler.execute(context(s, backend), stateWithLog(s))

        val system = backend.requests.single().system
        assertContains(system, "at most 6 sentence(s)")
        assertTrue("at most 99" !in system)
    }

    @Test
    fun usesTheHandlersOwnDefaultWhenMaxSentencesIsAbsent() = runTest {
        // Pins the value 3. It CANNOT discriminate WHICH constant that 3 came from
        // while PromptBuilder.DEFAULT_STATEMENT_MAX_SENTENCES is also 3 — refactoring
        // narrate to read the statement constant leaves this green. It becomes a
        // coupling detector for the handler's "narrate's OWN constant" rationale only
        // once the two values diverge.
        val s = scenario(maxSentences = null)
        val backend = ScriptedLLMBackend(listOf(narrates("ok")))

        handler.execute(context(s, backend), stateWithLog(s))

        assertContains(backend.requests.single().system, "at most 3 sentence(s)")
    }

    @Test
    fun requestsCommentarySchema() = runTest {
        // Engine-fixed single-field `{ commentary }` schema — not author-declared, so
        // the backend receives exactly that constraint regardless of the phase YAML.
        //
        // Scripted with the FULL retry budget, and reading `requests.first()` rather
        // than `.single()`, so that a renamed schema field is caught by the assertion
        // below rather than by the harness. With one script, renaming the field makes
        // the parser reject every response, the retry loop asks for a second script,
        // and `ScriptedLLMBackend` throws its exhaustion `IllegalStateException`
        // *before* this test ever reads the request — reddening for the same reason
        // as every unrelated test, which is not evidence about the schema.
        val s = scenario()
        val backend = ScriptedLLMBackend(List(LLMCaller.MAX_RETRIES + 1) { narrates("ok") })

        handler.execute(context(s, backend), stateWithLog(s))

        val schema = backend.requests.first().schema
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
