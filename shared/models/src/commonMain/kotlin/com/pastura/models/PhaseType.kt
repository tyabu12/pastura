package com.pastura.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * The type of a simulation phase, determining how it is processed.
 *
 * LLM phases ([SPEAK_ALL], [SPEAK_EACH], [VOTE], [CHOOSE], [REFLECT], [WHISPER])
 * require LLM inference. Code phases ([SCORE_CALC], [ASSIGN], [ELIMINATE],
 * [SUMMARIZE], [EVENT_INJECT], [RELATIONSHIP_UPDATE]) are processed
 * deterministically by the engine. [CONDITIONAL] is a control-flow phase: the
 * handler itself does no inference, but its sub-phases may be of any type.
 *
 * Kotlin port of `Pastura/Pastura/Models/PhaseType.swift`.
 */
@Serializable
public enum class PhaseType {
    /** Agent produces a spoken statement visible to all. */
    @SerialName("speak_all")
    SPEAK_ALL,

    /** Each agent speaks in turn. */
    @SerialName("speak_each")
    SPEAK_EACH,

    /** Agents cast votes. */
    @SerialName("vote")
    VOTE,

    /** Agent chooses an action from a constrained set. */
    @SerialName("choose")
    CHOOSE,

    /**
     * Each agent privately updates a short note about the situation via LLM
     * inference (canonical `note` output field).
     */
    @SerialName("reflect")
    REFLECT,

    /**
     * Pairs of active agents privately exchange statements, hidden from other
     * agents' prompts — each utterance is one LLM inference.
     */
    @SerialName("whisper")
    WHISPER,

    /** Runs a built-in scoring logic against simulation state. */
    @SerialName("score_calc")
    SCORE_CALC,

    /** Assigns values from a source list to agents. */
    @SerialName("assign")
    ASSIGN,

    /** Eliminates agents from further participation. */
    @SerialName("eliminate")
    ELIMINATE,

    /**
     * Formats a round summary by expanding a template with state variables —
     * deterministic, no LLM call. Per-pairing expansion if pairings exist and
     * the template contains `{agent1}`.
     */
    @SerialName("summarize")
    SUMMARIZE,

    /**
     * Control-flow branch: evaluates a DSL condition and dispatches to
     * sub-phases — no LLM call is made by the conditional itself.
     */
    @SerialName("conditional")
    CONDITIONAL,

    /**
     * Injects a random string from scenario `extraData` into simulation
     * variables — no LLM call.
     */
    @SerialName("event_inject")
    EVENT_INJECT,

    /**
     * Deterministically updates a per-agent affinity matrix from vote / choose
     * history and injects a natural-language summary — no LLM call (#910).
     */
    @SerialName("relationship_update")
    RELATIONSHIP_UPDATE,

    /**
     * A commentator persona narrates the round's highlight via a single LLM
     * inference per round (canonical `commentary` output) — not a participant,
     * so cost is one inference per round regardless of agent count (#909).
     */
    @SerialName("narrate")
    NARRATE;

    /**
     * Whether this phase type requires LLM inference.
     *
     * [CONDITIONAL] returns `false` because the handler evaluates a DSL
     * expression and dispatches to sub-phases — no LLM call is made by the
     * conditional itself. The sub-phases' [requiresLLM] determines whether
     * the enclosing branch requires inference; consumers that need the
     * effective LLM cost of a conditional must walk `thenPhases` / `elsePhases`
     * (see `ScenarioLoader.estimateInferenceCount`).
     *
     * [EVENT_INJECT] returns `false`: the handler picks a random string from
     * scenario `extraData` and writes it into `state.variables` — no LLM
     * call. Subsequent prompt phases reference the injected value via the
     * `as:` variable name (default `current_event`).
     *
     * [REFLECT] returns `true`: each agent runs an LLM inference to privately
     * update a short note about the situation (canonical `note` output field),
     * so it costs one inference per agent per round like [SPEAK_ALL] / [VOTE].
     *
     * [WHISPER] returns `true`: pairs of active agents privately exchange
     * statements (hidden from other agents' prompts), each utterance costing
     * one LLM inference.
     *
     * [RELATIONSHIP_UPDATE] returns `false`: the handler deterministically
     * updates a per-agent affinity matrix from vote / choose history and
     * injects a natural-language summary — no LLM call (#910).
     *
     * [NARRATE] returns `true`: a single LLM inference per round makes a
     * commentator persona narrate the round's highlight (canonical `commentary`
     * output). Unlike the per-agent LLM phases it costs exactly one inference
     * per round regardless of agent count — the narrator is not a participant
     * (#909).
     */
    public val requiresLLM: Boolean
        get() = when (this) {
            SPEAK_ALL, SPEAK_EACH, VOTE, CHOOSE, REFLECT, WHISPER, NARRATE -> true
            SCORE_CALC, ASSIGN, ELIMINATE, SUMMARIZE, CONDITIONAL, EVENT_INJECT,
            RELATIONSHIP_UPDATE -> false
        }
}
