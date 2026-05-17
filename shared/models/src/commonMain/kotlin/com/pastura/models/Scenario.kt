package com.pastura.models

import kotlinx.serialization.Serializable

/**
 * A complete scenario definition parsed from YAML.
 *
 * This is the pure domain model representing a scenario's structure.
 * It does not include persistence metadata (id, isPreset, timestamps) —
 * those belong to `ScenarioRecord` in the Data layer.
 *
 * Scenarios are parsed from YAML via `ScenarioLoader` in the Engine layer
 * using manual mapping (`Yams.load()` → `[String: Any]`).
 *
 * Kotlin port of `Pastura/Pastura/Models/Scenario.swift`.
 *
 * **Wire-key convention:** kotlinx.serialization emits Kotlin property
 * names as JSON keys (camelCase), matching Swift `Codable`'s default
 * `keyEncodingStrategy = .useDefaultKeys`. The snake_case keys in preset
 * YAML (`simulation_language`, `agent_count`, `extra_data`) are consumed
 * by Swift's `ScenarioLoader` via manual mapping, NOT through `Scenario`'s
 * `Codable` conformance — so the Kotlin port matches Swift's JSON wire
 * shape, not its YAML preset shape.
 *
 * @property id               Unique identifier for the scenario (from YAML `id` field).
 * @property name             Human-readable scenario name.
 * @property description      Brief description of what this scenario simulates.
 * @property language         Scenario authoring language: ISO 639-1 lowercase code (`"ja"` or `"en"`).
 *                            Drives Engine output language at runtime (prompt templates, scoring
 *                            summaries, handler default fallbacks) via per-site `when` dispatch.
 *                            Validator enforces `{ja, en}` at load time; absence is rejected by
 *                            `ScenarioLoader` (no backward-compat fill). See ADR-010 D1 / D7.
 * @property simulationLanguage Optional Engine override language for cross-language simulation.
 *                            When non-null, the Engine reads from this instead of [language] —
 *                            enabling "run an `en` scenario on a `ja` device with
 *                            `simulation_language: ja`." Resolved via [engineLanguage] at every
 *                            Engine site; never read directly outside that single resolve point.
 *                            See ADR-010 D5.
 * @property agentCount       Expected number of agents. Must match `personas.size`.
 * @property rounds           Number of rounds to execute.
 * @property context          Shared context injected into every agent's system prompt.
 * @property personas         Agent persona definitions.
 * @property phases           Ordered list of phases executed each round.
 * @property extraData        Scenario-specific data beyond the standard fields. Holds arbitrary
 *                            top-level YAML fields that phase handlers access at runtime. For
 *                            example, bokete's `topics` (string array) or word wolf's `words`
 *                            (array of dictionaries). The `assign` phase references keys here
 *                            via its `source` field. Empty if the scenario has no extra data.
 */
@Serializable
public data class Scenario(
    public val id: String,
    public val name: String,
    public val description: String,
    public val language: String,
    public val simulationLanguage: String? = null,
    public val agentCount: Int,
    public val rounds: Int,
    public val context: String,
    public val personas: List<Persona>,
    public val phases: List<Phase>,
    public val extraData: Map<String, AnyCodableValue> = emptyMap(),
) {
    /**
     * Engine-consumer resolver for cross-language simulation (ADR-010 D6 row 1).
     * Returns [simulationLanguage] when set, falling through to [language] otherwise.
     *
     * **Do not use as a generic resolver.** D6 defines four consumer rows, each with
     * its own resolver:
     *
     * - **Engine** (prompt / scoring / default text): [engineLanguage] (this property)
     * - **New scenario creation seed** (Editor): `LocaleResolver.deviceDefault()`
     * - **Preset / gallery initial selection** (picker): `LocaleResolver.deviceDefault()`
     * - **UI shell** (`Localizable.xcstrings`): `Bundle.main.preferredLocalizations`
     *
     * UI / Editor / Picker callsites **MUST** continue using their own D6 resolvers;
     * reading [engineLanguage] from those layers silently bypasses device-locale priority.
     * Two Engine-adjacent sites also stay on [language] (authoring axis), not
     * [engineLanguage] (runtime axis):
     *
     * - `ScenarioValidator` validates the authoring [language] field.
     * - `ScenarioSerializer` writes the authoring [language] back to YAML.
     *
     * `scripts/check_engine_language_axis.sh` enforces the Engine-side boundary in CI;
     * cross-layer misuse is caught by code review.
     */
    public val engineLanguage: String
        get() = simulationLanguage ?: language

    public companion object {
        /**
         * Accepted values for [language] (D1) and [simulationLanguage] (D5).
         *
         * Single source of truth — both `ScenarioLoader` (YAML path) and
         * `ScenarioValidator` (programmatic-construction path) gate against this set.
         * Adding a third language (Phase 3+) is new-ADR scope per ADR-010 Out-of-Scope;
         * extending this set is the first concrete step but never sufficient on its own.
         */
        public val ACCEPTED_LANGUAGES: Set<String> = setOf("ja", "en")
    }
}
