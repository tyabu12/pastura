package com.pastura.engine

import com.pastura.models.ChatTurnMarkers
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
     *    [StreamCallbacks.onTerminal]. A [TerminalStatus.Completed] stream
     *    additionally carries exactly one `isFinal = true` chunk, always last; a
     *    [TerminalStatus.Suspended] or [TerminalStatus.Failed] stream carries none
     *    (it was cut off). So "zero or more" bounds the *non-final* chunks.
     * 2. No callback fires after [StreamCallbacks.onTerminal].
     * 3. **[StreamHandle.cancel] is a best-effort request to stop, not a
     *    barrier.** It does not retract callbacks already in flight, and late
     *    callbacks MAY still arrive — Kotlin ignores them. This is deliberately
     *    weaker than "nothing fires after `cancel()` returns", because that is not
     *    implementable by the intended iOS actual: Swift `Task.cancel()` is
     *    asynchronous and cannot retract a `continuation.yield` already in flight
     *    on another thread. A backend needing stricter behaviour would have to own
     *    an atomic gate; none is required to.
     * 4. **Callbacks are delivered SERIALLY — never concurrently — and each
     *    callback happens-before the next.** They may arrive on any thread, and
     *    Kotlin does not assume the caller's context; but it does assume this
     *    ordering and does **not** lock. [LLMCaller] accumulates chunk deltas into
     *    plain fields, so a backend forwarding from two threads at once (e.g.
     *    deltas from a sampling thread and the terminal from a completion handler)
     *    would corrupt the accumulated text or lose the token count — a data race
     *    that K/N will not diagnose. The intended iOS actual satisfies this for
     *    free: one `Task` per call draining one `AsyncThrowingStream` is serial by
     *    construction. The clause therefore costs nothing and closes the hole for
     *    every future adapter.
     *
     * @param request   The prompts + optional output schema for this call.
     * @param callbacks Where chunks and the terminal status are delivered.
     * @return A handle for cancelling this call.
     */
    public fun generateStream(request: GenerationRequest, callbacks: StreamCallbacks): StreamHandle

    /**
     * Every turn-marker pair whose **plaintext** form could plausibly appear in
     * this backend's decoded output, for consumers that must recognize a
     * hallucinated turn boundary — [JSONResponseParser] truncation and the
     * [LLMCaller] chat-template leakage diagnostic (#1422).
     *
     * The set is the loaded model's own pair **unioned with**
     * [ChatTurnMarkers.chatML], so a backend that cannot name its model keeps
     * the pre-#1422 ChatML-only behaviour, and a ChatML model does not grow a
     * second, redundant entry. Mirrors Swift's `LLMService.knownTurnMarkers`
     * name-for-name, including where the union is computed, so the two seams
     * stay comparable.
     *
     * ⚠️ **This default does not cross Kotlin/Native.** A Kotlin interface's
     * default implementation is not carried into the generated Obj-C protocol
     * as an optional requirement, so the future Swift adapter over
     * `LlamaCppService` must state this member explicitly — it will **not**
     * silently inherit ChatML-only. Same asymmetry class as the default-args
     * one in `.claude/rules/kmp-interop.md` Pattern 3. That is the safe
     * direction (the compiler asks), but do not plan around inheritance.
     */
    public val knownTurnMarkers: List<ChatTurnMarkers>
        get() = listOf(ChatTurnMarkers.chatML)
}

/**
 * One inference request crossing the §5.2 boundary.
 *
 * [antiRepetitionSeeds] landed with its consumer, [SpeakEachHandler] (#1105) —
 * the Engine's only seeder, so until that handler was ported the field would have
 * been dead weight for the Swift adapter to map.
 *
 * @property system The system prompt defining the agent's persona and rules.
 * @property user   The user prompt with context and instructions for this turn.
 * @property schema Optional output schema. Backends translate this to their
 *   native constrained-decoding mechanism (llama.cpp: GBNF grammar). `null`
 *   means unconstrained generation.
 * @property antiRepetitionSeeds Prior text spans seeded into the backend's DRY
 *   sampler so a token-level repetition penalty spans the turn boundary (#1105).
 *   Empty means no seeding — the default, and what every non-seeding caller
 *   passes.
 *
 *   **Read the scope before reaching for this to fix a repetition complaint.**
 *   It covers exactly one case — an agent's own prior turns, in `speak_each`.
 *   Cross-*agent* template collapse and every other phase are **unreached**, and
 *   covering one needs a new seeder rather than a bigger value here. The full
 *   three-scope contract (including what the backend's own per-generation chain
 *   penalties do and do not reach) lives in `.claude/rules/engine.md`
 *   § "The chain's `penalties` cannot reach across a `generate()`" — read it
 *   there rather than trusting this paragraph to have stayed current.
 *
 *   A backend that cannot seed (Ollama's HTTP API, Foundation Models) ignores it
 *   rather than failing — mirroring the Swift services, which document the same
 *   no-op.
 */
public data class GenerationRequest(
    public val system: String,
    public val user: String,
    public val schema: OutputSchema? = null,
    public val antiRepetitionSeeds: List<String> = emptyList(),
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
     * @param isFinal          `true` on the last chunk of a **completed** stream.
     *   Mirrors Swift `LLMStreamChunk.isFinal`: exactly one chunk carries it and
     *   it is always the last observed. A suspended or failed stream carries no
     *   final chunk — see clause 1. Backends without true streaming (Ollama, a
     *   non-chunked mock) satisfy the contract by emitting a single
     *   `isFinal = true` chunk carrying the whole response; llama.cpp instead
     *   emits many non-final chunks plus a final chunk carrying **only** the token
     *   count with an empty delta (`LLMCaller.swift:298-302`). Both shapes are
     *   legal and [LLMCaller] handles them uniformly.
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
     *   Migration path, so the deferral stays cheap: Stage 3 adds a `kind` field
     *   with a default; `errorCode` / `message` stay. Source-additive on both
     *   sides.
     *
     * @param errorCode Backend-scoped identifier. **Diagnostic only — never
     *   display verbatim, and do not branch on it**; the taxonomy that would make
     *   branching safe does not exist yet. Note [LLMCaller] currently formats it
     *   into `SimulationError.LlmGenerationFailed(description:)`, whose Swift
     *   counterpart is a `LocalizedError` that can reach the UI — Stage 3's
     *   taxonomy is what should terminate that leak.
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
     * Request cancellation of this call. Idempotent, and safe to call after the
     * stream already ended (the common case: a cancelled coroutine whose stream
     * had completed).
     *
     * **Best-effort, per [LLMBackend.generateStream]'s clause 3** — it does not
     * retract callbacks already in flight. Kotlin ignores late callbacks rather
     * than requiring backends to gate them.
     */
    public fun cancel()
}
