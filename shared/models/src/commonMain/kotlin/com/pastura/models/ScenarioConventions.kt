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
 * | [PhaseType.REFLECT] | `note` |
 *
 * Speak phases route the canonical field's value into the conversation log
 * and into the agent's primary display text. Choose binds the canonical
 * field to a constrained output schema and reads it back directly in the
 * choose handler. Vote is similarly read directly by the vote handler.
 * [PhaseType.WHISPER] reuses the `statement` field (a private utterance).
 *
 * Code phases ([PhaseType.SCORE_CALC], [PhaseType.ASSIGN],
 * [PhaseType.ELIMINATE], [PhaseType.SUMMARIZE], [PhaseType.CONDITIONAL],
 * [PhaseType.EVENT_INJECT], [PhaseType.RELATIONSHIP_UPDATE]) emit no LLM
 * output and therefore have no primary field — [primaryField] returns `null`.
 * [PhaseType.NARRATE] is an LLM phase but its output shape is Engine-fixed
 * (a single `commentary` schema), not author-declared, so it too returns `null`.
 *
 * This convention is enforced at scenario-commit time by
 * `ScenarioValidator.validateForCommit`; it is not re-checked at
 * run-time because `SimulationRunner` accepts already-persisted scenarios
 * as-is.
 *
 * Kotlin port of `Pastura/Pastura/Models/ScenarioConventions.swift`.
 * Not `@Serializable` — this is a namespace of pure functions, not a
 * serialized data type. Only [primaryField] is ported so far; the Swift
 * original's `thoughtField` / `decoratePrimary` / `isValidFieldName` are
 * deferred (ADR-023 PR0-b).
 */
public object ScenarioConventions {
    /**
     * Returns the canonical primary output field name expected on `output:`
     * for the given phase type, or `null` for code phases that emit no LLM
     * output.
     *
     * Speak phases return `"statement"`, choose returns `"action"`, vote
     * returns `"vote"`, reflect returns `"note"`, whisper returns `"statement"`.
     * All other phase types return `null`.
     */
    public fun primaryField(phaseType: PhaseType): String? = when (phaseType) {
        PhaseType.SPEAK_ALL, PhaseType.SPEAK_EACH -> "statement"
        PhaseType.CHOOSE -> "action"
        PhaseType.VOTE -> "vote"
        PhaseType.REFLECT -> "note"
        PhaseType.WHISPER -> "statement"
        // NARRATE is an LLM phase, but its output shape is Engine-fixed (a
        // single `commentary` schema built by the narrate handler), not
        // author-declared — so there is no canonical author `output:` field to
        // enforce. Returning null keeps validateForCommit's canonical-field
        // check off narrate. (Mirrors Swift ScenarioConventions.primaryField.)
        PhaseType.SCORE_CALC,
        PhaseType.ASSIGN,
        PhaseType.ELIMINATE,
        PhaseType.SUMMARIZE,
        PhaseType.CONDITIONAL,
        PhaseType.EVENT_INJECT,
        PhaseType.RELATIONSHIP_UPDATE,
        PhaseType.NARRATE -> null
    }
}
