package com.pastura.engine

import com.pastura.models.Persona
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import com.pastura.models.SimulationError
import com.pastura.models.SimulationEvent
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertTrue

/**
 * End-to-end tests for the §5.1 entry point — the gate slice's assembled artifact,
 * with BOTH boundary contracts wired together.
 *
 * ## Why these use real threads, not `runTest`
 *
 * Every other suite here drives coroutines through `runTest`'s virtual scheduler.
 * These cannot: [SimulationEngine.run] deliberately owns its own
 * `CoroutineScope(Dispatchers.Default)` — that is the §5.1 threading clause
 * ("`onEvent` fires from a Kotlin worker context; the adapter must not assume
 * MainActor"). A test that injected a scheduler would be testing a different
 * engine than the one PR-C links. So these poll real events with a real timeout,
 * which also exercises the clause itself.
 *
 * Ported for the ADR-023 §6 Stage-2 gate slice (#501).
 */
class SimulationEngineTests {

    private fun scenario(
        agents: List<String> = listOf("Alice", "Bob"),
        rounds: Int = 1,
        phases: Int = 1,
    ) = Scenario(
        id = "t",
        name = "T",
        description = "d",
        language = "en",
        agentCount = agents.size,
        rounds = rounds,
        context = "A test.",
        personas = agents.map { Persona(name = it, description = "$it's persona.") },
        phases = List(phases) {
            Phase(type = PhaseType.SPEAK_ALL, prompt = "Speak.", outputSchema = mapOf("statement" to "string"))
        },
    )

    private fun says(text: String) =
        ScriptedLLMBackend.Script.completing("""{"statement": "$text"}""")

    /**
     * Finish call [index] on a [ManualLLMBackend].
     *
     * Every pause/cancel test below drives the run through a ManualLLMBackend
     * rather than a scripted one, because those tests need the run to be provably
     * **mid-flight** when the handle is used — and a scripted backend completes
     * synchronously, so the whole run can finish before the test's next line.
     *
     * That is not hypothetical: written against ScriptedLLMBackend, these tests
     * passed on JVM and FAILED on macosArm64, where the run outpaced the poll and
     * reached SimulationCompleted before cancel() landed. The K/N rung caught a
     * race the JVM rung hid — which is the concrete case for ADR-023 Decision 5's
     * "JVM parity alone does not witness the K/N memory model iOS will run".
     */
    private fun ManualLLMBackend.finish(index: Int, text: String) {
        calls[index].callbacks.onChunk(
            delta = """{"statement": "$text"}""",
            isFinal = true,
            completionTokens = null,
        )
        calls[index].callbacks.onTerminal(TerminalStatus.Completed)
    }

    // MARK: - Emit order (Stage-4 compares transcripts, so ORDER is contract)

    @Test
    fun aCompleteRunEmitsSwiftsEventOrder() = runBlockingTest {
        val s = scenario()
        val c = Collector()
        SimulationEngine().run(s, ScriptedLLMBackend(listOf(says("a"), says("b")))) { c.record(it) }
        awaitTerminal(c)

        val kinds = c.snapshot().map { it::class.simpleName }
        assertEquals(
            listOf(
                "RoundStarted",
                "PhaseStarted",
                "InferenceStarted", "AgentOutputStream", "InferenceCompleted", "AgentOutput",
                "InferenceStarted", "AgentOutputStream", "InferenceCompleted", "AgentOutput",
                "PhaseCompleted",
                "RoundCompleted",
                "RoundCheckpoint",
                "SimulationCompleted",
            ),
            kinds,
        )
    }

    @Test
    fun roundCheckpointFollowsRoundCompletedAndCarriesTheCompletedRound() = runBlockingTest {
        // The resume contract: `state.currentRound` is the LAST COMPLETED round, so
        // the App layer resumes from +1. Emitted only after the round fully
        // completes — a checkpoint before PhaseCompleted would resume past unrun work.
        val s = scenario(rounds = 2)
        val c = Collector()
        SimulationEngine().run(
            s,
            ScriptedLLMBackend(listOf(says("a"), says("b"), says("c"), says("d"))),
        ) { c.record(it) }
        awaitTerminal(c)

        val checkpoints = c.snapshot().filterIsInstance<SimulationEvent.RoundCheckpoint>()
        assertEquals(listOf(1, 2), checkpoints.map { it.state.currentRound })

        val order = c.snapshot()
        val firstCheckpoint = order.indexOfFirst { it is SimulationEvent.RoundCheckpoint }
        assertIs<SimulationEvent.RoundCompleted>(order[firstCheckpoint - 1])
    }

    @Test
    fun theCheckpointPayloadCarriesTheRoundsAccumulatedState() = runBlockingTest {
        // Why roundCheckpoint is IN this slice: it is the fattest payload the §5.1
        // boundary relays (§6 measurement (iii)). A checkpoint carrying an empty
        // state would measure nothing.
        val s = scenario()
        val c = Collector()
        SimulationEngine().run(s, ScriptedLLMBackend(listOf(says("a"), says("b")))) { c.record(it) }
        awaitTerminal(c)

        val state = c.snapshot().filterIsInstance<SimulationEvent.RoundCheckpoint>().single().state
        assertEquals(2, state.conversationLog.size)
        assertEquals(2, state.lastOutputs.size)
        assertEquals("a", state.lastOutputs["Alice"]?.fields?.get("statement"))
    }

    @Test
    fun eachRoundClearsTheConversationLogButKeepsScores() = runBlockingTest {
        val s = scenario(rounds = 2)
        val c = Collector()
        SimulationEngine().run(
            s,
            ScriptedLLMBackend(listOf(says("r1a"), says("r1b"), says("r2a"), says("r2b"))),
        ) { c.record(it) }
        awaitTerminal(c)

        val checkpoints = c.snapshot().filterIsInstance<SimulationEvent.RoundCheckpoint>()
        assertEquals(listOf("r1a", "r1b"), checkpoints[0].state.conversationLog.map { it.content })
        assertEquals(listOf("r2a", "r2b"), checkpoints[1].state.conversationLog.map { it.content })
    }

    @Test
    fun currentRoundIsInjectedAsATemplateVariable() = runBlockingTest {
        val s = scenario(rounds = 2)
        val c = Collector()
        SimulationEngine().run(
            s,
            ScriptedLLMBackend(listOf(says("a"), says("b"), says("c"), says("d"))),
        ) { c.record(it) }
        awaitTerminal(c)

        val checkpoints = c.snapshot().filterIsInstance<SimulationEvent.RoundCheckpoint>()
        assertEquals("2", checkpoints[1].state.variables["current_round"])
    }

    // MARK: - Early termination

    @Test
    fun fewerThanTwoActiveAgentsEndsTheRunEarlyWithASummary() = runBlockingTest {
        val s = scenario(agents = listOf("Alice"))
        val c = Collector()
        SimulationEngine().run(s, ScriptedLLMBackend(emptyList())) { c.record(it) }
        awaitTerminal(c)

        val kinds = c.snapshot().map { it::class.simpleName }
        assertEquals(listOf("Summary", "SimulationCompleted"), kinds)
        assertTrue(
            c.snapshot().filterIsInstance<SimulationEvent.Summary>().single().text.contains("fewer than 2"),
        )
    }

    // MARK: - Error propagation

    @Test
    fun aPhaseErrorEndsTheRunWithAnErrorEvent() = runBlockingTest {
        val s = scenario()
        val c = Collector()
        SimulationEngine().run(
            s,
            ScriptedLLMBackend(listOf(ScriptedLLMBackend.Script(terminal = TerminalStatus.Failed(errorCode = "boom")))),
        ) { c.record(it) }
        awaitTerminal(c)

        val error = c.snapshot().last()
        assertIs<SimulationError.LlmGenerationFailed>(assertIs<SimulationEvent.ErrorEvent>(error).error)
        // No SimulationCompleted after an error — the run stops.
        assertFalse(c.snapshot().any { it is SimulationEvent.SimulationCompleted })
    }

    // `anUnportedPhaseTypeSurfacesAsAValidationError` lived here, using CONDITIONAL
    // as the last-to-be-ported exemplar. Wave B completed at 14/14 (#1342), so no
    // PhaseType is unported and the case had no subject left. Not repointed: the
    // dispatcher's throw is unreachable through the public API, and it is covered at
    // the unit level via the seam (`PhaseDispatcherTests`). Its engine-level claim —
    // that a phase error ends the run with an ErrorEvent rather than a crash — is
    // already carried by `aPhaseErrorEndsTheRunWithAnErrorEvent` above, since the
    // dispatch call sits inside the same `try` as handler execution.

    // MARK: - §5.1 pause / resume

    /**
     * Drive a 2-round run to the round-2 pause checkpoint with the gate set.
     *
     * Deterministic by construction: the run parks on each inference until this
     * finishes it, so "paused at a checkpoint" is reached by driving, never by
     * out-racing the engine.
     */
    private suspend fun pausedAtRoundTwo(backend: ManualLLMBackend, c: Collector, handle: RunHandle) {
        await { backend.calls.size == 1 }
        handle.pause() // takes effect at the NEXT checkpoint, i.e. round 2's
        backend.finish(0, "a")
        await { backend.calls.size == 2 }
        backend.finish(1, "b")
        await { c.snapshot().any { it is SimulationEvent.SimulationPaused } }
    }

    @Test
    fun pauseHaltsAtACheckpointAndResumeContinues() = runBlockingTest {
        val s = scenario(rounds = 2)
        val backend = ManualLLMBackend()
        val c = Collector()
        val handle = SimulationEngine().run(s, backend) { c.record(it) }
        pausedAtRoundTwo(backend, c, handle)

        val atPause = c.snapshot().size
        kotlinx.coroutines.delay(30)
        assertEquals(atPause, c.snapshot().size, "a paused run must emit nothing — zero CPU, no polling")
        assertEquals(2, backend.calls.size, "and must not start round 2's inference")

        handle.resume()
        await { backend.calls.size == 3 }
        backend.finish(2, "c")
        await { backend.calls.size == 4 }
        backend.finish(3, "d")
        awaitTerminal(c)
        assertIs<SimulationEvent.SimulationCompleted>(c.snapshot().last())
    }

    @Test
    fun simulationPausedIsEmittedOncePerPauseCycle() = runBlockingTest {
        // The runner is the SOLE emitter of SimulationPaused; a handler must never
        // emit it. One pause => exactly one event, no matter how many checkpoints
        // the loop would cross while parked.
        val s = scenario(rounds = 2)
        val backend = ManualLLMBackend()
        val c = Collector()
        val handle = SimulationEngine().run(s, backend) { c.record(it) }
        pausedAtRoundTwo(backend, c, handle)

        kotlinx.coroutines.delay(30)
        handle.resume()
        await { backend.calls.size == 3 }
        backend.finish(2, "c")
        await { backend.calls.size == 4 }
        backend.finish(3, "d")
        awaitTerminal(c)

        assertEquals(1, c.snapshot().count { it is SimulationEvent.SimulationPaused })
    }

    @Test
    fun pauseAndResumeAreIdempotent() = runBlockingTest {
        val s = scenario()
        val c = Collector()
        val handle = SimulationEngine().run(s, ScriptedLLMBackend(listOf(says("a"), says("b")))) { c.record(it) }

        // The adapter's lifecycle callbacks can fire repeatedly.
        handle.resume()
        handle.resume()
        awaitTerminal(c)
        assertIs<SimulationEvent.SimulationCompleted>(c.snapshot().last())
    }

    // MARK: - §5.1 cancel

    @Test
    fun cancelEndsTheRunWithCancelled() = runBlockingTest {
        val s = scenario(rounds = 5)
        val backend = ManualLLMBackend()
        val c = Collector()
        val handle = SimulationEngine().run(s, backend) { c.record(it) }

        await { backend.calls.isNotEmpty() } // provably mid-run: parked on inference 1
        handle.cancel()
        awaitTerminal(c)

        val error = assertIs<SimulationEvent.ErrorEvent>(c.snapshot().last())
        assertIs<SimulationError.Cancelled>(error.error)
        assertFalse(c.snapshot().any { it is SimulationEvent.SimulationCompleted })
    }

    @Test
    fun cancelWhilePausedDoesNotDeadlock() = runBlockingTest {
        // THE reason RunHandleImpl.cancel() releases the gate before cancelling the
        // Job: a run parked on the pause gate would otherwise observe cancellation
        // only when something resumed it — and nothing would. Without the release
        // this test hangs to its timeout.
        val s = scenario(rounds = 2)
        val backend = ManualLLMBackend()
        val c = Collector()
        val handle = SimulationEngine().run(s, backend) { c.record(it) }
        pausedAtRoundTwo(backend, c, handle) // provably parked ON THE GATE

        handle.cancel()
        awaitTerminal(c)
        assertIs<SimulationError.Cancelled>(assertIs<SimulationEvent.ErrorEvent>(c.snapshot().last()).error)
    }

    @Test
    fun cancelIsIdempotent() = runBlockingTest {
        val s = scenario(rounds = 5)
        val backend = ManualLLMBackend()
        val c = Collector()
        val handle = SimulationEngine().run(s, backend) { c.record(it) }

        await { backend.calls.isNotEmpty() }
        handle.cancel()
        handle.cancel()
        awaitTerminal(c)
        assertEquals(1, c.snapshot().count { it is SimulationEvent.ErrorEvent })
    }

    // MARK: - §5.2 wired through the runner (both boundaries together)

    @Test
    fun notifyLLMResumedDrivesASuspendedInferenceToCompletion() = runBlockingTest {
        // BOTH boundaries in one path — the gate artifact's whole point. The backend
        // suspends (§5.2), the platform signals resume through RunHandle (§5.1), and
        // the run completes.
        val s = scenario()
        val c = Collector()
        val backend = ScriptedLLMBackend(
            listOf(
                ScriptedLLMBackend.Script(terminal = TerminalStatus.Suspended),
                says("a"),
                says("b"),
            ),
        )
        val handle = SimulationEngine().run(s, backend) { c.record(it) }

        await { backend.callCount >= 1 }
        // The run is parked on the relay; nothing completes until the platform says so.
        kotlinx.coroutines.delay(30)
        assertFalse(c.isTerminal, "a suspended inference must park, not fail")

        handle.notifyLLMResumed()
        awaitTerminal(c)

        assertIs<SimulationEvent.SimulationCompleted>(c.snapshot().last())
        assertEquals(3, backend.callCount, "1 suspended + 2 agents — the suspend re-issue is off the budget")
    }

    @Test
    fun cancelReachesAnInFlightStreamHandle() = runBlockingTest {
        // §5.2 cancellation composition, end-to-end through RunHandle: without it,
        // cancel() would kill the Kotlin Job and leave the Swift stream — and its
        // llama_decode loop — running.
        val s = scenario()
        val backend = ManualLLMBackend()
        val c = Collector()
        val handle = SimulationEngine().run(s, backend) { c.record(it) }

        await { backend.calls.isNotEmpty() }
        assertFalse(backend.latest!!.cancelled)

        handle.cancel()
        await { backend.latest!!.cancelled }
        assertTrue(backend.latest!!.cancelled, "RunHandle.cancel() must compose down to StreamHandle.cancel()")
    }
}
