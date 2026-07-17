package com.pastura.engine

import com.pastura.models.OutputSchema
import com.pastura.models.SimulationError
import com.pastura.models.SimulationEvent
import com.pastura.models.TurnOutput
import kotlin.coroutines.coroutineContext
import kotlin.coroutines.resume
import kotlin.time.DurationUnit
import kotlin.time.TimeSource
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * Wraps LLM inference with retry logic and event emission.
 *
 * Retries up to [MAX_RETRIES] times on JSON parse failure or empty fields
 * (`"..."` or `""`). Emits `InferenceStarted` / `InferenceCompleted` per attempt,
 * plus per-chunk `AgentOutputStream` snapshots for UI progress.
 *
 * This is where the ADR-023 §5.2 inference boundary is actually consumed: it
 * turns [LLMBackend]'s callbacks back into a `suspend` call
 * ([suspendCancellableCoroutine]), so structured concurrency stays inside Kotlin
 * and nothing coroutine-shaped crosses K/N (Decision 2).
 *
 * ## Scope: the ADR-023 §6 Stage-2 gate slice's *bounded* core
 *
 * §6 names this explicitly: "`LLMCaller` core (retry loop + stream consumption +
 * suspension relay IN; `PartialOutputExtractor`, language-adherence retry,
 * `StreamFailure` taxonomy stay Stage 3)".
 *
 * **Knowingly absent** — named units, tracked on #501:
 *
 * | Absent | Why |
 * |---|---|
 * | `PartialOutputExtractor` | named Stage-3 freight; snapshots carry raw accumulated text instead — see [AgentOutputStream emission][emitSnapshot] |
 * | Language-adherence retry (ADR-010 Step E) | named Stage-3 freight; no `detector` reaches this slice |
 * | `StreamFailure` taxonomy + ADR-021 D3 classification | named Stage-3 freight; [TerminalStatus.Failed] maps straight to [SimulationError.LlmGenerationFailed] |
 * | The `StreamingDiag` log channel | the `EngineLogger` seam is not in this slice's [PhaseContext] |
 *
 * Swift original: `Pastura/Pastura/Engine/LLMCaller.swift`.
 */
internal class LLMCaller(
    private val parser: JSONResponseParser = JSONResponseParser(),
) {

    companion object {
        /**
         * Parse/empty retries per call. `0..MAX_RETRIES` inclusive = 3 attempts,
         * matching Swift's `for attempt in 0...Self.maxRetries`.
         *
         * **Suspend cycles do not consume this** (§5.2 invariant 1) — see [call].
         */
        const val MAX_RETRIES: Int = 2
    }

    /** One drained stream. */
    private data class StreamResult(val rawText: String, val completionTokens: Int?)

    /**
     * Call the backend with retry logic and return a parsed [TurnOutput].
     *
     * @param expectedKeys Derived once from the schema at the handler boundary and
     *   passed through to the parser's guard — the single source of truth for both
     *   the backend-layer constraint and the parser-layer check (#194 PR#b).
     * @throws SimulationException wrapping [SimulationError.RetriesExhausted] after
     *   [MAX_RETRIES] parse failures, or [SimulationError.LlmGenerationFailed] on a
     *   backend failure.
     */
    suspend fun call(
        backend: LLMBackend,
        system: String,
        user: String,
        agentName: String,
        schema: OutputSchema? = null,
        relay: SuspensionRelay,
        emitter: (SimulationEvent) -> Unit,
    ): TurnOutput {
        val expectedKeys: Set<String> = schema?.fields?.map { it.name }?.toSet() ?: emptySet()
        val request = GenerationRequest(system = system, user = user, schema = schema)

        for (attempt in 0..MAX_RETRIES) {
            emitter(SimulationEvent.InferenceStarted(agent = agentName))
            val startMark = TimeSource.Monotonic.markNow()

            val result = try {
                consumeStreamWithSuspendRetry(backend, request, relay, agentName, emitter)
            } catch (e: SimulationException) {
                // Tokens are unknown on failure — the backend never completed.
                emitInferenceCompleted(agentName, startMark, tokens = null, emitter = emitter)
                throw e
            }
            emitInferenceCompleted(agentName, startMark, result.completionTokens, emitter)

            val output = try {
                parser.parse(result.rawText, expectedKeys).first
            } catch (_: SimulationException) {
                if (attempt < MAX_RETRIES) continue
                throw SimulationException(SimulationError.RetriesExhausted)
            }

            // Note the `&&`: on the LAST attempt an empty-field output is RETURNED,
            // not thrown. Swift does the same (`if hasEmptyFields(output) && attempt
            // < maxRetries`), and the asymmetry with parse failure is deliberate —
            // a parseable-but-thin answer still lets the simulation continue.
            if (hasEmptyFields(output) && attempt < MAX_RETRIES) continue

            return output
        }

        // Unreachable: the loop either returns or throws. Mirrors Swift's
        // "should not reach here, but satisfy compiler" tail.
        throw SimulationException(SimulationError.RetriesExhausted)
    }

    /**
     * Drain one generation, re-issuing transparently across suspend cycles.
     *
     * **§5.2 invariant 1 — suspend re-issues stay OFF the retry budget.** This loop
     * is separate from [call]'s `attempt` counter by construction: a
     * [TerminalStatus.Suspended] `continue`s *here*, never returning to the caller,
     * so a user backgrounding and foregrounding N times cannot exhaust the parse
     * budget. `SuspendController.swift:18` documents the same contract Swift-side.
     *
     * **§5.2 invariant 2 — one deferred + one relay cycle per suspension.**
     * [SuspensionRelay.arm] runs before each issue, so each cycle allocates fresh
     * and a resume racing the suspend observation is latched rather than lost. See
     * that type's doc for why arming here — not inside `awaitResume` — is the whole
     * design.
     */
    private suspend fun consumeStreamWithSuspendRetry(
        backend: LLMBackend,
        request: GenerationRequest,
        relay: SuspensionRelay,
        agentName: String,
        emitter: (SimulationEvent) -> Unit,
    ): StreamResult {
        while (true) {
            // Arm BEFORE issuing: a resume can land any time after the backend
            // suspends, including before we observe it.
            relay.arm()
            val (result, status) = issueStream(backend, request, agentName, emitter)

            when (status) {
                is TerminalStatus.Completed -> return result
                is TerminalStatus.Suspended -> {
                    relay.awaitResume()
                    // Mirrors Swift's `try Task.checkCancellation()` right after
                    // `await controller.awaitResume()`. Load-bearing, not
                    // ceremony: `Deferred.await()` on an ALREADY-completed
                    // deferred (the sticky-latch fast path) returns without
                    // suspending, so it never observes cancellation. Without this,
                    // a run cancelled while parked — whose resume had already
                    // latched — would `continue`, re-arm, and kick off a real
                    // llama_decode before `suspendCancellableCoroutine` noticed and
                    // called `handle.cancel()`. Self-healing, but exactly the waste
                    // §5.2's cancellation clause exists to prevent.
                    coroutineContext.ensureActive()
                    // Loop: re-issue from scratch. Any snapshot emitted before the
                    // suspend is naturally replaced by the new stream's snapshots
                    // on the consumer side, so no reset event is needed.
                }
                is TerminalStatus.Failed -> throw SimulationException(
                    SimulationError.LlmGenerationFailed(
                        description = status.message?.let { "${status.errorCode}: $it" } ?: status.errorCode,
                    ),
                )
            }
        }
    }

    /**
     * Issue one stream and suspend until its terminal status arrives.
     *
     * **Cancellation composition (§5.2 contract clause).** `invokeOnCancellation`
     * routes Kotlin coroutine cancellation to [StreamHandle.cancel]. Without it,
     * `RunHandle.cancel()` would cancel the Kotlin `Job` but leave the Swift stream
     * — and its `llama_decode` loop — running.
     */
    private suspend fun issueStream(
        backend: LLMBackend,
        request: GenerationRequest,
        agentName: String,
        emitter: (SimulationEvent) -> Unit,
    ): Pair<StreamResult, TerminalStatus> = suspendCancellableCoroutine { continuation ->
        val callbacks = object : StreamCallbacks {
            private val accumulated = StringBuilder()
            private var tokens: Int? = null

            override fun onChunk(delta: String, isFinal: Boolean, completionTokens: Int?) {
                // Symmetric with onTerminal's guard. `cancel()` is best-effort
                // (LLMBackend clause 3), so a late chunk is legal — but emitting
                // its snapshot would push an AgentOutputStream event into a run
                // the user already cancelled.
                if (!continuation.isActive) return
                if (delta.isNotEmpty()) {
                    accumulated.append(delta)
                    emitSnapshot(agentName, accumulated.toString(), emitter)
                }
                // Only the final chunk carries a token count (the §5.2 contract), so
                // a non-final chunk's null must not clobber it.
                if (isFinal) tokens = completionTokens
            }

            override fun onTerminal(status: TerminalStatus) {
                // What this guard actually buys — measured, not assumed. Resuming
                // a CANCELLED continuation does NOT throw: kotlinx's
                // `CancellableContinuationImpl.resumeImpl` hits
                // `is CancelledContinuation -> if (state.makeResumed()) return`,
                // i.e. the FIRST post-cancel resume is a silent no-op. The guard
                // covers the DUPLICATE-terminal case, which would otherwise hit
                // `alreadyResumedError`. Both are reachable because clause 3 makes
                // cancel() best-effort, so late callbacks are legal.
                if (continuation.isActive) {
                    continuation.resume(StreamResult(accumulated.toString(), tokens) to status)
                }
            }
        }

        val handle = backend.generateStream(request, callbacks)
        continuation.invokeOnCancellation { handle.cancel() }
    }

    /**
     * Emit a live progress snapshot.
     *
     * **Carries RAW accumulated text, not an extracted primary/thought split.**
     * `PartialOutputExtractor` — which computes that split — is named Stage-3
     * freight (ADR-023 §6). The event is still emitted per chunk on purpose: it is
     * the highest-frequency Kotlin->Swift crossing, and §6 measurement (i)/(ii)
     * measure exactly that boundary at realistic token rates. Dropping it would
     * leave the gate measuring the event boundary at ~3 crossings per turn instead
     * of the real 10-50/s, biasing a GO optimistic.
     *
     * `thought` is null rather than guessed: a wrong split would be worse than an
     * honest absence, and PR-C's consumer only counts and times these.
     */
    private fun emitSnapshot(agentName: String, raw: String, emitter: (SimulationEvent) -> Unit) {
        // TODO(#501 Stage 3): `primary` is RAW accumulated text. PartialOutputExtractor
        // supplies the real primary/thought split — do NOT render this to users as-is.
        emitter(SimulationEvent.AgentOutputStream(agent = agentName, primary = raw, thought = null))
    }

    private fun emitInferenceCompleted(
        agentName: String,
        start: TimeSource.Monotonic.ValueTimeMark,
        tokens: Int?,
        emitter: (SimulationEvent) -> Unit,
    ) {
        emitter(
            SimulationEvent.InferenceCompleted(
                agent = agentName,
                durationSeconds = start.elapsedNow().toDouble(DurationUnit.SECONDS),
                tokenCount = tokens,
            ),
        )
    }

    private fun hasEmptyFields(output: TurnOutput): Boolean =
        output.fields.values.any { it == "..." || it.isEmpty() }
}
