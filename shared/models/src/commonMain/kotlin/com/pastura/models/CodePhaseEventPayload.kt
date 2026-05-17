package com.pastura.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Serializable payload for a code-phase event persisted in `code_phase_events`.
 *
 * Kotlin port of `Pastura/Pastura/Models/CodePhaseEventPayload.swift`.
 *
 * Mirrors the code-phase cases of [SimulationEvent] for durable storage.
 * The App layer consumes [SimulationEvent]s from the Engine and maps them
 * into this type before writing `payloadJSON`, so the exporter and other
 * consumers can reconstruct per-phase results without replaying events.
 *
 * **Wire shape divergence from Swift (production-relevant):**
 * Unlike [SimulationEvent] which is delivered via AsyncStream and never
 * round-trips JSON in production, `CodePhaseEventPayload` IS persisted —
 * `code_phase_events.payloadJSON` stores Swift's JSONEncoder output. The
 * Swift auto-synth Codable form is `{"<caseName>":{<payload>}}`; the
 * Kotlin port uses kotlinx default sealed-class polymorphism
 * (`{"type":"<caseName>",<payload>}`). If a Kotlin Engine port (W3+)
 * needs to read existing `payloadJSON` rows written by Swift, a custom
 * KSerializer aligning the tagging will be required — flagged for
 * PR-B canonicalizer attention.
 *
 * Wire-format stability per Swift kdoc: adding new cases is
 * backward-compatible (new outer keys are unknown to old decoders, not an
 * issue here since readers ship with producers). Renaming or removing
 * a case requires a data migration that rewrites existing `payloadJSON`
 * rows.
 */
@Serializable
public sealed class CodePhaseEventPayload {
    /** An agent was eliminated as the result of an `eliminate` phase. */
    @Serializable
    @SerialName("elimination")
    public data class Elimination(
        public val agent: String,
        public val voteCount: Int,
    ) : CodePhaseEventPayload()

    /** Scores were updated by a `score_calc` phase. */
    @Serializable
    @SerialName("scoreUpdate")
    public data class ScoreUpdate(public val scores: Map<String, Int>) : CodePhaseEventPayload()

    /**
     * A textual summary was produced by `summarize` or a scoring logic
     * (e.g., `wordwolf_judge` verdicts surface here).
     */
    @Serializable
    @SerialName("summary")
    public data class Summary(public val text: String) : CodePhaseEventPayload()

    /**
     * Voting concluded.
     *
     * @property votes   voter → target
     * @property tallies candidate → received vote count
     */
    @Serializable
    @SerialName("voteResults")
    public data class VoteResults(
        public val votes: Map<String, String>,
        public val tallies: Map<String, Int>,
    ) : CodePhaseEventPayload()

    /** One pair's outcome in a `choose` phase with round-robin pairing. */
    @Serializable
    @SerialName("pairingResult")
    public data class PairingResult(
        public val agent1: String,
        public val action1: String,
        public val agent2: String,
        public val action2: String,
    ) : CodePhaseEventPayload()

    /**
     * A value was assigned to an agent by an `assign` phase
     * (e.g., wolf/villager role in Word Wolf).
     */
    @Serializable
    @SerialName("assignment")
    public data class Assignment(
        public val agent: String,
        public val value: String,
    ) : CodePhaseEventPayload()

    /**
     * An `event_inject` phase rolled its probability and either selected a
     * random event string ([event] non-null) or missed ([event] null).
     *
     * The miss case persists explicitly so past-results timelines can
     * distinguish "phase didn't run" from "phase ran and rolled a miss".
     */
    @Serializable
    @SerialName("eventInjected")
    public data class EventInjected(public val event: String? = null) : CodePhaseEventPayload()
}
