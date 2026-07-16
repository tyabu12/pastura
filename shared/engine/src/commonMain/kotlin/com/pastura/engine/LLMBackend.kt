package com.pastura.engine

import com.pastura.models.OutputSchema

/**
 * The inference boundary: Kotlin `LLMCaller` -> a platform LLM backend
 * (ADR-023 §5.2).
 *
 * **Why a plain interface and not `expect`/`actual`.** This mirrors today's
 * Swift `LLMService` protocol-injection pattern: the backend is constructor-
 * injected, so `commonTest` supplies a scripted Kotlin fake and iOS supplies a
 * Swift adapter over `LlamaCppService` — without either the module or the K/N
 * boundary needing a platform-specific declaration.
 *
 * **Why callbacks and not `suspend`/Flow** (ADR-023 Decision 2). No `suspend`
 * function, Flow, or `AsyncSequence` crosses Kotlin/Native. Structured
 * concurrency stays inside each language: Swift keeps its
 * `AsyncThrowingStream`, Kotlin re-wraps these callbacks internally via
 * `suspendCancellableCoroutine`. That keeps the two hardest semantics —
 * cancellation composition and the ADR-003 suspension contract — as explicit
 * contract clauses this module's tests can exercise, rather than emergent
 * behaviour of a codegen layer pinned to Kotlin-version skew.
 *
 * **Implemented by the platform, called by Kotlin.** The iOS actual is a Swift
 * adapter running one `Task` per call that consumes
 * `LLMService.generateStream`'s `AsyncThrowingStream` and forwards each chunk.
 * `LLMError.suspended` maps to [TerminalStatus.Suspended]; `attachSuspendController`
 * and the `SuspendController` object itself stay entirely inside that adapter
 * and **never cross this boundary** (ADR-023 Decision 3).
 *
 * Swift counterpart: `Pastura/Pastura/LLM/LLMService.swift`.
 *
 * Ported for the ADR-023 §6 Stage-2 gate slice (#501).
 */
public interface LLMBackend {
    /**
     * Begin one streaming generation.
     *
     * **Must not block.** Returns a [StreamHandle] immediately; chunks and the
     * terminal status arrive on [callbacks].
     *
     * **Callback contract** (the backend must honour all four):
     * 1. Zero or more [StreamCallbacks.onChunk] calls, then **exactly one**
     *    [StreamCallbacks.onTerminal].
     * 2. No callback fires after [StreamCallbacks.onTerminal].
     * 3. No callback fires after [StreamHandle.cancel] returns — a backend that
     *    cannot guarantee this must drop late callbacks itself, because
     *    [LLMCaller] treats cancellation as final.
     * 4. Callbacks may arrive on any thread. Kotlin does not assume the caller's
     *    context.
     *
     * @param request   The prompts + optional output schema for this call.
     * @param callbacks Where chunks and the terminal status are delivered.
     * @return A handle for cancelling this call.
     */
    public fun generateStream(request: GenerationRequest, callbacks: StreamCallbacks): StreamHandle
}

/**
 * One inference request crossing the §5.2 boundary.
 *
 * **Deliberately omits `antiRepetitionSeeds`** (#1105). Swift's
 * `LLMService.generateStream` carries it, but `SpeakEachHandler` is the Engine's
 * only seeder and that handler is Stage-3 freight — so a seeds field on this
 * gate slice would be dead weight the Swift adapter must map for nothing. Add it
 * with its consumer.
 *
 * @property system The system prompt defining the agent's persona and rules.
 * @property user   The user prompt with context and instructions for this turn.
 * @property schema Optional output schema. Backends translate this to their
 *   native constrained-decoding mechanism (llama.cpp: GBNF grammar). `null`
 *   means unconstrained generation.
 */
public data class GenerationRequest(
    public val system: String,
    public val user: String,
    public val schema: OutputSchema? = null,
)

/**
 * Where a backend delivers a generation's chunks and terminal status.
 *
 * **Implemented by Kotlin, called by the platform** — the mirror image of
 * [LLMBackend]. See [LLMBackend.generateStream] for the ordering contract the
 * caller must honour.
 */
public interface StreamCallbacks {
    /**
     * One incremental chunk.
     *
     * @param delta            Text generated since the previous chunk. May be
     *   empty — Kotlin skips empty deltas rather than treating them as a signal.
     * @param isFinal          `true` on the last chunk of this stream. Mirrors
     *   Swift `LLMStreamChunk.isFinal`: exactly one chunk per stream carries it,
     *   and it is always the last observed. Backends without true streaming
     *   (Ollama, a non-chunked mock) satisfy the contract by emitting a single
     *   `isFinal = true` chunk carrying the whole response.
     * @param completionTokens Token count, populated only on the final chunk and
     *   only when the backend can report it cheaply. `null` means "unknown
     *   throughput" — consumers exclude such calls from rolling averages rather
     *   than treating it as zero.
     */
    public fun onChunk(delta: String, isFinal: Boolean, completionTokens: Int?)

    /** How the stream ended. Fires exactly once, after every [onChunk]. */
    public fun onTerminal(status: TerminalStatus)
}

/**
 * How one generation ended.
 *
 * A sealed interface rather than an enum because [Failed] carries a payload —
 * the Kotlin counterpart of Swift's `enum` with associated values.
 */
public sealed interface TerminalStatus {
    /** Generation finished normally; the accumulated text is complete. */
    public object Completed : TerminalStatus

    /**
     * Generation was interrupted by a platform suspend request and is
     * **re-issuable** (ADR-003 / ADR-023 §5.2).
     *
     * Maps from Swift `LLMError.suspended`. On iOS this means the app went to
     * background and Metal GPU work was cut off mid-`llama_decode` — not a
     * failure. [LLMCaller] parks on a `CompletableDeferred`, waits for
     * [RunHandle.notifyLLMResumed], then re-issues the same prompt.
     *
     * **Invariant 1 (ADR-023 §5.2): a suspend cycle must NOT consume the
     * parse/empty retry budget.** Users can background/foreground freely.
     */
    public object Suspended : TerminalStatus

    /**
     * Generation failed and is not re-issuable by the relay.
     *
     * **Deliberately untyped**: the Swift `StreamFailure` taxonomy (and its
     * ADR-021 D3 classification) is Stage-3 freight, so this gate slice carries
     * an opaque code + message rather than pre-committing to a taxonomy the
     * deferred work is most likely to reshape. Ratify the shape when
     * `StreamFailure` lands, not here.
     *
     * @param errorCode Backend-scoped identifier. Diagnostic only — do not
     *   branch on it; the taxonomy that would make that safe does not exist yet.
     * @param message   Human-readable detail, when the backend has one.
     */
    public data class Failed(
        public val errorCode: String,
        public val message: String? = null,
    ) : TerminalStatus
}

/**
 * Cancels one in-flight [LLMBackend.generateStream] call.
 *
 * **Implemented by the platform, called by Kotlin.**
 *
 * **Cancellation composition (ADR-023 §5.2 contract clause).** Kotlin coroutine
 * cancellation MUST reach [cancel] — [LLMCaller] wires it through
 * `suspendCancellableCoroutine`'s `invokeOnCancellation` — and the iOS actual
 * MUST cancel its backing Swift `Task` from it. Without this clause,
 * [RunHandle.cancel] cancels the Kotlin `Job` but leaves the Swift stream, and
 * its `llama_decode` loop, running.
 */
public interface StreamHandle {
    /**
     * Cancel this call. Idempotent, and safe to call after the stream already
     * ended (the common case: a cancelled coroutine whose stream had completed).
     *
     * Per [LLMBackend.generateStream]'s contract clause 3, no callback may fire
     * after this returns.
     */
    public fun cancel()
}
