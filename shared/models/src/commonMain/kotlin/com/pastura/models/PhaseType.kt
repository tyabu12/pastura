package com.pastura.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * The type of a simulation phase, determining how it is processed.
 *
 * LLM phases ([SPEAK_ALL], [SPEAK_EACH], [VOTE], [CHOOSE]) require LLM inference.
 * Code phases ([SCORE_CALC], [ASSIGN], [ELIMINATE], [SUMMARIZE], [EVENT_INJECT])
 * are processed deterministically by the engine. [CONDITIONAL] is a
 * control-flow phase: the handler itself does no inference, but its
 * sub-phases may be of any type.
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
    EVENT_INJECT;

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
     */
    public val requiresLLM: Boolean
        get() = when (this) {
            SPEAK_ALL, SPEAK_EACH, VOTE, CHOOSE -> true
            SCORE_CALC, ASSIGN, ELIMINATE, SUMMARIZE, CONDITIONAL, EVENT_INJECT -> false
        }
}
