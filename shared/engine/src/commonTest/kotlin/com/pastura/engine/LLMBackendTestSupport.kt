package com.pastura.engine

import kotlin.concurrent.atomics.AtomicInt
import kotlin.concurrent.atomics.AtomicReference
import kotlin.concurrent.atomics.ExperimentalAtomicApi
import kotlin.concurrent.atomics.update

/**
 * Test doubles for the ADR-023 §5.2 inference boundary.
 *
 * Kotlin counterpart of Swift's `MockLLMService` — which stays Swift-side per
 * ADR-023 §4 ("`MockLLMService` stays for Swift-side tests; Kotlin gets its own
 * scripted mock in `commonTest`").
 *
 * Two doubles, because the boundary has two distinct testing needs:
 * - [ScriptedLLMBackend] drives a call to completion synchronously — the common
 *   case for retry / parse / handler tests.
 * - [ManualLLMBackend] never completes on its own, so a test can observe an
 *   *in-flight* call. Required for cancellation composition, which by definition
 *   only exists while a stream is open.
 *
 * **Neither satisfies the ADR-023 §6 gate.** The gate requires "a Swift-side
 * scripted streaming `LLMBackend` actual producing a real `AsyncThrowingStream`
 * through the §5.2 adapter — a Kotlin-side mock alone does NOT satisfy the gate."
 * These doubles verify Kotlin-side semantics; PR-C measures the real seam.
 */

/**
 * Delivers a pre-scripted sequence of chunks and a terminal status, synchronously,
 * before [generateStream] returns.
 *
 * Synchronous delivery is deliberate: it makes retry and suspension-relay tests
 * deterministic without a scheduler. It still exercises the real contract, because
 * [LLMCaller] must not assume the backend is asynchronous — a fast local backend
 * genuinely can complete before returning.
 *
 * @param scripts One entry per expected call, in order. Re-issues after a
 *   [TerminalStatus.Suspended] consume the next entry — that is how a
 *   suspend-then-succeed cycle is scripted.
 */
internal class ScriptedLLMBackend(
    private val scripts: List<Script>,
) : LLMBackend {

    /**
     * @param chunks           Deltas delivered in order via [StreamCallbacks.onChunk].
     * @param terminal         How this call ends.
     * @param completionTokens Reported on the final chunk only, mirroring the
     *   Swift contract. `null` means "backend cannot report cheaply".
     */
    data class Script(
        val chunks: List<String> = emptyList(),
        val terminal: TerminalStatus = TerminalStatus.Completed,
        val completionTokens: Int? = null,
    ) {
        companion object {
            /** A call that streams [text] as one chunk and completes. */
            fun completing(text: String, completionTokens: Int? = null): Script =
                Script(chunks = listOf(text), completionTokens = completionTokens)
        }
    }

    /**
     * **Every observable this double exposes is atomic**, because all three are
     * written on the engine's worker context and read from the test thread.
     *
     * Not for mutual exclusion — the engine issues calls sequentially — but for
     * **visibility**. `EngineParityTests` asserts [callCount] as its
     * retry-budget detector, and a plain `var` would reach that assertion only
     * through whatever happens-before edge the surrounding poll incidentally
     * provides. A stale read there is the shape that presents as a K/N-only
     * flake in the one assertion whose whole job is to be exact.
     *
     * **Held uniformly rather than only where a suite reads it today.** No
     * `SimulationEngine`-driven test asserts [requests] or [cancelCount] yet —
     * every current reader drives a handler directly — so leaving them plain
     * would break nothing now and hand the first such assertion exactly the
     * flake described above, with nothing in the file saying why one member
     * carried the treatment and its siblings did not. The same reasoning is
     * what [Collector]'s KDoc calls "a genuine data race … undefined behaviour
     * on Kotlin/Native".
     */
    @OptIn(ExperimentalAtomicApi::class)
    private val callIndex = AtomicInt(0)

    @OptIn(ExperimentalAtomicApi::class)
    private val recorded = AtomicReference<List<GenerationRequest>>(emptyList())

    @OptIn(ExperimentalAtomicApi::class)
    private val cancels = AtomicInt(0)

    /** Every request received, in call order. */
    @OptIn(ExperimentalAtomicApi::class)
    val requests: List<GenerationRequest> get() = recorded.load()

    /** How many times a returned [StreamHandle] was cancelled. */
    @OptIn(ExperimentalAtomicApi::class)
    val cancelCount: Int get() = cancels.load()

    /** How many calls have been issued — the retry-budget observable. */
    @OptIn(ExperimentalAtomicApi::class)
    val callCount: Int get() = callIndex.load()

    @OptIn(ExperimentalAtomicApi::class)
    override fun generateStream(request: GenerationRequest, callbacks: StreamCallbacks): StreamHandle {
        recorded.update { it + request }
        // `fetchAndAdd` rather than a load / store pair: the pair is a
        // non-atomic read-modify-write, sound here only by the sequential-calls
        // argument above, which is the argument this class is trying not to
        // depend on. The counter therefore advances BEFORE the script lookup —
        // a call with no script left was still issued, and the message below
        // reports it as such.
        val index = callIndex.fetchAndAdd(1)
        val script = scripts.getOrNull(index)
            ?: throw IllegalStateException(
                "ScriptedLLMBackend exhausted: call #${index + 1} was issued but only " +
                    "${scripts.size} script(s) were provided. An unexpected extra call usually " +
                    "means the retry budget was consumed by something the test did not intend.",
            )

        // `isFinal` marks the last chunk of a COMPLETED stream only. A suspended or
        // failed stream has no final chunk — it is cut off — mirroring Swift, where
        // `LLMError.suspended` throws out of the AsyncThrowingStream rather than
        // arriving as a terminal chunk.
        val completes = script.terminal is TerminalStatus.Completed
        script.chunks.forEachIndexed { i, delta ->
            val last = i == script.chunks.lastIndex
            callbacks.onChunk(
                delta = delta,
                isFinal = last && completes,
                completionTokens = if (last && completes) script.completionTokens else null,
            )
        }
        callbacks.onTerminal(script.terminal)
        return object : StreamHandle {
            override fun cancel() {
                cancels.fetchAndAdd(1)
            }
        }
    }
}

/**
 * Records calls and hands control to the test — never delivers a callback on its
 * own.
 *
 * Use when the test must act on an **in-flight** stream. Cancellation composition
 * (ADR-023 §5.2) is only observable this way: [ScriptedLLMBackend] has already
 * terminated by the time it returns, so there is no open stream left to cancel.
 */
internal class ManualLLMBackend : LLMBackend {

    /** One in-flight call the test drives directly. */
    class Call(
        val request: GenerationRequest,
        val callbacks: StreamCallbacks,
    ) {
        /** Set when Kotlin cancelled this call through its [StreamHandle]. */
        var cancelled: Boolean = false
            internal set
    }

    val calls: MutableList<Call> = mutableListOf()

    /** The most recent in-flight call, or `null` before the first. */
    val latest: Call? get() = calls.lastOrNull()

    override fun generateStream(request: GenerationRequest, callbacks: StreamCallbacks): StreamHandle {
        val call = Call(request, callbacks)
        calls += call
        return object : StreamHandle {
            override fun cancel() {
                call.cancelled = true
            }
        }
    }
}

/**
 * Records the exact callback sequence a backend delivered, so tests can assert the
 * [LLMBackend.generateStream] ordering contract rather than trusting it.
 */
internal class RecordingStreamCallbacks : StreamCallbacks {

    sealed interface Event {
        data class Chunk(val delta: String, val isFinal: Boolean, val completionTokens: Int?) : Event
        data class Terminal(val status: TerminalStatus) : Event
    }

    val events: MutableList<Event> = mutableListOf()

    val chunks: List<Event.Chunk> get() = events.filterIsInstance<Event.Chunk>()
    val terminals: List<Event.Terminal> get() = events.filterIsInstance<Event.Terminal>()

    /** Concatenated deltas — what a consumer would have accumulated. */
    val accumulated: String get() = chunks.joinToString("") { it.delta }

    override fun onChunk(delta: String, isFinal: Boolean, completionTokens: Int?) {
        events += Event.Chunk(delta, isFinal, completionTokens)
    }

    override fun onTerminal(status: TerminalStatus) {
        events += Event.Terminal(status)
    }
}
