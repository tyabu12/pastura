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
 * serialized data type. Its Swift↔Kotlin parity is behavioural (see
 * `ScenarioConventionsTests`), since golden JSON has nothing to encode here.
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

    /**
     * Returns the private-thought (secondary) output field name expected on
     * `output:` for the given LLM phase, or `null` for code phases.
     *
     * Vote returns `"reason"`; `reflect` returns `null` (its canonical `note`
     * output *is* the private reasoning, so it authors a single-field `{ note }`
     * schema with no separate thought field); every other LLM phase returns
     * `"inner_thought"`. Phase-aware, not a blind `inner_thought` fallback, so a
     * stray `reason` on a speak/choose output never leaks into THINKING and a
     * vote's `reason` is never dropped. Mirrors Swift
     * `ScenarioConventions.thoughtField(for:)` (#760).
     */
    public fun thoughtField(phaseType: PhaseType): String? = when (phaseType) {
        PhaseType.VOTE -> "reason"
        PhaseType.SPEAK_ALL, PhaseType.SPEAK_EACH, PhaseType.CHOOSE, PhaseType.WHISPER ->
            "inner_thought"
        // reflect's canonical `note` output is itself the private reasoning;
        // narrate is a single-field Engine-fixed `{ commentary }` schema — both
        // declare no secondary thought field.
        PhaseType.REFLECT, PhaseType.SCORE_CALC, PhaseType.ASSIGN, PhaseType.ELIMINATE,
        PhaseType.SUMMARIZE, PhaseType.CONDITIONAL, PhaseType.EVENT_INJECT,
        PhaseType.RELATIONSHIP_UPDATE, PhaseType.NARRATE -> null
    }

    /**
     * Decorates a raw primary value for display. Vote prefixes the `→ ` arrow
     * affordance (`→ <voted>`); all other phases return the value unchanged.
     * Single source of truth for the vote arrow so the live-streaming and
     * committed / export paths render identically. Mirrors Swift
     * `ScenarioConventions.decoratePrimary(_:for:)`.
     */
    public fun decoratePrimary(value: String, phaseType: PhaseType): String =
        if (phaseType == PhaseType.VOTE) "→ $value" else value

    /**
     * Returns `true` if `name` is a valid scenario `output:` field name.
     *
     * Rule: non-empty, first character an ASCII letter (`[A-Za-z]`), every
     * subsequent character an ASCII letter, digit, or underscore
     * (`[A-Za-z0-9_]`). Output field names are emitted verbatim as JSON-key
     * literals into every LLM-phase GBNF grammar; a non-ASCII / multi-byte key
     * crashes llama.cpp's sampler at accept-time on-device (the "empty grammar
     * stack" SIGABRT, #599/#607), so ASCII-only is the durable boundary.
     *
     * Mirrors Swift `ScenarioConventions.isValidFieldName(_:)`. The ASCII checks
     * are explicit `Char` ranges, **not** Kotlin's `Char.isLetter()` /
     * `isDigit()`, which are Unicode-true and would accept `あ` / `é` / fullwidth
     * digits — the exact keys this gate exists to reject (Swift gates both the
     * first-char and subsequent-char branches with `isASCII`).
     */
    public fun isValidFieldName(name: String): Boolean {
        val first = name.firstOrNull() ?: return false
        if (!first.isAsciiLetter()) return false
        return name.all { it.isAsciiLetter() || it.isAsciiDigit() || it == '_' }
    }

    private fun Char.isAsciiLetter(): Boolean = this in 'a'..'z' || this in 'A'..'Z'

    private fun Char.isAsciiDigit(): Boolean = this in '0'..'9'
}
