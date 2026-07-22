package com.pastura.engine

import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Pins the [PhaseHandler] contract — specifically the one place it structurally
 * diverges from Swift.
 *
 * Swift handlers take `state: inout SimulationState` and mutate in place. Kotlin
 * [SimulationState] is an immutable `data class`, so handlers return the next
 * state (the #1063 Stage-2-pre precedent). That swap is silent-failure-shaped: a
 * caller that ignores the return value compiles fine and drops every change. These
 * tests make the new contract executable before any real handler depends on it.
 *
 * Ported for the ADR-023 §6 Stage-2 gate slice (#501).
 */
class PhaseHandlerTests {

    private val scenario = makeTestScenario(agentNames = listOf("Alice", "Bob"))
    private val phase = Phase(type = PhaseType.SPEAK_ALL, prompt = "Speak.")

    private fun context(
        emitter: (SimulationEvent) -> Unit = {},
        pauseCheck: suspend (List<Int>) -> Unit = { },
    ) = PhaseContext(
        scenario = scenario,
        phase = phase,
        backend = ScriptedLLMBackend(emptyList()),
        suspensionRelay = SuspensionRelay(),
        emitter = emitter,
        pauseCheck = pauseCheck,
        phasePath = listOf(0),
        turnGate = TurnFailureGate(),
    )

    /**
     * A handler that bumps one score — the smallest observable state change.
     *
     * Bumps rather than inserts: `SimulationState.initial` already seeds every
     * agent at 0 (matching Swift), so "Alice" is present from the start and only
     * its *value* can witness a change.
     */
    private class ScoringHandler : PhaseHandler {
        override suspend fun execute(context: PhaseContext, state: SimulationState): SimulationState =
            state.copy(scores = state.scores + ("Alice" to 42))
    }

    // MARK: - Immutable-state contract

    @Test
    fun handlerReturnsNextStateAndLeavesTheInputUntouched() {
        runTest {
            val before = SimulationState.initial(scenario)
            val after = ScoringHandler().execute(context(), before)

            assertEquals(42, after.scores["Alice"])
            // The input is genuinely untouched — this is what makes "ignoring the
            // return value silently drops changes" true, and why the runner must
            // thread the result through every phase.
            assertEquals(0, before.scores["Alice"], "the handler must not mutate its input")
        }
    }

    @Test
    fun statesAreValueEqualSoRunnerThreadingIsObservable() {
        // The runner's loop reassigns `state` per phase. Value equality is what
        // lets a test assert that a phase actually advanced state rather than
        // returning its input.
        runTest {
            val before = SimulationState.initial(scenario)
            val unchanged = object : PhaseHandler {
                override suspend fun execute(context: PhaseContext, state: SimulationState) = state
            }.execute(context(), before)
            assertEquals(before, unchanged)

            val changed = ScoringHandler().execute(context(), before)
            assertFalse(before == changed)
        }
    }

    // MARK: - Context wiring

    @Test
    fun emitterReachesTheCaller() {
        runTest {
            val events = mutableListOf<SimulationEvent>()
            val ctx = context(emitter = { events += it })
            ctx.emitter(SimulationEvent.Summary(text = "hi"))
            assertEquals(1, events.size)
            assertEquals(SimulationEvent.Summary(text = "hi"), events.single())
        }
    }

    @Test
    fun pauseCheckCarriesThePhasePath() {
        // Sub-phase granularity: a nesting handler passes its inner path so the
        // runner can attribute the pause. Nothing in this slice nests, but the
        // contract is what Stage 3's ConditionalHandler consumes.
        runTest {
            val seen = mutableListOf<List<Int>>()
            val ctx = context(pauseCheck = { path -> seen += path })
            ctx.pauseCheck(listOf(1, 2))
            assertEquals(listOf(listOf(1, 2)), seen)
        }
    }

    @Test
    fun pauseCheckSignalsCancellationByThrowingNotByReturning() {
        // The Swift->Kotlin contract swap. Swift returns `Bool` ("cancelled while
        // paused — return early") because it polls `Task.isCancelled`. Kotlin
        // cancellation THROWS, so the handler unwinds on its own and a Bool would
        // be vestigial — worse, a handler could ignore it and keep running after
        // cancellation. Throwing makes that structurally impossible; this pins it.
        runTest {
            val ctx = context(pauseCheck = { throw CancellationException("cancelled while paused") })
            assertFailsWith<CancellationException> { ctx.pauseCheck(listOf(0)) }
        }
    }

    @Test
    fun suspensionRelayIsAPassThroughHandlersDoNotDrive() {
        // Pins the doc's contract: the relay on the context is for LLMCaller.
        // A handler must be able to forward it without arming or awaiting — this
        // asserts the shape is available for forwarding, nothing more.
        runTest {
            val relay = SuspensionRelay()
            val ctx = PhaseContext(
                scenario = scenario,
                phase = phase,
                backend = ScriptedLLMBackend(emptyList()),
                suspensionRelay = relay,
                emitter = {},
                pauseCheck = { },
                phasePath = listOf(0),
                turnGate = TurnFailureGate(),
            )
            assertTrue(ctx.suspensionRelay === relay)
        }
    }
}
