package com.pastura.engine

import com.pastura.models.OutputSchema
import com.pastura.models.SimulationError
import com.pastura.models.SimulationEvent
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Behaviour tests for the bounded [LLMCaller] core.
 *
 * The §5.2 invariants get the most attention here, because ADR-023 §10 records
 * that "the §5.2 invariants must be defended in review forever" — a test is a
 * cheaper defence than a reviewer's memory.
 *
 * Ported for the ADR-023 §6 Stage-2 gate slice (#501).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class LLMCallerTests {

    private val caller = LLMCaller()
    private val schema = OutputSchema(
        fields = listOf(OutputSchema.Field(name = "statement", kind = OutputSchema.Kind.StringKind)),
    )

    private suspend fun call(
        backend: LLMBackend,
        relay: SuspensionRelay = SuspensionRelay(),
        schema: OutputSchema? = this.schema,
        events: MutableList<SimulationEvent> = mutableListOf(),
    ) = caller.call(
        backend = backend,
        system = "sys",
        user = "usr",
        agentName = "Alice",
        schema = schema,
        relay = relay,
        emitter = { events += it },
    )

    private fun script(vararg chunks: String, tokens: Int? = null) =
        ScriptedLLMBackend.Script(chunks = chunks.toList(), completionTokens = tokens)

    // MARK: - Happy path

    @Test
    fun parsesAccumulatedChunksIntoATurnOutput() = runTest {
        val backend = ScriptedLLMBackend(listOf(script("""{"stat""", """ement": "hi"}""")))
        val out = call(backend)
        assertEquals("hi", out.fields["statement"])
        assertEquals(1, backend.callCount)
    }

    @Test
    fun schemaReachesTheBackendAsTheRequestSchema() = runTest {
        val backend = ScriptedLLMBackend(listOf(script("""{"statement": "hi"}""")))
        call(backend)
        assertEquals(schema, backend.requests.single().schema)
        assertEquals("sys", backend.requests.single().system)
        assertEquals("usr", backend.requests.single().user)
    }

    // MARK: - Retry budget (parse / empty)

    @Test
    fun parseFailureRetriesUpToTheBudgetThenSucceeds() = runTest {
        val backend = ScriptedLLMBackend(
            listOf(script("garbage"), script("still garbage"), script("""{"statement": "ok"}""")),
        )
        assertEquals("ok", call(backend).fields["statement"])
        assertEquals(3, backend.callCount, "0..MAX_RETRIES inclusive = 3 attempts")
    }

    @Test
    fun parseFailureThrowsRetriesExhaustedAfterTheBudget() = runTest {
        val backend = ScriptedLLMBackend(List(3) { script("garbage") })
        val error = assertFailsWith<SimulationException> { call(backend) }
        assertIs<SimulationError.RetriesExhausted>(error.error)
        assertEquals(3, backend.callCount)
    }

    @Test
    fun emptyFieldTriggersARetry() = runTest {
        val backend = ScriptedLLMBackend(
            listOf(script("""{"statement": ""}"""), script("""{"statement": "real"}""")),
        )
        // The empty-field retry only fires when the parser guard does not reject
        // first, so this call goes schema-less.
        assertEquals("real", call(backend, schema = null).fields["statement"])
        assertEquals(2, backend.callCount)
    }

    @Test
    fun ellipsisCountsAsAnEmptyField() = runTest {
        val backend = ScriptedLLMBackend(
            listOf(script("""{"statement": "..."}"""), script("""{"statement": "real"}""")),
        )
        assertEquals("real", call(backend, schema = null).fields["statement"])
    }

    @Test
    fun anEmptyFieldOnTheLastAttemptIsRETURNEDNotThrown() = runTest {
        // The asymmetry with parse failure, and it is deliberate on both sides:
        // Swift's guard is `hasEmptyFields(output) && attempt < maxRetries`, so a
        // parseable-but-thin answer still lets the simulation continue. A port that
        // threw here would abort runs Swift completes.
        val backend = ScriptedLLMBackend(List(3) { script("""{"statement": ""}""") })
        val out = call(backend, schema = null)
        assertEquals("", out.fields["statement"])
        assertEquals(3, backend.callCount)
    }

    // MARK: - §5.2 invariant 1 — suspend re-issues stay OFF the retry budget

    @Test
    fun suspendThenSucceedPreservesTheFullRetryBudget() = runTest {
        // The named ADR-023 §5.2 invariant-1 assertion. Five suspend cycles, then
        // two parse failures, then success: if suspends consumed the budget, the
        // parse failures would exhaust it and this would throw.
        val relay = SuspensionRelay()
        val scripts = buildList {
            repeat(5) { add(ScriptedLLMBackend.Script(terminal = TerminalStatus.Suspended)) }
            add(script("garbage"))
            add(script("garbage"))
            add(script("""{"statement": "survived"}"""))
        }
        val backend = ScriptedLLMBackend(scripts)

        val job = launch { assertEquals("survived", call(backend, relay).fields["statement"]) }
        // Each cycle: the caller arms, the backend suspends, the caller parks.
        repeat(5) {
            advanceUntilIdle()
            relay.notifyResumed()
        }
        advanceUntilIdle()
        job.join()
        assertEquals(8, backend.callCount, "5 suspend re-issues + 3 budgeted attempts")
    }

    @Test
    fun suspendAloneNeverExhaustsTheBudget() = runTest {
        // Ten suspends and a single success: more cycles than the budget could
        // absorb if they counted against it.
        val relay = SuspensionRelay()
        val backend = ScriptedLLMBackend(
            buildList {
                repeat(10) { add(ScriptedLLMBackend.Script(terminal = TerminalStatus.Suspended)) }
                add(script("""{"statement": "ok"}"""))
            },
        )
        val job = launch { assertEquals("ok", call(backend, relay).fields["statement"]) }
        repeat(10) {
            advanceUntilIdle()
            relay.notifyResumed()
        }
        advanceUntilIdle()
        job.join()
        assertEquals(11, backend.callCount)
    }

    @Test
    fun resumeRacingTheSuspendObservationDoesNotHang() = runTest {
        // §5.2 invariant 3, end-to-end. The window: the relay is ARMED and the
        // stream has suspended, but the caller has not yet reached awaitResume.
        // A resume landing here must be latched, not dropped.
        //
        // ManualLLMBackend is required to build this. With a synchronous backend
        // there is no scheduler turn between arm() and awaitResume(), so the window
        // cannot be opened from a test at all.
        //
        // If LLMCaller armed inside awaitResume instead of before the stream, the
        // resume below would land with nothing armed, be dropped, and this would
        // deadlock — which is precisely the bug the arm-first design prevents.
        val relay = SuspensionRelay()
        val backend = ManualLLMBackend()
        var done = false
        val job = launch {
            call(backend, relay)
            done = true
        }
        advanceUntilIdle() // armed, stream issued, parked on the stream

        // Back-to-back with no scheduler turn between: the caller is still inside
        // the terminal callback and has not reached awaitResume.
        backend.latest!!.callbacks.onTerminal(TerminalStatus.Suspended)
        relay.notifyResumed()

        advanceUntilIdle()
        assertFalse(done, "still mid-call — the re-issued stream has not completed yet")
        assertEquals(2, backend.calls.size, "the caller must have re-issued, not parked forever")

        backend.latest!!.callbacks.onChunk("""{"statement": "ok"}""", isFinal = true, completionTokens = null)
        backend.latest!!.callbacks.onTerminal(TerminalStatus.Completed)
        advanceUntilIdle()
        assertTrue(done, "a resume racing the suspend observation must not hang the caller")
        job.join()
    }

    // MARK: - Backend failure

    @Test
    fun failedTerminalThrowsLlmGenerationFailedWithTheCode() = runTest {
        val backend = ScriptedLLMBackend(
            listOf(
                ScriptedLLMBackend.Script(
                    terminal = TerminalStatus.Failed(errorCode = "metal_oom", message = "no GPU"),
                ),
            ),
        )
        val error = assertFailsWith<SimulationException> { call(backend) }
        val failed = assertIs<SimulationError.LlmGenerationFailed>(error.error)
        assertTrue(failed.description.contains("metal_oom"))
        assertTrue(failed.description.contains("no GPU"))
    }

    @Test
    fun failedTerminalDoesNotConsumeTheRetryBudget() = runTest {
        // A backend failure aborts rather than retrying — the Stage-3 StreamFailure
        // taxonomy is what will eventually decide which failures are retryable.
        val backend = ScriptedLLMBackend(
            listOf(
                ScriptedLLMBackend.Script(terminal = TerminalStatus.Failed(errorCode = "x")),
                script("""{"statement": "never reached"}"""),
            ),
        )
        assertFailsWith<SimulationException> { call(backend) }
        assertEquals(1, backend.callCount)
    }

    @Test
    fun failedTerminalWithoutAMessageUsesTheBareCode() = runTest {
        val backend = ScriptedLLMBackend(
            listOf(ScriptedLLMBackend.Script(terminal = TerminalStatus.Failed(errorCode = "unknown"))),
        )
        val error = assertFailsWith<SimulationException> { call(backend) }
        assertEquals("unknown", assertIs<SimulationError.LlmGenerationFailed>(error.error).description)
    }

    // MARK: - §5.2 cancellation composition

    @Test
    fun coroutineCancellationReachesTheStreamHandle() = runTest {
        // THE §5.2 contract clause. Without invokeOnCancellation, RunHandle.cancel()
        // would kill the Kotlin Job and leave the Swift stream — and its
        // llama_decode loop — running.
        val backend = ManualLLMBackend()
        val job = launch { call(backend) }
        advanceUntilIdle()

        assertEquals(1, backend.calls.size, "the stream must be in flight")
        assertFalse(backend.latest!!.cancelled)

        job.cancel()
        advanceUntilIdle()
        assertTrue(backend.latest!!.cancelled, "cancellation must reach StreamHandle.cancel()")
    }

    @Test
    fun cancellationWhileParkedOnASuspendUnwindsCleanlyWithNothingLeftRunning() = runTest {
        // Renamed from "...AlsoCancelsTheStream", which named an invariant that is
        // structurally FALSE: the suspended stream already delivered its terminal,
        // so its continuation resumed and `invokeOnCancellation` can never fire for
        // that handle. The correct semantics is that there is nothing left to
        // cancel — per LLMBackend clauses 1-2 the stream ended at its terminal.
        val relay = SuspensionRelay()
        val backend = ManualLLMBackend()
        val job = launch { call(backend, relay) }
        advanceUntilIdle()

        backend.latest!!.callbacks.onTerminal(TerminalStatus.Suspended)
        advanceUntilIdle()

        job.cancel()
        advanceUntilIdle()
        job.join()
        assertTrue(job.isCancelled)
        assertFalse(
            backend.latest!!.cancelled,
            "the suspended stream already terminated — there is nothing to cancel",
        )
        assertEquals(1, backend.calls.size, "and no doomed re-issue was started")
    }

    @Test
    fun aCancelledParkWithAnAlreadyLatchedResumeDoesNotIssueADoomedStream() = runTest {
        // Swift has `try Task.checkCancellation()` right after `awaitResume()`.
        // Without the matching `ensureActive()`, `Deferred.await()` on an ALREADY
        // completed deferred returns without suspending — so it never observes
        // cancellation, and the loop would `continue`, re-arm, and kick off a real
        // llama_decode before the cancellation was noticed. Delete the
        // `coroutineContext.ensureActive()` and this fires.
        val relay = SuspensionRelay()
        val backend = ManualLLMBackend()
        val job = launch { call(backend, relay) }
        advanceUntilIdle()

        backend.latest!!.callbacks.onTerminal(TerminalStatus.Suspended)
        relay.notifyResumed() // latches BEFORE the caller reaches awaitResume
        job.cancel()
        advanceUntilIdle()

        assertEquals(1, backend.calls.size, "a cancelled run must not issue a second stream")
    }

    @Test
    fun aDuplicateTerminalAfterCancellationIsIgnoredNotACrash() = runTest {
        // Non-vacuous version. The FIRST post-cancel resume is already a silent
        // no-op in kotlinx (`CancelledContinuation -> if (state.makeResumed())
        // return`), so a single terminal proves nothing — the guard exists for the
        // DUPLICATE, which would otherwise hit `alreadyResumedError`. Both are
        // legal inputs, because clause 3 makes cancel() best-effort.
        val backend = ManualLLMBackend()
        val job = launch { call(backend) }
        advanceUntilIdle()
        job.cancel()
        advanceUntilIdle()

        backend.latest!!.callbacks.onTerminal(TerminalStatus.Completed)
        backend.latest!!.callbacks.onTerminal(TerminalStatus.Completed)
        advanceUntilIdle()
        assertTrue(job.isCancelled)
    }

    @Test
    fun aNonFinalChunksTokenCountIsIgnored() = runTest {
        // Pins the `if (isFinal)` guard, which ScriptedLLMBackend structurally
        // cannot exercise (it welds isFinal onto the last chunk). Deleting the
        // guard would otherwise pass every test in this file.
        val events = mutableListOf<SimulationEvent>()
        val backend = ManualLLMBackend()
        val job = launch { call(backend, events = events) }
        advanceUntilIdle()

        val cb = backend.latest!!.callbacks
        cb.onChunk(delta = "{\"statement\":", isFinal = false, completionTokens = 7)
        cb.onChunk(delta = " \"hi\"}", isFinal = true, completionTokens = null)
        cb.onTerminal(TerminalStatus.Completed)
        advanceUntilIdle()
        job.join()

        assertNull(
            events.filterIsInstance<SimulationEvent.InferenceCompleted>().single().tokenCount,
            "only the FINAL chunk's count counts — a non-final 7 must not leak through",
        )
    }

    @Test
    fun anEmptyFinalDeltaStillCarriesItsTokenCount() = runTest {
        // The llama.cpp shape: many non-final chunks, then a final chunk carrying
        // ONLY the token count with an empty delta (LLMCaller.swift:298-302).
        // ScriptedLLMBackend can only express the wrap shape, so this — the
        // production path — was untested.
        val events = mutableListOf<SimulationEvent>()
        val backend = ManualLLMBackend()
        val job = launch { call(backend, events = events) }
        advanceUntilIdle()

        val cb = backend.latest!!.callbacks
        cb.onChunk(delta = "{\"statement\": \"hi\"}", isFinal = false, completionTokens = null)
        cb.onChunk(delta = "", isFinal = true, completionTokens = 12)
        cb.onTerminal(TerminalStatus.Completed)
        advanceUntilIdle()
        job.join()

        assertEquals(12, events.filterIsInstance<SimulationEvent.InferenceCompleted>().single().tokenCount)
        assertEquals(
            1,
            events.filterIsInstance<SimulationEvent.AgentOutputStream>().size,
            "the empty final delta emits no snapshot",
        )
    }

    // MARK: - Events

    @Test
    fun emitsInferenceStartedAndCompletedPerAttempt() = runTest {
        val events = mutableListOf<SimulationEvent>()
        val backend = ScriptedLLMBackend(listOf(script("garbage"), script("""{"statement": "ok"}""")))
        call(backend, events = events)

        assertEquals(2, events.filterIsInstance<SimulationEvent.InferenceStarted>().size)
        assertEquals(2, events.filterIsInstance<SimulationEvent.InferenceCompleted>().size)
    }

    @Test
    fun completionTokensRideTheFinalChunk() = runTest {
        val events = mutableListOf<SimulationEvent>()
        call(ScriptedLLMBackend(listOf(script("""{"statement": "ok"}""", tokens = 12))), events = events)
        assertEquals(12, events.filterIsInstance<SimulationEvent.InferenceCompleted>().single().tokenCount)
    }

    @Test
    fun tokensAreNullWhenTheBackendFails() = runTest {
        // Unknown, NOT zero — a consumer that averaged 0 would poison tok/s.
        val events = mutableListOf<SimulationEvent>()
        val backend = ScriptedLLMBackend(
            listOf(ScriptedLLMBackend.Script(terminal = TerminalStatus.Failed(errorCode = "x"))),
        )
        assertFailsWith<SimulationException> { call(backend, events = events) }
        assertNull(events.filterIsInstance<SimulationEvent.InferenceCompleted>().single().tokenCount)
    }

    @Test
    fun emitsOneSnapshotPerNonEmptyChunkCarryingRawAccumulatedText() = runTest {
        // The highest-frequency Kotlin->Swift crossing, and what §6 measurement
        // (i)/(ii) actually measure. `primary` is RAW accumulated text — the
        // primary/thought split needs PartialOutputExtractor (Stage 3).
        val events = mutableListOf<SimulationEvent>()
        call(ScriptedLLMBackend(listOf(script("""{"stat""", """ement":""", """ "hi"}"""))), events = events)

        val snaps = events.filterIsInstance<SimulationEvent.AgentOutputStream>()
        assertEquals(3, snaps.size)
        assertEquals("""{"stat""", snaps[0].primary)
        assertEquals("""{"statement":""", snaps[1].primary)
        assertEquals("""{"statement": "hi"}""", snaps[2].primary)
        assertTrue(snaps.all { it.thought == null }, "no extractor in this slice — thought must be honestly null")
        assertTrue(snaps.all { it.agent == "Alice" })
    }

    @Test
    fun emptyDeltasEmitNoSnapshot() = runTest {
        val events = mutableListOf<SimulationEvent>()
        call(ScriptedLLMBackend(listOf(script("", """{"statement": "hi"}""", ""))), events = events)
        assertEquals(1, events.filterIsInstance<SimulationEvent.AgentOutputStream>().size)
    }
}
