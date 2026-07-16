package com.pastura.models

import kotlinx.serialization.Serializable

/**
 * A single phase definition within a scenario.
 *
 * Each phase describes one step in a simulation round. The available fields
 * depend on the phase's [type] — LLM phases use [prompt] and [outputSchema],
 * while code phases use type-specific fields like [logic] or [template].
 *
 * Kotlin port of `Pastura/Pastura/Models/Phase.swift`.
 *
 * **Wire-key convention:** kotlinx.serialization defaults to the Kotlin
 * property name as the JSON key (camelCase). This matches Swift `Codable`'s
 * default `keyEncodingStrategy = .useDefaultKeys`, so the JSON wire shape
 * lines up across both languages without explicit `@SerialName`. The
 * snake_case keys in preset YAML (`output_schema`, `exclude_self`, etc.)
 * are a separate format consumed by Swift's `ScenarioLoader` via manual
 * mapping — NOT through `Phase`'s `Codable` conformance.
 *
 * **Null-omit divergence from Swift:** kotlinx.serialization omits null fields
 * by default; Swift Codable emits `null`. H2 canonicalizer (W2 PR-B per Q1 (c))
 * normalizes this at comparison time — both sides emit their native shape.
 *
 * @property type          The type of this phase, determining how it is processed.
 * @property prompt        The prompt template sent to the LLM. Supports variable
 *                         expansion (e.g., `{scoreboard}`, `{opponent_name}`).
 *                         Required for LLM phases.
 * @property outputSchema  Expected output field names and their type descriptors
 *                         (e.g., `{"action": "string"}`). Used by `JSONResponseParser`
 *                         to validate LLM output. Required for LLM phases.
 * @property options       Available choices for `choose` phases (e.g., `["cooperate", "betray"]`).
 * @property pairing       Pairing strategy for `choose` phases (e.g., [PairingStrategy.ROUND_ROBIN]).
 * @property logic         Scoring logic identifier for `score_calc` phases.
 * @property template      Format template for `summarize` phases. Supports variable expansion.
 * @property source        Data source key for `assign` phases (e.g., `"topics"`). References a
 *                         top-level field in the scenario definition.
 * @property target        Target specification for `assign` phases. `null` defaults to [AssignTarget.ALL].
 * @property excludeSelf   Whether agents are excluded from voting for themselves in `vote` phases.
 * @property subRounds     Number of sub-rounds for `speak_each` phases. Defaults to 1 if not specified.
 * @property maxSentences  Per-phase soft cap on statement length. `null` uses the global default.
 * @property condition     Boolean condition expression for `conditional` phases.
 *                         Single-comparison primitive (`Identifier(.Identifier)? OP Operand`)
 *                         composed with `&&` / `||` and parenthesized grouping. Precedence:
 *                         comparison > `&&` > `||`, both combinators left-associative.
 *                         Parsed and evaluated by `ConditionEvaluator`.
 * @property thenPhases    Sub-phases executed when [condition] evaluates to true. May be `null`
 *                         (then-branch empty, handler no-ops) or a list of any phase type except
 *                         [PhaseType.CONDITIONAL] itself (depth-1 rule enforced by
 *                         `ScenarioValidator` and `ScenarioLoader`).
 * @property elsePhases    Sub-phases executed when [condition] evaluates to false.
 *                         See [thenPhases] for shape constraints.
 * @property probability   Fire probability for `event_inject` phases, in `[0.0, 1.0]`. `null`
 *                         defaults to `1.0` (always fires). The handler uses strict `<` against
 *                         `Random.nextDouble()`, so `0.0` never fires and `1.0` always fires.
 * @property eventVariable Variable name written by `event_inject` phases (the YAML `as:` key).
 *                         `null` defaults to `"current_event"`. The handler writes the chosen
 *                         event string to `state.variables[eventVariable ?: "current_event"]` so
 *                         subsequent prompt phases can reference it via `{current_event}`.
 */
@Serializable
public data class Phase(
    public val type: PhaseType,
    public val prompt: String? = null,
    public val outputSchema: Map<String, String>? = null,
    public val options: List<String>? = null,
    public val pairing: PairingStrategy? = null,
    public val logic: ScoreCalcLogic? = null,
    public val template: String? = null,
    public val source: String? = null,
    public val target: AssignTarget? = null,
    public val excludeSelf: Boolean? = null,
    public val subRounds: Int? = null,
    /**
     * Per-phase soft cap on the number of sentences in an agent's primary
     * `statement` output (the YAML `max_sentences:` key), overriding the global
     * default of 3 for this phase only.
     *
     * `null` means the phase uses the global default. Applied by `PromptBuilder`
     * as a **prompt-side** brevity rule on the statement field only — it does not
     * constrain `inner_thought`, and code phases (which emit no statement) never
     * surface the rule.
     *
     * Empirically a **ja lever**: a Stage-0 harness A/B (#881) found ja statement
     * length responds bidirectionally to the cap (cap 1/3/6 -> ~1.0/1.4/1.9
     * sentences) while en is near-inert.
     *
     * **The 1..6 range is not enforced here.** Swift's `ScenarioValidator` owns
     * that gate and is a Stage-3 port (ADR-023 §4), so no Kotlin gate rejects an
     * out-of-range value yet — the ported `PromptBuilder` must not assume one.
     * Re-point this note at the Kotlin validator when it lands.
     *
     * Slice-path prerequisite for the ADR-023 §6 Stage-2 gate: `buildAnswerRules`
     * reads it on the speak_all path. Swift original:
     * `Pastura/Pastura/Models/Phase.swift`.
     */
    public val maxSentences: Int? = null,
    public val condition: String? = null,
    public val thenPhases: List<Phase>? = null,
    public val elsePhases: List<Phase>? = null,
    public val probability: Double? = null,
    public val eventVariable: String? = null,
) {
    /**
     * The schema's required keys as a [Set], or an empty set when the phase has no
     * output schema (code phases). Handlers pass this to `JSONResponseParser.parse`
     * via `LLMCaller.call` to enable the A2 schema-aware repair guard (#194).
     *
     * This is NOT a data-class component — it is a derived property getter.
     */
    public val outputSchemaKeys: Set<String>
        get() = outputSchema?.keys?.toSet() ?: emptySet()
}
