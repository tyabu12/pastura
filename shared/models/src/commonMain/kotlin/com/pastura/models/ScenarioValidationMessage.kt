package com.pastura.models

/**
 * A parameter-carrying description of a scenario load / validation failure.
 *
 * Kotlin port of `Pastura/Pastura/Models/ScenarioValidationMessage.swift`,
 * **1:1 across all 53 cases** — the Swift enum is the single source of truth for
 * the set. Each subtype is a portable structured payload (name + typed args);
 * [render] is the single rendering leaf that turns one into a display string.
 *
 * ## What this set covers, and what it does not
 *
 * These 53 cases come from `ScenarioValidator` (+ its extensions) and
 * `ScenarioLoader` **only**. The ADR-024 semantic linter is a *separate* surface
 * with its own 21 messages (Ordering 8 / Config 7 / Conditions 3 /
 * Placeholders 3 — measured against
 * `Pastura/Pastura/Engine/ScenarioSemanticLinter+*.swift`), which are not here
 * and grow this type when `ScenarioSemanticLinter` is ported. Say so up front,
 * because `ScenarioValidationMessageTests` pins the case count at 53: without
 * this note, the linter slice reads that failing pin as a mystery regression
 * rather than as the pin doing its job.
 *
 * ## Landed as infra
 *
 * There is **no Kotlin consumer yet** — `ScenarioValidator` itself is unported
 * (see `DivergenceLedger.DivergenceClass.VALIDATOR_UNPORTED`). This type, and
 * `InferenceEstimator` in `shared/engine`, are the two dependencies that must
 * exist before the validator port can compile. Ported for the ADR-023 §6
 * Stage-3 Engine migration (#501).
 *
 * ## Naming
 *
 * A subtype's name is its Swift case name with the first character uppercased,
 * with **no** other rewriting (so `invalidYAMLFormat` →
 * [InvalidYAMLFormat], not `InvalidYamlFormat`). That keeps the mapping
 * mechanical, which is what lets the commonTest case-set check compare a
 * hand-transcribed Swift name list against this hierarchy without a translation
 * table. Constructor parameter names likewise reuse the Swift argument labels —
 * or, where a Swift case has an unlabelled argument, the name its `localized`
 * switch binds it to (`agentCountBelowMinimum(Int)` → `count`).
 */
public sealed class ScenarioValidationMessage {

    // ── Language membership (shared: ScenarioValidator + ScenarioLoader) ─────

    public data class LanguageNotAccepted(
        public val allowed: String,
        public val got: String,
    ) : ScenarioValidationMessage()

    public data class SimulationLanguageNotAccepted(
        public val allowed: String,
        public val got: String,
    ) : ScenarioValidationMessage()

    public data class SimulationLanguageYAMLNotAccepted(
        public val allowed: String,
        public val got: String,
    ) : ScenarioValidationMessage()

    // ── Execution limits (ScenarioValidator) ────────────────────────────────

    public data class AgentCountBelowMinimum(public val count: Int) : ScenarioValidationMessage()

    public data class AgentCountExceedsMaximum(public val count: Int) : ScenarioValidationMessage()

    public data class PersonaCountMismatch(
        public val personaCount: Int,
        public val agentCount: Int,
    ) : ScenarioValidationMessage()

    public data class RoundCountExceedsMaximum(public val rounds: Int) : ScenarioValidationMessage()

    public data class LogWindowBelowMinimum(public val window: Int) : ScenarioValidationMessage()

    public data class EstimatedInferencesExceedsMaximum(
        public val estimated: Int,
    ) : ScenarioValidationMessage()

    public data class HighInferenceCount(public val estimated: Int) : ScenarioValidationMessage()

    // ── Conditional-phase shape (ScenarioValidator) ─────────────────────────

    public data class ConditionalMissingIf(public val label: String) : ScenarioValidationMessage()

    public data class ConditionalEmptyBranches(
        public val label: String,
    ) : ScenarioValidationMessage()

    public data class NestedConditionalNotAllowed(
        public val label: String,
    ) : ScenarioValidationMessage()

    public data class BranchNestedConditional(
        public val label: String,
    ) : ScenarioValidationMessage()

    public data class BranchReflectNotAllowed(
        public val label: String,
    ) : ScenarioValidationMessage()

    public data class BranchWhisperNotAllowed(
        public val label: String,
    ) : ScenarioValidationMessage()

    public data class BranchRelationshipUpdateNotAllowed(
        public val label: String,
    ) : ScenarioValidationMessage()

    public data class BranchNarrateNotAllowed(
        public val label: String,
    ) : ScenarioValidationMessage()

    // ── Canonical / required output fields ──────────────────────────────────

    public data class RequiresOutputField(
        public val label: String,
        public val type: String,
        public val field: String,
    ) : ScenarioValidationMessage()

    public data class SecondaryFieldMismatch(
        public val label: String,
        public val type: String,
        public val canonical: String,
        public val key: String,
    ) : ScenarioValidationMessage()

    public data class RelationshipUpdateMissingRule(
        public val label: String,
        public val type: String,
    ) : ScenarioValidationMessage()

    // ── Assign-phase source shape ───────────────────────────────────────────

    public data class SourceNotFound(
        public val label: String,
        public val source: String,
    ) : ScenarioValidationMessage()

    public data class AssignSourceGroupedForAll(
        public val label: String,
        public val source: String,
    ) : ScenarioValidationMessage()

    public data class AssignSourceNotGroupedForRandomOne(
        public val label: String,
        public val source: String,
    ) : ScenarioValidationMessage()

    // ── Structural mapping (ScenarioLoader) ─────────────────────────────────

    public object InvalidYAMLFormat : ScenarioValidationMessage()

    public data class MissingRequiredField(
        public val label: String,
        public val key: String,
    ) : ScenarioValidationMessage()

    public data class FieldWrongType(
        public val label: String,
        public val key: String,
        public val expected: String,
        public val got: String,
    ) : ScenarioValidationMessage()

    public data class FieldNotDoubleOrInt(
        public val label: String,
        public val key: String,
        public val got: String,
    ) : ScenarioValidationMessage()

    public data class AgentsPersonasCountMismatch(
        public val agentCount: Int,
        public val personaCount: Int,
    ) : ScenarioValidationMessage()

    public data class InvalidTarget(
        public val label: String,
        public val value: String,
    ) : ScenarioValidationMessage()

    public data class InvalidPairing(
        public val label: String,
        public val value: String,
    ) : ScenarioValidationMessage()

    public data class InvalidLogic(
        public val label: String,
        public val value: String,
        public val allowed: String,
    ) : ScenarioValidationMessage()

    public data class ActionDeltasNotDict(
        public val label: String,
        public val got: String,
    ) : ScenarioValidationMessage()

    public data class ActionDeltasValueNotInt(
        public val label: String,
        public val key: String,
        public val got: String,
    ) : ScenarioValidationMessage()

    public data class PayoffNotList(
        public val label: String,
        public val got: String,
    ) : ScenarioValidationMessage()

    public data class PayoffRowInvalid(
        public val label: String,
        public val detail: String,
    ) : ScenarioValidationMessage()

    public data class PhaseMissingType(public val label: String) : ScenarioValidationMessage()

    public data class PhaseInvalidType(
        public val label: String,
        public val value: String,
    ) : ScenarioValidationMessage()

    public data class OutputNotDict(
        public val label: String,
        public val got: String,
    ) : ScenarioValidationMessage()

    public data class OutputValueNotString(
        public val label: String,
        public val key: String,
        public val got: String,
    ) : ScenarioValidationMessage()

    public data class BranchNotArray(
        public val label: String,
        public val branch: String,
    ) : ScenarioValidationMessage()

    public data class ExtraDataArrayOfDictNotString(
        public val key: String,
    ) : ScenarioValidationMessage()

    public data class ExtraDataMixedArray(public val key: String) : ScenarioValidationMessage()

    public data class ExtraDataDictNotString(public val key: String) : ScenarioValidationMessage()

    public data class ExtraDataUnsupportedType(
        public val key: String,
        public val got: String,
        public val shapes: String,
    ) : ScenarioValidationMessage()

    // ── event_inject shape ──────────────────────────────────────────────────

    public data class EventInjectMissingSource(
        public val label: String,
    ) : ScenarioValidationMessage()

    public data class EventInjectSourceEmptyStrings(
        public val label: String,
        public val source: String,
    ) : ScenarioValidationMessage()

    public data class EventInjectSourceWrongShape(
        public val label: String,
        public val source: String,
    ) : ScenarioValidationMessage()

    public data class EventInjectSourceEmptyEvents(
        public val label: String,
        public val source: String,
    ) : ScenarioValidationMessage()

    public data class EventInjectEntryMissingText(
        public val label: String,
        public val source: String,
    ) : ScenarioValidationMessage()

    public data class EventInjectProbabilityOutOfRange(
        public val label: String,
        public val probability: String,
    ) : ScenarioValidationMessage()

    // ── Output field-name validation ────────────────────────────────────────

    public data class OutputFieldNameInvalid(
        public val label: String,
        public val name: String,
    ) : ScenarioValidationMessage()

    // ── Per-phase statement brevity override (#881) ─────────────────────────

    public data class MaxSentencesOutOfRange(
        public val label: String,
        public val value: Int,
    ) : ScenarioValidationMessage()

    /**
     * Renders the case to its display string, in **English only**.
     *
     * The literals are byte-identical to the `String(localized:)` base values in
     * Swift's `ScenarioValidationMessage.localized`, with `%@` / `%lld`
     * substituted positionally.
     *
     * ## Why en-only, and why that is not a shortcut
     *
     * `commonMain` has no string catalog, and Kotlin/Native has no path to
     * `Localizable.xcstrings`. ADR-023 §5 defines no boundary for this type, and
     * nothing consumes it in production until Stage 5 — so there is no
     * localization contract to satisfy yet, and inventing one here would be
     * guessing at Stage-5's design.
     *
     * ⚠️ **"the parity harness runs in en, so en-only is fine" is NOT the
     * reason, and must not be restored as one.** Validation messages never reach
     * a transcript at all:
     * `DivergenceLedger.DivergenceClass.VALIDATOR_UNPORTED` records that a
     * scenario Swift rejects produces no transcript to compare. The harness is
     * silent about this type in either language.
     *
     * ## The Stage-5 debt this creates
     *
     * Every one of these 53 literals **already has a `ja` translation** in
     * `Pastura/Pastura/Resources/Localizable.xcstrings`. If iOS starts consuming
     * the Kotlin engine (Stage 5) while this is still en-only, Japanese users get
     * English validation errors — a user-visible regression with **no compiler
     * and no test signal**, since the Kotlin side would be internally consistent
     * and the pins below would stay green.
     *
     * The Stage-5 fix is to make the rendering an `expect`/`actual` leaf. Member
     * naming here is chosen so that lands without moving callers: `render()`
     * keeps its name and signature, and only its body delegates to the platform
     * leaf. Note the cost — `shared/models` has four targets (`jvm`, `iosArm64`,
     * `iosSimulatorArm64`, `macosArm64`), so that is four `actual`s.
     */
    public fun render(): String = when (this) {
        is LanguageNotAccepted ->
            "Scenario: field 'language' must be one of {$allowed}, got '$got'"
        is SimulationLanguageNotAccepted ->
            "Scenario: field 'simulationLanguage' must be one of {$allowed} or nil, got '$got'"
        is SimulationLanguageYAMLNotAccepted ->
            "Scenario: field 'simulation_language' must be one of {$allowed} or absent, got '$got'"
        is AgentCountBelowMinimum ->
            "Agent count ($count) is below minimum of 2"
        is AgentCountExceedsMaximum ->
            "Agent count ($count) exceeds maximum of 10"
        is PersonaCountMismatch ->
            "Persona count ($personaCount) does not match agent count ($agentCount)"
        is RoundCountExceedsMaximum ->
            "Round count ($rounds) exceeds maximum of 30"
        is LogWindowBelowMinimum ->
            "Log window ($window) must be at least 1"
        is EstimatedInferencesExceedsMaximum ->
            "Estimated inferences ($estimated) exceeds maximum of 100"
        is HighInferenceCount ->
            "High inference count ($estimated). Simulation may take several minutes."
        is ConditionalMissingIf ->
            "$label: missing or empty 'if' expression."
        is ConditionalEmptyBranches ->
            "$label: must have at least one sub-phase in 'then' or 'else'."
        is NestedConditionalNotAllowed ->
            "$label: nested 'conditional' inside another conditional is not allowed (depth-1 rule)."
        is BranchNestedConditional ->
            "$label is another conditional, which is not allowed (depth-1 rule)."
        is BranchReflectNotAllowed ->
            "$label is a reflect phase, which is not allowed inside a conditional."
        is BranchWhisperNotAllowed ->
            "$label is a whisper phase, which is not allowed inside a conditional."
        is BranchRelationshipUpdateNotAllowed ->
            "$label is a relationship_update phase, which is not allowed inside a conditional."
        is BranchNarrateNotAllowed ->
            "$label is a narrate phase, which is not allowed inside a conditional."
        is RequiresOutputField ->
            "$label ($type) requires field '${field}' in output."
        is SecondaryFieldMismatch ->
            "$label ($type) secondary field must be '$canonical', not '$key'."
        is RelationshipUpdateMissingRule ->
            "$label ($type) requires at least one affinity rule: " +
                "'vote_against' and/or 'action_deltas'."
        is SourceNotFound ->
            "$label: source '$source' not found in scenario data. " +
                "Add a top-level '$source' field to the scenario YAML."
        is AssignSourceGroupedForAll ->
            "$label: source '$source' contains grouped values (e.g., majority/minority pairs). " +
                "Use target: random_one to distribute these. " +
                "Use target: all only for a flat list of strings or a single string."
        is AssignSourceNotGroupedForRandomOne ->
            "$label: source '$source' must be a list of grouped values " +
                "(e.g., majority/minority pairs) when target is random_one."
        is InvalidYAMLFormat ->
            "Invalid YAML format"
        is MissingRequiredField ->
            "$label: missing required field '$key'"
        is FieldWrongType ->
            "$label: field '$key' must be $expected, got $got"
        is FieldNotDoubleOrInt ->
            "$label: field '$key' must be Double or Int, got $got"
        is AgentsPersonasCountMismatch ->
            "agents ($agentCount) does not match personas count ($personaCount)"
        is InvalidTarget ->
            "$label has invalid target: '$value'. Use 'all' or 'random_one'."
        is InvalidPairing ->
            "$label has invalid pairing: '$value'. Use 'round_robin'."
        is InvalidLogic ->
            "$label has invalid logic: '$value'. Expected one of: $allowed."
        is ActionDeltasNotDict ->
            "$label: field 'action_deltas' must be a dictionary of Int values, got $got"
        is ActionDeltasValueNotInt ->
            "$label: action_deltas value for '$key' must be Int, got $got"
        is PayoffNotList ->
            "$label: field 'payoff' must be a list of {when, points} rows, got $got"
        is PayoffRowInvalid ->
            "$label: each 'payoff' row needs 'when' (2 strings) and 'points' (2 ints) — $detail"
        is PhaseMissingType ->
            "$label missing 'type'"
        is PhaseInvalidType ->
            "$label has invalid type: '$value'"
        is OutputNotDict ->
            "$label: field 'output' must be a dictionary of String values, got $got"
        is OutputValueNotString ->
            "$label: output schema value for '$key' must be String, got $got"
        is BranchNotArray ->
            "$label: '$branch' must be an array of phase objects"
        is ExtraDataArrayOfDictNotString ->
            "Top-level field '$key': array-of-dict values must all be String. " +
                "Quote non-string values (e.g. `majority: \"1\"`)."
        is ExtraDataMixedArray ->
            "Top-level field '$key': mixed-type arrays are not supported. " +
                "Use a pure [String] or [[String: String]]."
        is ExtraDataDictNotString ->
            "Top-level field '$key': dictionary values must all be String. " +
                "Quote non-string values."
        is ExtraDataUnsupportedType ->
            "Top-level field '$key' has unsupported type $got. Supported shapes: $shapes."
        is EventInjectMissingSource ->
            "$label: missing 'source'. event_inject requires a 'source' key naming a " +
                "top-level YAML field that lists the event strings."
        is EventInjectSourceEmptyStrings ->
            "$label: source '$source' is empty. event_inject requires at least one string " +
                "in the list; for a single fixed event use ['only_event']."
        is EventInjectSourceWrongShape ->
            "$label: source '$source' must be a list of event strings or {text, favors} " +
                "mappings; for a single fixed event use ['only_event']."
        is EventInjectSourceEmptyEvents ->
            "$label: source '$source' is empty. event_inject requires at least one event " +
                "in the list; for a single fixed event use ['only_event']."
        is EventInjectEntryMissingText ->
            "$label: source '$source' has an event entry missing a non-empty 'text'. " +
                "Dict-shaped events require 'text' (and may add 'favors')."
        is EventInjectProbabilityOutOfRange ->
            "$label: probability $probability is out of range. " +
                "Must be between 0.0 and 1.0 inclusive."
        is OutputFieldNameInvalid ->
            "$label: output field name '$name' must be an ASCII identifier " +
                "(letters, digits, and underscore, not starting with a digit or underscore). " +
                "Agent text values may be any language."
        is MaxSentencesOutOfRange ->
            "$label: max_sentences ($value) must be between 1 and 6"
    }
}
