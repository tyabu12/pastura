package com.pastura.models

/**
 * Naming conventions for scenario authoring.
 *
 * LLM phases each have a single canonical primary output field that the
 * engine and UI key on:
 *
 * | Phase | Canonical primary field |
 * |-------|-------------------------|
 * | [PhaseType.SPEAK_ALL], [PhaseType.SPEAK_EACH] | `statement` |
 * | [PhaseType.CHOOSE] | `action` |
 * | [PhaseType.VOTE] | `vote` |
 *
 * Speak phases route the canonical field's value into the conversation log
 * and into the agent's primary display text. Choose binds the canonical
 * field to a constrained output schema and reads it back directly in the
 * choose handler. Vote is similarly read directly by the vote handler.
 *
 * Code phases ([PhaseType.SCORE_CALC], [PhaseType.ASSIGN],
 * [PhaseType.ELIMINATE], [PhaseType.SUMMARIZE], [PhaseType.CONDITIONAL],
 * [PhaseType.EVENT_INJECT]) emit no LLM output and therefore have no
 * primary field — [primaryField] returns `null`.
 *
 * This convention is enforced at scenario-commit time by
 * `ScenarioValidator.validateForCommit`; it is not re-checked at
 * run-time because `SimulationRunner` accepts already-persisted scenarios
 * as-is.
 *
 * Kotlin port of `Pastura/Pastura/Models/ScenarioConventions.swift`.
 * Not `@Serializable` — this is a namespace of pure functions, not a
 * serialized data type.
 */
public object ScenarioConventions {
    /**
     * Returns the canonical primary output field name expected on `output:`
     * for the given phase type, or `null` for code phases that emit no LLM
     * output.
     *
     * Speak phases return `"statement"`, choose returns `"action"`, vote
     * returns `"vote"`. All other phase types return `null`.
     */
    public fun primaryField(phaseType: PhaseType): String? = when (phaseType) {
        PhaseType.SPEAK_ALL, PhaseType.SPEAK_EACH -> "statement"
        PhaseType.CHOOSE -> "action"
        PhaseType.VOTE -> "vote"
        PhaseType.SCORE_CALC,
        PhaseType.ASSIGN,
        PhaseType.ELIMINATE,
        PhaseType.SUMMARIZE,
        PhaseType.CONDITIONAL,
        PhaseType.EVENT_INJECT -> null
    }
}
