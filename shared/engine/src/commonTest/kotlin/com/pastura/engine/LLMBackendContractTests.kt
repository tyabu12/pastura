package com.pastura.engine

import com.pastura.models.OutputSchema
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Pins the ADR-023 §5.2 inference-boundary contract against the commonTest
 * doubles.
 *
 * **What these tests are for.** The contract clauses in
 * [LLMBackend.generateStream]'s kdoc are prose that `LLMCaller` (and, at PR-C,
 * a Swift adapter) rely on. Prose is not enforcement — these tests make the
 * clauses executable, and make [ScriptedLLMBackend] / [ManualLLMBackend]
 * trustworthy as the spec-enforcement tools items 5-7 build on.
 *
 * Ported for the ADR-023 §6 Stage-2 gate slice (#501).
 */
class LLMBackendContractTests {

    private fun request(system: String = "sys", user: String = "usr") =
        GenerationRequest(system = system, user = user)

    // MARK: - Clause 1/2: chunks, then exactly one terminal

    @Test
    fun completingCallDeliversChunksThenExactlyOneTerminal() {
        val backend = ScriptedLLMBackend(
            listOf(ScriptedLLMBackend.Script(chunks = listOf("{\"a\":", "1}"))),
        )
        val cb = RecordingStreamCallbacks()
        backend.generateStream(request(), cb)

        assertEquals(2, cb.chunks.size)
        assertEquals("{\"a\":1}", cb.accumulated)
        assertEquals(1, cb.terminals.size)
        // Ordering: the terminal is last, never interleaved.
        assertIs<RecordingStreamCallbacks.Event.Terminal>(cb.events.last())
        assertEquals(TerminalStatus.Completed, cb.terminals.single().status)
    }

    @Test
    fun exactlyOneChunkIsFinalAndItIsTheLast() {
        val backend = ScriptedLLMBackend(
            listOf(ScriptedLLMBackend.Script(chunks = listOf("a", "b", "c"), completionTokens = 7)),
        )
        val cb = RecordingStreamCallbacks()
        backend.generateStream(request(), cb)

        assertEquals(1, cb.chunks.count { it.isFinal })
        assertTrue(cb.chunks.last().isFinal)
        // completionTokens rides the final chunk only — the Swift contract.
        assertEquals(7, cb.chunks.last().completionTokens)
        assertTrue(cb.chunks.dropLast(1).all { it.completionTokens == null })
    }

    @Test
    fun completionTokensMayBeNullMeaningUnknownThroughput() {
        // `null` is "backend cannot report cheaply", NOT zero. A consumer that
        // coerced it to 0 would poison rolling tok/s averages.
        val backend = ScriptedLLMBackend(listOf(ScriptedLLMBackend.Script.completing("x")))
        val cb = RecordingStreamCallbacks()
        backend.generateStream(request(), cb)
        assertNull(cb.chunks.single().completionTokens)
    }

    // MARK: - Terminal statuses

    @Test
    fun suspendedStreamHasNoFinalChunk() {
        // Mirrors Swift: `LLMError.suspended` throws out of the
        // AsyncThrowingStream, so the stream is CUT OFF — it does not arrive as
        // a well-formed final chunk. A port that marked the last pre-suspend
        // chunk `isFinal` would let a consumer treat a partial generation as
        // complete.
        val backend = ScriptedLLMBackend(
            listOf(
                ScriptedLLMBackend.Script(
                    chunks = listOf("partial"),
                    terminal = TerminalStatus.Suspended,
                ),
            ),
        )
        val cb = RecordingStreamCallbacks()
        backend.generateStream(request(), cb)

        assertTrue(cb.chunks.none { it.isFinal })
        assertEquals(TerminalStatus.Suspended, cb.terminals.single().status)
    }

    @Test
    fun failedStreamCarriesCodeAndOptionalMessage() {
        val backend = ScriptedLLMBackend(
            listOf(
                ScriptedLLMBackend.Script(
                    terminal = TerminalStatus.Failed(errorCode = "metal_oom", message = "no GPU"),
                ),
            ),
        )
        val cb = RecordingStreamCallbacks()
        backend.generateStream(request(), cb)

        val failed = assertIs<TerminalStatus.Failed>(cb.terminals.single().status)
        assertEquals("metal_oom", failed.errorCode)
        assertEquals("no GPU", failed.message)
        assertTrue(cb.chunks.none { it.isFinal })
    }

    @Test
    fun failedMessageIsOptional() {
        assertNull(TerminalStatus.Failed(errorCode = "unknown").message)
    }

    @Test
    fun suspendedAndCompletedAreSingletonsNotValueEqualByAccident() {
        // Sealed `object`s: identity equality is what the relay branches on.
        assertEquals(TerminalStatus.Completed, TerminalStatus.Completed)
        assertFalse(TerminalStatus.Completed == TerminalStatus.Suspended)
    }

    // MARK: - GenerationRequest shape

    @Test
    fun schemaDefaultsToNullMeaningUnconstrainedGeneration() {
        assertNull(request().schema)
    }

    @Test
    fun requestCarriesSchemaThrough() {
        val schema = OutputSchema(
            fields = listOf(OutputSchema.Field(name = "statement", kind = OutputSchema.Kind.StringKind)),
        )
        val backend = ScriptedLLMBackend(listOf(ScriptedLLMBackend.Script.completing("{}")))
        backend.generateStream(
            GenerationRequest(system = "s", user = "u", schema = schema),
            RecordingStreamCallbacks(),
        )
        assertEquals(schema, backend.requests.single().schema)
    }

    // MARK: - StreamHandle

    @Test
    fun cancelIsIdempotentAndSafeAfterTermination() {
        // The common real case: a cancelled coroutine whose stream had already
        // completed. `LLMCaller` wires cancel() through invokeOnCancellation and
        // cannot know whether the stream ended first, so cancel() must never
        // throw.
        val backend = ScriptedLLMBackend(listOf(ScriptedLLMBackend.Script.completing("x")))
        val handle = backend.generateStream(request(), RecordingStreamCallbacks())
        handle.cancel()
        handle.cancel()
        assertEquals(2, backend.cancelCount)
    }

    @Test
    fun manualBackendExposesInFlightCallWithoutTerminating() {
        // The property that makes cancellation composition testable at all.
        val backend = ManualLLMBackend()
        val cb = RecordingStreamCallbacks()
        val handle = backend.generateStream(request(user = "u1"), cb)

        assertEquals(1, backend.calls.size)
        assertEquals("u1", backend.latest?.request?.user)
        assertTrue(cb.events.isEmpty(), "ManualLLMBackend must not deliver callbacks on its own")
        assertFalse(backend.latest!!.cancelled)

        handle.cancel()
        assertTrue(backend.latest!!.cancelled)
    }

    @Test
    fun manualBackendLetsTheTestDriveCallbacks() {
        val backend = ManualLLMBackend()
        val cb = RecordingStreamCallbacks()
        backend.generateStream(request(), cb)

        backend.latest!!.callbacks.onChunk(delta = "hi", isFinal = true, completionTokens = 3)
        backend.latest!!.callbacks.onTerminal(TerminalStatus.Completed)

        assertEquals("hi", cb.accumulated)
        assertEquals(TerminalStatus.Completed, cb.terminals.single().status)
    }

    // MARK: - Double self-checks

    @Test
    fun scriptedBackendConsumesOneScriptPerCallInOrder() {
        // Underpins every retry / suspend-relay test: call N gets script N.
        val backend = ScriptedLLMBackend(
            listOf(
                ScriptedLLMBackend.Script(terminal = TerminalStatus.Suspended),
                ScriptedLLMBackend.Script.completing("done"),
            ),
        )
        val first = RecordingStreamCallbacks()
        backend.generateStream(request(user = "call1"), first)
        assertEquals(TerminalStatus.Suspended, first.terminals.single().status)

        val second = RecordingStreamCallbacks()
        backend.generateStream(request(user = "call2"), second)
        assertEquals("done", second.accumulated)

        assertEquals(2, backend.callCount)
        assertEquals(listOf("call1", "call2"), backend.requests.map { it.user })
    }

    @Test
    fun scriptedBackendFailsLoudlyWhenOverCalled() {
        // An extra call means the retry budget went somewhere the test did not
        // intend. Silently replaying the last script would hide exactly the bug
        // the retry tests exist to catch.
        val backend = ScriptedLLMBackend(listOf(ScriptedLLMBackend.Script.completing("only")))
        backend.generateStream(request(), RecordingStreamCallbacks())
        val error = assertFailsWith<IllegalStateException> {
            backend.generateStream(request(), RecordingStreamCallbacks())
        }
        assertTrue(error.message!!.contains("exhausted"))
    }
}
