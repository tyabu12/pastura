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
 * plus per-chunk `AgentOutputStream` snapshots for UI progress. After the shape
 * checks it runs the ADR-010 Step E output-language adherence check, and routes
 * all diagnostics through the injected [EngineLogger] seam (the `StreamingDiag`
 * channel `scripts/analyze-streaming-diag.sh` parses).
 *
 * This is where the ADR-023 §5.2 inference boundary is actually consumed: it
 * turns [LLMBackend]'s callbacks back into a `suspend` call
 * ([suspendCancellableCoroutine]), so structured concurrency stays inside Kotlin
 * and nothing coroutine-shaped crosses K/N (Decision 2).
 *
 * ## Knowingly absent — named units, tracked on #501
 *
 * The Stage-2 gate slice's bounded core has grown: B0b (ADR-023 §6 Stage 3) landed
 * the language-adherence retry (ADR-010 Step E) and the [EngineLogger]
 * `StreamingDiag` channel. What still stays Stage-3 freight:
 *
 * | Absent | Why |
 * |---|---|
 * | `PartialOutputExtractor` | the type landed in PR-3 (#501 Stage 3), but this slice does not consume it yet — snapshots still carry raw accumulated text; wiring is deferred to a later Wave B step (see [emitSnapshot]) |
 * | `StreamFailure` taxonomy + ADR-021 D3 classification | named Stage-3 freight; [TerminalStatus.Failed] maps straight to [SimulationError.LlmGenerationFailed] |
 *
 * Swift original: `Pastura/Pastura/Engine/LLMCaller.swift` (+ its sibling
 * `LLMCaller+Logging.swift`, folded into this file's logging helpers below — Kotlin
 * has no SwiftLint `file_length` cap, so no sibling split is needed).
 *
 * @param logger The diagnostic seam. Defaults to [NoopEngineLogger] (silent) so
 *   tests / non-App consumers construct `LLMCaller()`; production handlers pass
 *   `context.logger` (an `OSLogEngineLogger` in the Swift App layer once the K/N
 *   boundary wiring lands — see [PhaseContext]).
 */
internal class LLMCaller(
    private val parser: JSONResponseParser = JSONResponseParser(),
    private val logger: EngineLogger = NoopEngineLogger(),
) {

    companion object {
        /**
         * Parse/empty retries per call. `0..MAX_RETRIES` inclusive = 3 attempts,
         * matching Swift's `for attempt in 0...Self.maxRetries`.
         *
         * **Suspend cycles do not consume this** (§5.2 invariant 1) — see [call].
         */
        const val MAX_RETRIES: Int = 2

        /** OSLog category for general `LLMCaller` diagnostics. */
        private const val LOG_CATEGORY: String = "LLMCaller"

        /**
         * OSLog category for the streaming-diagnostic channel
         * `scripts/analyze-streaming-diag.sh` captures (`retryCause` / `repaired`
         * / `langCheckSkipped`). Load-bearing — must stay `"StreamingDiag"`.
         */
        private const val DIAG_CATEGORY: String = "StreamingDiag"

        /**
         * Minimum unicode-scalar count of the joined natural-language values
         * required to run the adherence check. Below this a language detector's
         * confidence is unreliable (single proper nouns, enum tokens), so the
         * check is skipped rather than spuriously flagging a mismatch. Matches
         * Swift's `minDetectionLength`.
         */
        private const val MIN_DETECTION_LENGTH: Int = 12
    }

    /** One drained stream. */
    private data class StreamResult(val rawText: String, val completionTokens: Int?)

    /**
     * Call the backend with retry logic and return a parsed [TurnOutput].
     *
     * @param expectedKeys Derived once from the schema at the handler boundary and
     *   passed through to the parser's guard — the single source of truth for both
     *   the backend-layer constraint and the parser-layer check (#194 PR#b).
     * @param detector Optional [LanguageDetector] for the ADR-010 Step E
     *   output-language adherence check. When both [detector] and
     *   [expectedLanguage] are non-null, a post-parse check runs after the
     *   empty-field check; on mismatch within the existing [MAX_RETRIES] budget the
     *   call retries (`retryCause cause=language_mismatch`), and on exhaustion a
     *   [SimulationEvent.LanguageMismatch] is emitted and the parsed output is
     *   still returned (the sim continues — structurally distinct from a parse /
     *   empty-field exhaustion, which throws).
     * @param expectedLanguage The scenario's `engineLanguage` (ADR-010 D5/D6).
     *   `null` skips the adherence check entirely (back-compat for callers that
     *   pre-date the seam).
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
        detector: LanguageDetector? = null,
        expectedLanguage: String? = null,
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

            val parseResult = try {
                parser.parse(result.rawText, expectedKeys)
            } catch (_: SimulationException) {
                logParseFailure(agentName, result.rawText, attempt)
                if (attempt < MAX_RETRIES) {
                    emitRetryCause(agentName, attempt + 1, "parse_failed")
                    continue
                }
                throw SimulationException(SimulationError.RetriesExhausted)
            }
            val output = parseResult.first
            logRepairIfNeeded(agentName, parseResult.second)
            logChatTemplateLeakage(result.rawText)

            // Note the `&&`: on the LAST attempt an empty-field output is RETURNED,
            // not thrown. Swift does the same (`if hasEmptyFields(output) && attempt
            // < maxRetries`), and the asymmetry with parse failure is deliberate —
            // a parseable-but-thin answer still lets the simulation continue.
            if (hasEmptyFields(output) && attempt < MAX_RETRIES) {
                logEmptyFields(output.fields, attempt)
                emitRetryCause(agentName, attempt + 1, "empty_field")
                continue
            }

            // Language adherence (ADR-010 Step E). Ordered AFTER parse_failed +
            // empty_field — shape failures take priority, because a
            // wrong-language-but-empty response should retry for the empty field
            // first. No-ops when detector or expectedLanguage is null (back-compat)
            // and when the joined natural-language input is below the min-length
            // gate. See [handleLanguageAdherence] for the side-effect contract.
            if (handleLanguageAdherence(output, schema, detector, expectedLanguage, agentName, attempt, emitter)) {
                continue
            }

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
     * `PartialOutputExtractor` — which computes that split — landed in PR-3
     * (ADR-023 §6 Stage 3) but is not consumed here yet. The event is still
     * emitted per chunk on purpose: it is
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

    // MARK: - Language adherence (ADR-010 Step E)

    /**
     * Decide whether the current attempt's parsed output triggers a
     * language-adherence retry, and apply the side effects (emit the retry cause,
     * or emit [SimulationEvent.LanguageMismatch] on exhaustion). Mirrors Swift's
     * `handleLanguageAdherence`.
     *
     * @return `true` when the caller should `continue` the loop (retry the
     *   inference); `false` when it should proceed to `return output` — either
     *   because no mismatch was detected, or because the retry budget was exhausted
     *   and the event has already been emitted (sim continues with the output).
     */
    private fun handleLanguageAdherence(
        output: TurnOutput,
        schema: OutputSchema?,
        detector: LanguageDetector?,
        expectedLanguage: String?,
        agentName: String,
        attempt: Int,
        emitter: (SimulationEvent) -> Unit,
    ): Boolean {
        val detected = detectLanguageMismatch(output, schema, detector, expectedLanguage, agentName)
            ?: return false
        if (attempt < MAX_RETRIES) {
            emitRetryCause(agentName, attempt + 1, "language_mismatch")
            return true
        }
        // Exhausted: surface the verdict but fall through. expectedLanguage is
        // non-null here — detectLanguageMismatch returns non-null only when both
        // detector and expectedLanguage are set.
        if (expectedLanguage != null) {
            emitter(
                SimulationEvent.LanguageMismatch(
                    agent = agentName,
                    detected = detected,
                    expected = expectedLanguage,
                ),
            )
        }
        return false
    }

    /**
     * Run the post-parse adherence check.
     *
     * @return the detected language code when a mismatch was found (the caller
     *   seeds the [SimulationEvent.LanguageMismatch] event with it on exhaustion),
     *   or `null` when the check was skipped or the output matches the expected
     *   language — both meaning "no retry needed".
     */
    private fun detectLanguageMismatch(
        output: TurnOutput,
        schema: OutputSchema?,
        detector: LanguageDetector?,
        expectedLanguage: String?,
        agentName: String,
    ): String? {
        if (detector == null || expectedLanguage == null) return null
        val joined = naturalLanguageFieldValues(output, schema).joinToString("\n")
        // Swift gates on `joined.unicodeScalars.count`; commonMain has no
        // `codePointCount`, so count scalars as chars-minus-low-surrogates: a
        // surrogate pair is one scalar whose high surrogate is counted and low
        // surrogate skipped, and a BMP char is one scalar counted once.
        val scalarCount = joined.count { !it.isLowSurrogate() }
        if (scalarCount < MIN_DETECTION_LENGTH) {
            emitLangCheckSkipped(agentName, "too_short")
            return null
        }
        val detected = detector.detect(joined) ?: return null
        return if (detected == expectedLanguage) null else detected
    }

    /**
     * Collect natural-language values from [output], keeping only fields whose kind
     * is [OutputSchema.Kind.StringKind]. Author-defined choice tokens
     * ([OutputSchema.Kind.Choice], e.g. `cooperate` / `betray` in a `choose` phase)
     * are excluded — their language is fixed by the scenario author, not the LLM,
     * so they would skew the detector's verdict (ADR-010 Step E, #405).
     *
     * When [schema] is null the caller hasn't opted into constrained decoding, so
     * every field is treated as natural language (Swift's conservative fallback —
     * unconstrained generation is rare in the production path).
     */
    private fun naturalLanguageFieldValues(output: TurnOutput, schema: OutputSchema?): List<String> {
        if (schema == null) return output.fields.values.toList()
        val naturalNames = schema.fields
            .filter { it.kind is OutputSchema.Kind.StringKind }
            .map { it.name }
            .toSet()
        return output.fields.filterKeys { it in naturalNames }.values.toList()
    }

    // MARK: - Logging (StreamingDiag + engineering channels)
    //
    // Folded in from Swift's sibling `LLMCaller+Logging.swift`. Each builds the
    // fully-rendered message and routes it through the injected [EngineLogger] seam
    // (#501 S0.2). The `StreamingDiag`-category wire formats — `retryCause agent=…
    // attempt=… cause=…` (cause last), `repaired agent=… kind=…`, `langCheckSkipped
    // agent=… reason=…` — are load-bearing: `scripts/analyze-streaming-diag.sh`
    // parses them. Swift's `#if DEBUG print()` console fallback is dropped (a
    // platform-specific Xcode convenience, not part of the wire contract).

    /**
     * Emit the parse-failure warning. `agent=` is load-bearing for the harness
     * stderr channel: a terminal turn failure does NOT emit a following `retryCause`
     * line ([call] throws instead), so a reader cannot recover the agent by scanning
     * neighbours — the record has to name itself. `raw=` stays the trailing token
     * because it is unbounded.
     */
    private fun logParseFailure(agentName: String, raw: String, attempt: Int) {
        // `raw` may echo user-authored scenario / persona content via malformed LLM
        // output, but the same data is already persisted on-device to
        // `TurnRecord.rawOutput` (ADR-001), so exposure is consistent with the
        // existing surface. `.public` is required for diagnostic value off-device.
        logger.log(
            EngineLogLevel.WARNING,
            LOG_CATEGORY,
            "JSON parse failed agent=$agentName (attempt ${attempt + 1}/${MAX_RETRIES + 1}): raw=${raw.take(500)}",
            EngineLogPrivacy.PUBLIC,
        )
    }

    /**
     * Emit the `StreamingDiag` `retryCause` line. Field order
     * `agent=… attempt=… cause=…` is load-bearing — the analyzer regex expects
     * `cause=` to be the last token (#194 PR#a Item 4).
     */
    private fun emitRetryCause(agentName: String, attempt: Int, cause: String) {
        logger.log(
            EngineLogLevel.INFO,
            DIAG_CATEGORY,
            "retryCause agent=$agentName attempt=$attempt cause=$cause",
            EngineLogPrivacy.PUBLIC,
        )
    }

    /** Emit the `StreamingDiag` `repaired` line. No-op when the parse didn't repair. */
    private fun logRepairIfNeeded(agentName: String, kind: String?) {
        if (kind == null) return
        logger.log(
            EngineLogLevel.INFO,
            DIAG_CATEGORY,
            "repaired agent=$agentName kind=$kind",
            EngineLogPrivacy.PUBLIC,
        )
    }

    /**
     * Detect chat-template token leakage. The Swift `LlamaCppService` streaming path
     * strips `<|im_end|>` before emission, so this primarily catches non-streaming
     * backends where the raw string may still contain template tokens.
     */
    private fun logChatTemplateLeakage(raw: String) {
        if (raw.contains("<|im_start|>")) {
            logger.log(
                EngineLogLevel.WARNING,
                LOG_CATEGORY,
                "Model hallucinated past its turn — continuation truncated at <|im_end|>",
                EngineLogPrivacy.PUBLIC,
            )
        } else if (raw.contains("<|im_end|>")) {
            logger.log(
                EngineLogLevel.DEBUG,
                LOG_CATEGORY,
                "Trailing <|im_end|> token stripped from output",
                EngineLogPrivacy.PUBLIC,
            )
        }
    }

    /**
     * Emit the empty-fields DEBUG diagnostic. `.private`: [fields] carries agent
     * output, so the whole line is redacted off-device (a `.debug` line isn't
     * persisted in Release anyway; this errs toward more redaction, never less).
     */
    private fun logEmptyFields(fields: Map<String, String>, attempt: Int) {
        logger.log(
            EngineLogLevel.DEBUG,
            LOG_CATEGORY,
            "Empty fields detected (attempt ${attempt + 1}/${MAX_RETRIES + 1}): fields=$fields",
            EngineLogPrivacy.PRIVATE,
        )
    }

    /**
     * Emit a `StreamingDiag` `langCheckSkipped` line. Field order
     * `agent=… reason=…` matches the `retryCause` / `repaired` conventions (agent
     * first; trailing key is the classification). Consumed by the analyzer.
     */
    private fun emitLangCheckSkipped(agentName: String, reason: String) {
        logger.log(
            EngineLogLevel.INFO,
            DIAG_CATEGORY,
            "langCheckSkipped agent=$agentName reason=$reason",
            EngineLogPrivacy.PUBLIC,
        )
    }
}
