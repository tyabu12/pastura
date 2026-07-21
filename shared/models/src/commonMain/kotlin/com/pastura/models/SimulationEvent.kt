package com.pastura.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Events emitted by Pastura's simulation runner.
 *
 * The Swift original is `enum SimulationEvent` — the contract between
 * Engine, App, and Views layers. The App/ViewModel layer consumes these
 * events to update UI state and persist turn records to the database.
 *
 * Kotlin port of `Pastura/Pastura/Models/SimulationEvent.swift`.
 *
 * **Wire shape divergence from Swift:**
 * Swift's `enum SimulationEvent: Codable` uses auto-synthesized
 * enum-with-associated-values Codable (roughly:
 * `{"<caseName>": {"<param>": value}}` per case). The Kotlin port uses
 * kotlinx.serialization's default sealed-class polymorphism, which emits
 * `{"type": "<caseName>", "<param>": value}` (single discriminator key).
 *
 * This divergence is intentional and safe for the spike: `SimulationEvent`
 * is **not** JSON-roundtripped in production — it is delivered via Swift
 * `AsyncStream` and consumed in-memory by the App layer. The `Codable`
 * conformance exists for `Equatable` + `Sendable` protocol consistency and
 * test fixture support, NOT as a cross-language wire-shape contract. If
 * PR-B canonicalizer needs cross-language equivalence for this type, a
 * custom KSerializer can align the tagging at that time. The cross-language
 * semantic invariants (case names + payload shapes) hold.
 *
 * **Case-naming convention:** Kotlin subclass names use PascalCase (Kotlin
 * idiom). The wire discriminator value is the Swift case name (camelCase)
 * via `@SerialName`, so the JSON tag matches Swift's case identifier.
 */
@Serializable
public sealed class SimulationEvent {

    // MARK: - Round Lifecycle

    /** A new round has started. */
    @Serializable
    @SerialName("roundStarted")
    public data class RoundStarted(
        public val round: Int,
        public val totalRounds: Int,
    ) : SimulationEvent()

    /** A round has completed with current scores. */
    @Serializable
    @SerialName("roundCompleted")
    public data class RoundCompleted(
        public val round: Int,
        public val scores: Map<String, Int>,
    ) : SimulationEvent()

    // MARK: - Phase Lifecycle

    /**
     * A phase is about to begin execution.
     *
     * [phasePath] uniquely identifies the phase's position in the scenario.
     * Top-level phase K has path `[K]`; a sub-phase at index N inside a
     * conditional at top-level K has path `[K, N]`. The list form lets
     * future phase types reuse the same identifier shape.
     */
    @Serializable
    @SerialName("phaseStarted")
    public data class PhaseStarted(
        public val phaseType: PhaseType,
        public val phasePath: List<Int>,
    ) : SimulationEvent()

    /** A phase has finished execution. See [PhaseStarted] for `phasePath` semantics. */
    @Serializable
    @SerialName("phaseCompleted")
    public data class PhaseCompleted(
        public val phaseType: PhaseType,
        public val phasePath: List<Int>,
    ) : SimulationEvent()

    // MARK: - Agent Outputs (LLM Phases)

    /** An agent produced output from an LLM phase. */
    @Serializable
    @SerialName("agentOutput")
    public data class AgentOutput(
        public val agent: String,
        public val output: TurnOutput,
        public val phaseType: PhaseType,
    ) : SimulationEvent()

    /**
     * Incremental snapshot of an agent's in-flight LLM output.
     *
     * Emitted during token-by-token streaming. Carries the best-effort
     * partial primary value (e.g., `statement`) and optional
     * `inner_thought` extracted from the model's still-arriving JSON.
     *
     * Semantics:
     * - Replaces — not appends to — the agent's current stream snapshot.
     * - [primary] is null until the primary key's opening quote arrives.
     * - On retry / suspend re-issue, a new snapshot overwrites naturally.
     * - [AgentOutput] still fires exactly once at stream end with the
     *   final parsed [TurnOutput]; canonical readers consume that event.
     */
    @Serializable
    @SerialName("agentOutputStream")
    public data class AgentOutputStream(
        public val agent: String,
        public val primary: String? = null,
        public val thought: String? = null,
    ) : SimulationEvent()

    // MARK: - Code Phase Results

    /** Scores have been updated (from `score_calc` phase). */
    @Serializable
    @SerialName("scoreUpdate")
    public data class ScoreUpdate(public val scores: Map<String, Int>) : SimulationEvent()

    /** An agent has been eliminated (from `eliminate` phase). */
    @Serializable
    @SerialName("elimination")
    public data class Elimination(
        public val agent: String,
        public val voteCount: Int,
    ) : SimulationEvent()

    /** Data has been assigned to an agent (from `assign` phase). */
    @Serializable
    @SerialName("assignment")
    public data class Assignment(
        public val agent: String,
        public val value: String,
    ) : SimulationEvent()

    /**
     * The same shared value was assigned to *every* agent (from an `assign`
     * phase with `target: all`, e.g. the round's お題). Emitted once per round
     * with no agent attribution, so consumers render a single topic line rather
     * than N identical [Assignment] lines. Distinct from the per-agent
     * [Assignment] (word wolf, `target: random_one`), which stays one event per
     * agent because each agent gets a different secret. See #939.
     */
    @Serializable
    @SerialName("sharedAssignment")
    public data class SharedAssignment(public val value: String) : SimulationEvent()

    /** A summary text was generated (from `summarize` phase). */
    @Serializable
    @SerialName("summary")
    public data class Summary(public val text: String) : SimulationEvent()

    /**
     * Live commentary generated by a `narrate` phase (#909).
     *
     * A single LLM inference per round narrates the round's highlight. Distinct
     * from [Summary] (deterministic template / scoring text): it is free LLM
     * prose about the agents, so consumers MUST run it through `ContentFilter`
     * before display (ADR-005), and it carries no agent attribution (the
     * narrator is not a participant). Persisted via
     * `CodePhaseEventPayload.Narration`.
     */
    @Serializable
    @SerialName("narration")
    public data class Narration(public val text: String) : SimulationEvent()

    /**
     * The per-agent affinity matrix was updated (from a `relationship_update`
     * phase). `relationships[perceiver][other]` is the accumulated affinity
     * `perceiver` holds toward `other` (positive = warmth, negative =
     * wariness). This is the raw matrix — not the natural-language summary
     * injected into prompts — so a relationship-graph visualization can consume
     * it directly. Emitted once per phase invocation. See #910.
     */
    @Serializable
    @SerialName("relationshipUpdate")
    public data class RelationshipUpdate(
        public val relationships: Map<String, Map<String, Int>>,
    ) : SimulationEvent()

    // MARK: - Vote Results

    /**
     * Vote results after a `vote` phase completes.
     *
     * @property votes   voter name → voted-for name
     * @property tallies candidate → count
     */
    @Serializable
    @SerialName("voteResults")
    public data class VoteResults(
        public val votes: Map<String, String>,
        public val tallies: Map<String, Int>,
    ) : SimulationEvent()

    // MARK: - Pairing Results

    /** Result of a paired interaction in a `choose` phase with round-robin pairing. */
    @Serializable
    @SerialName("pairingResult")
    public data class PairingResult(
        public val agent1: String,
        public val action1: String,
        public val agent2: String,
        public val action2: String,
    ) : SimulationEvent()

    // MARK: - Conditional Evaluation

    /**
     * A `conditional` phase evaluated its condition expression.
     *
     * Emitted once per conditional invocation, immediately before the
     * selected branch's sub-phases begin. The surrounding
     * [PhaseStarted] / [PhaseCompleted] events (carrying the conditional's
     * own `phasePath`) bracket the whole evaluation + branch execution;
     * nested sub-phase events carry `[K, N]` paths.
     */
    @Serializable
    @SerialName("conditionalEvaluated")
    public data class ConditionalEvaluated(
        public val condition: String,
        public val result: Boolean,
    ) : SimulationEvent()

    // MARK: - Event Injection

    /**
     * An `event_inject` phase rolled its probability and either selected a
     * random event string from `extraData` ([event] non-null) or missed
     * ([event] null).
     *
     * Emitted exactly once per `event_inject` invocation regardless of
     * outcome. Consumers treat `null` as "rolled and lost" — the variable
     * itself is still set to the empty string so prompt expansion stays
     * well-defined.
     */
    @Serializable
    @SerialName("eventInjected")
    public data class EventInjected(public val event: String? = null) : SimulationEvent()

    // MARK: - Simulation Lifecycle

    /** The simulation has completed all rounds successfully. */
    @Serializable
    @SerialName("simulationCompleted")
    public object SimulationCompleted : SimulationEvent()

    /**
     * A resumable snapshot of the full simulation state, emitted at each round
     * boundary (after the round completes).
     *
     * The carried `state.currentRound` is the last *completed* round — the App
     * layer persists this so a paused run can resume from `currentRound + 1`
     * (round-boundary continuation; partial progress within the next,
     * interrupted round is discarded and re-run). Emitted only by the
     * simulation runner; handlers must not emit this event directly.
     *
     * **Why this is in the ADR-023 §6 Stage-2 gate slice.** It carries
     * [SimulationState] — nested maps of [TurnOutput] and lists of
     * [ConversationEntry] — making it the fattest single payload the §5.1 event
     * boundary relays. Gate measurement (iii) re-measures the K/N shim budget on
     * the Engine-consuming surface precisely because the #220 spike exercised
     * only 8 of 21 Models types (ADR-004 §9.3 Q9), so omitting the heaviest
     * crossing would under-sample the measurement and bias a GO optimistic.
     *
     * **Known payload gap:** Kotlin [SimulationState] still lacks Swift's
     * `drawnEvents` (see its own doc). Not on the speak_all path — no event_inject
     * phase runs in the slice — so it stays empty at gate runtime; tracked in the
     * #501 drift ledger for Stage 3.
     *
     * Swift original: `Pastura/Pastura/Models/SimulationEvent.swift`.
     */
    @Serializable
    @SerialName("roundCheckpoint")
    public data class RoundCheckpoint(
        public val state: SimulationState,
    ) : SimulationEvent()

    /**
     * The simulation has been paused at the given position.
     *
     * Emitted only by the simulation runner; handlers must not emit
     * this event directly.
     */
    @Serializable
    @SerialName("simulationPaused")
    public data class SimulationPaused(
        public val round: Int,
        public val phasePath: List<Int>,
    ) : SimulationEvent()

    /**
     * An error occurred during simulation execution.
     *
     * Named `ErrorEvent` (not `Error`) to avoid shadowing `kotlin.Error`
     * for callers that import this nested class directly. The wire
     * discriminator is still `"error"` via [SerialName].
     */
    @Serializable
    @SerialName("error")
    public data class ErrorEvent(public val error: SimulationError) : SimulationEvent()

    // MARK: - Progress (UI Feedback)

    /** LLM inference has started for an agent. */
    @Serializable
    @SerialName("inferenceStarted")
    public data class InferenceStarted(public val agent: String) : SimulationEvent()

    /**
     * LLM inference has completed for an agent with timing + optional token info.
     *
     * [tokenCount] is null when the backend did not report completion tokens
     * (e.g., Ollama without `usage` metadata). Consumers computing tok/s
     * must treat null as "unknown" rather than substituting zero.
     */
    @Serializable
    @SerialName("inferenceCompleted")
    public data class InferenceCompleted(
        public val agent: String,
        public val durationSeconds: Double,
        public val tokenCount: Int? = null,
    ) : SimulationEvent()

    // MARK: - Language Adherence (ADR-010 Step E PR2)

    /**
     * LLM output language did not match `scenario.engineLanguage` after the
     * retry budget was exhausted (ADR-010 Step E PR2).
     *
     * Unlike [ErrorEvent], this is informational — the parse result is
     * still delivered via [AgentOutput] and the simulation continues.
     *
     * @property agent    The agent whose output was flagged.
     * @property detected The ISO 639-1 lowercase code returned by the
     *                    language detector, or null if no confident
     *                    classification was returned (e.g., output was
     *                    mostly punctuation / very short).
     * @property expected `scenario.engineLanguage` at call time —
     *                    usually `"ja"` or `"en"` per ADR-010 D1.
     */
    @Serializable
    @SerialName("languageMismatch")
    public data class LanguageMismatch(
        public val agent: String,
        public val detected: String? = null,
        public val expected: String,
    ) : SimulationEvent()

    // MARK: - Turn Degradation (ADR-021)

    /**
     * A turn's LLM call failed transiently after the retry budget was exhausted,
     * and the turn was skipped rather than aborting the run (ADR-021 D1/D2 —
     * "degrade by omission"). Informational, not an [ErrorEvent]: the phase
     * continues with the remaining agents/pairs. Live-only in the App layer
     * (replay no-ops it). [cause] is a diagnostic English description of the
     * failure, not user-facing copy.
     */
    @Serializable
    @SerialName("turnSkipped")
    public data class TurnSkipped(
        public val agent: String,
        public val phaseType: PhaseType,
        public val cause: String,
    ) : SimulationEvent()

    /**
     * A `choose` (round-robin) agent's LLM call **succeeded** but delivered an
     * action outside the phase's option set that no normalization could map back
     * (ADR-021 § Amendment 2026-07-17 / #1151). The engine drops the whole
     * pairing and emits this rather than fabricating a decision the agent did not
     * make. Distinct from [TurnSkipped]: the turn did **not** skip — the call
     * succeeded and [AgentOutput] already rendered the utterance. Folds into the
     * same `degradedTurnCount` badge as [TurnSkipped]; does **not** feed the D4
     * breaker. [raw] is model content — UI consumers MUST route it through
     * `ContentFilter` before display (ADR-005).
     */
    @Serializable
    @SerialName("actionRejected")
    public data class ActionRejected(
        public val agent: String,
        public val phaseType: PhaseType,
        public val raw: String,
    ) : SimulationEvent()

    /**
     * Whether no further event follows this one, per `SimulationEngine.run`'s
     * contract.
     *
     * Declared here — once, on the type — rather than as a predicate at each
     * consumer. A consumer-side `is SimulationCompleted || is ErrorEvent`
     * chain is invisible to ADR-022's no-default gate, which reaches `when` /
     * `switch` projections but not `is` / `==` predicates (ADR-027 records the
     * same carve-out for `==`). The gate spike's `SharedEngineRunner` had
     * exactly that shape: a new terminal case would have left its
     * reconstructed `AsyncStream` never finishing, with nothing red.
     *
     * The `when` below is an expression over a sealed class with no `else`, so
     * the compiler rejects it the moment a subclass is added — and
     * `:shared:models:jvmTest` runs on every PR that touches `shared/`, which
     * a new subclass necessarily does, so that rejection is a per-PR gate
     * rather than a nightly one. (The job is path-gated, not unconditional —
     * the guarantee holds because the gate's trigger and the change that
     * needs gating are the same edit.)
     *
     * Enumerated exhaustively on purpose: an `else -> false` would restore the
     * silent-default this exists to remove.
     */
    public val isTerminal: Boolean
        get() = when (this) {
            is SimulationCompleted -> true
            is ErrorEvent -> true
            is RoundStarted -> false
            is RoundCompleted -> false
            is PhaseStarted -> false
            is PhaseCompleted -> false
            is AgentOutput -> false
            is AgentOutputStream -> false
            is ScoreUpdate -> false
            is Elimination -> false
            is Assignment -> false
            is Summary -> false
            is VoteResults -> false
            is PairingResult -> false
            is ConditionalEvaluated -> false
            is EventInjected -> false
            is RoundCheckpoint -> false
            is SimulationPaused -> false
            is InferenceStarted -> false
            is InferenceCompleted -> false
            is LanguageMismatch -> false
            is SharedAssignment -> false
            is Narration -> false
            is RelationshipUpdate -> false
            is TurnSkipped -> false
            is ActionRejected -> false
        }
}

/**
 * Errors that can occur during simulation execution.
 *
 * Co-located with [SimulationEvent] (matches Swift's file layout) because
 * the event's [SimulationEvent.ErrorEvent] case references this type.
 *
 * Kotlin port of `Pastura/Pastura/Models/SimulationEvent.swift:SimulationError`.
 *
 * **Divergence from Swift:** Swift's `SimulationError` conforms to `Error`
 * + `LocalizedError` and provides per-case `errorDescription` strings
 * wrapped in `String(localized:)` for i18n. The Kotlin port omits the
 * LocalizedError extension entirely — Models layer carries only the wire
 * shape; i18n is an App/UI concern handled by Swift's
 * `Localizable.xcstrings` in PR's current Swift form. If/when KMP Engine
 * needs to throw these, the Engine port (W3+) can wrap them in a Kotlin
 * `Throwable` subclass at that layer.
 *
 * **Wire shape:** sealed class polymorphism per kotlinx default
 * (`{"type":"<caseName>",...payload}`); same divergence note as
 * [SimulationEvent].
 */
@Serializable
public sealed class SimulationError {
    /** The scenario definition failed validation. */
    @Serializable
    @SerialName("scenarioValidationFailed")
    public data class ScenarioValidationFailed(public val message: String) : SimulationError()

    /**
     * The LLM backend failed to generate a response.
     *
     * Stores the description as a String (not the original Throwable) so the
     * type remains Sendable / Equatable / Serializable — matches Swift's
     * `case llmGenerationFailed(description: String)`.
     */
    @Serializable
    @SerialName("llmGenerationFailed")
    public data class LlmGenerationFailed(public val description: String) : SimulationError()

    /** The LLM response could not be parsed as valid JSON. */
    @Serializable
    @SerialName("jsonParseFailed")
    public data class JsonParseFailed(public val raw: String) : SimulationError()

    /** All retry attempts for LLM inference were exhausted. */
    @Serializable
    @SerialName("retriesExhausted")
    public object RetriesExhausted : SimulationError()

    /** The LLM model is not loaded. */
    @Serializable
    @SerialName("modelNotLoaded")
    public object ModelNotLoaded : SimulationError()

    /** The simulation was cancelled. */
    @Serializable
    @SerialName("cancelled")
    public object Cancelled : SimulationError()

    /**
     * The ADR-021 D4 circuit breaker tripped: [consecutiveCount] consecutive
     * turns were skipped (see [SimulationEvent.TurnSkipped]) without an
     * intervening successful turn. Thrown by the turn-degradation gate in place
     * of another skip, surfacing through the abort path so a systemically-dead
     * backend does not grind through the rest of the run.
     */
    @Serializable
    @SerialName("turnFailureLimitReached")
    public data class TurnFailureLimitReached(
        public val consecutiveCount: Int,
    ) : SimulationError()
}
