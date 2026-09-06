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
 * with its own 22 messages (Ordering 8 / Config 8 / Placeholders 3 /
 * Conditions 3), and they live in their own type — [ScenarioLintMessage],
 * mirroring `Pastura/Pastura/Models/ScenarioLintMessage.swift`. That split is a
 * decision (#1562), not a staging accident: a lint finding carries a severity
 * and is collected alongside others for the same scenario, while a validation
 * message is thrown as the sole reason a load or commit-gate check failed.
 * So the `53` pins in `ScenarioValidationMessageTests` **stay at 53** when
 * `ScenarioSemanticLinter` is ported — the linter's cases never join this type.
 *
 * ## Landed as infra
 *
 * Landed ahead of its consumer — `ScenarioValidator` — as one of the two
 * dependencies (with `InferenceEstimator` in `shared/engine`) that had to
 * exist before the validator port could compile. `ScenarioValidator` is now
 * ported and, since D3 (#1591), wired into `SimulationEngine.run`. Ported for
 * the ADR-023 §6 Stage-3 Engine migration (#501).
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
     * Renders the case to its display string, localized on Apple hosts that
     * carry the app's string catalog.
     *
     * The format strings are byte-identical to the `String(localized:)` base
     * values in Swift's `ScenarioValidationMessage.localized`. Rendering goes
     * through the platform catalog leaf — [localizedFormat] in
     * `MessageRendering.kt` — an `expect`/`actual` with one `jvmMain` actual
     * (identity: returns the English key unchanged) and one `appleMain` actual
     * (`NSBundle.mainBundle.localizedStringForKey`). So the JVM and catalog-less
     * Apple hosts (the macOS parity harness) get the English key
     * back — the commonTest pins below are still the detector on both rungs —
     * while the iOS app resolves the same `Localizable.xcstrings` `ja` value
     * Swift does, because the format string doubles as the catalog key.
     *
     * ⚠️ **"the parity harness runs in en, so en-only is fine" was never the
     * reason this stayed en-only, and must not be restored as one now that it
     * isn't.** Validation messages never reach a transcript at all, even now
     * that the validator is wired into the run path (D3 #1591): a scenario
     * Swift rejects produces no transcript to compare. The harness is silent
     * about this type in either language — the localization leaf below exists
     * for the iOS app, not for parity.
     *
     * ## The Stage-5 debt this discharges
     *
     * Every one of these 53 literals has a `ja` translation in
     * `Pastura/Pastura/Resources/Localizable.xcstrings`. Before this leaf
     * landed (#1631), a Stage-5 iOS app consuming the Kotlin engine would have
     * shown Japanese users English validation errors with no compiler or test
     * signal — recorded on the Stage-5 row of `docs/kmp-migration-status.md`.
     * That debt is discharged: `MessageCatalogCoverageTests`
     * (`:shared:models:jvmTest`) is now the catalog-drift signal, failing
     * whenever a [rendering] format is stale or its `%@`/`%lld` multiset
     * disagrees with the catalog's `ja` value.
     *
     * A Swift literal reword is therefore a **four-place edit**: the Swift
     * `String(localized:)` literal, the catalog `ja` value (via the normal
     * `xcstringstool` sync), this file's [rendering] format, and the
     * commonTest expected string. Miss the Kotlin side and
     * `MessageCatalogCoverageTests` reddens per-PR (`ci.yml`'s `kmp` filter
     * fires on `Localizable.xcstrings` and the two Swift `*Message.swift`
     * files); miss the catalog sync and the same test catches the stale key.
     */
    public fun render(): String = rendering().render()

    /**
     * Maps the case to its [Rendering] — English format string plus positional
     * args, in the order the format consumes them.
     *
     * The format strings are byte-identical to the `String(localized:)` base
     * values in Swift's `ScenarioValidationMessage.localized`, with `%@` / `%lld`
     * left in place as catalog placeholders rather than substituted here —
     * [Rendering.render] resolves the platform catalog and substitutes.
     */
    internal fun rendering(): Rendering = when (this) {
        is LanguageNotAccepted ->
            Rendering(
                "Scenario: field 'language' must be one of {%@}, got '%@'",
                listOf(allowed, got),
            )
        is SimulationLanguageNotAccepted ->
            Rendering(
                "Scenario: field 'simulationLanguage' must be one of {%@} or nil, got '%@'",
                listOf(allowed, got),
            )
        is SimulationLanguageYAMLNotAccepted ->
            Rendering(
                "Scenario: field 'simulation_language' must be one of {%@} or absent, got '%@'",
                listOf(allowed, got),
            )
        is AgentCountBelowMinimum ->
            Rendering("Agent count (%lld) is below minimum of 2", listOf(count))
        is AgentCountExceedsMaximum ->
            Rendering("Agent count (%lld) exceeds maximum of 10", listOf(count))
        is PersonaCountMismatch ->
            Rendering(
                "Persona count (%lld) does not match agent count (%lld)",
                listOf(personaCount, agentCount),
            )
        is RoundCountExceedsMaximum ->
            Rendering("Round count (%lld) exceeds maximum of 30", listOf(rounds))
        is LogWindowBelowMinimum ->
            Rendering("Log window (%lld) must be at least 1", listOf(window))
        is EstimatedInferencesExceedsMaximum ->
            Rendering("Estimated inferences (%lld) exceeds maximum of 100", listOf(estimated))
        is HighInferenceCount ->
            Rendering(
                "High inference count (%lld). Simulation may take several minutes.",
                listOf(estimated),
            )
        is ConditionalMissingIf ->
            Rendering("%@: missing or empty 'if' expression.", listOf(label))
        is ConditionalEmptyBranches ->
            Rendering(
                "%@: must have at least one sub-phase in 'then' or 'else'.",
                listOf(label),
            )
        is NestedConditionalNotAllowed ->
            Rendering(
                "%@: nested 'conditional' inside another conditional is not allowed (depth-1 rule).",
                listOf(label),
            )
        is BranchNestedConditional ->
            Rendering(
                "%@ is another conditional, which is not allowed (depth-1 rule).",
                listOf(label),
            )
        is BranchReflectNotAllowed ->
            Rendering(
                "%@ is a reflect phase, which is not allowed inside a conditional.",
                listOf(label),
            )
        is BranchWhisperNotAllowed ->
            Rendering(
                "%@ is a whisper phase, which is not allowed inside a conditional.",
                listOf(label),
            )
        is BranchRelationshipUpdateNotAllowed ->
            Rendering(
                "%@ is a relationship_update phase, which is not allowed inside a conditional.",
                listOf(label),
            )
        is BranchNarrateNotAllowed ->
            Rendering(
                "%@ is a narrate phase, which is not allowed inside a conditional.",
                listOf(label),
            )
        is RequiresOutputField ->
            Rendering(
                "%@ (%@) requires field '%@' in output.",
                listOf(label, type, field),
            )
        is SecondaryFieldMismatch ->
            Rendering(
                "%@ (%@) secondary field must be '%@', not '%@'.",
                listOf(label, type, canonical, key),
            )
        is RelationshipUpdateMissingRule ->
            Rendering(
                "%@ (%@) requires at least one affinity rule: 'vote_against' and/or 'action_deltas'.",
                listOf(label, type),
            )
        is SourceNotFound ->
            Rendering(
                "%@: source '%@' not found in scenario data. " +
                    "Add a top-level '%@' field to the scenario YAML.",
                listOf(label, source, source),
            )
        is AssignSourceGroupedForAll ->
            Rendering(
                "%@: source '%@' contains grouped values (e.g., majority/minority pairs). " +
                    "Use target: random_one to distribute these. " +
                    "Use target: all only for a flat list of strings or a single string.",
                listOf(label, source),
            )
        is AssignSourceNotGroupedForRandomOne ->
            Rendering(
                "%@: source '%@' must be a list of grouped values " +
                    "(e.g., majority/minority pairs) when target is random_one.",
                listOf(label, source),
            )
        is InvalidYAMLFormat ->
            Rendering("Invalid YAML format", emptyList())
        is MissingRequiredField ->
            Rendering("%@: missing required field '%@'", listOf(label, key))
        is FieldWrongType ->
            Rendering(
                "%@: field '%@' must be %@, got %@",
                listOf(label, key, expected, got),
            )
        is FieldNotDoubleOrInt ->
            Rendering(
                "%@: field '%@' must be Double or Int, got %@",
                listOf(label, key, got),
            )
        is AgentsPersonasCountMismatch ->
            Rendering(
                "agents (%lld) does not match personas count (%lld)",
                listOf(agentCount, personaCount),
            )
        is InvalidTarget ->
            Rendering(
                "%@ has invalid target: '%@'. Use 'all' or 'random_one'.",
                listOf(label, value),
            )
        is InvalidPairing ->
            Rendering(
                "%@ has invalid pairing: '%@'. Use 'round_robin'.",
                listOf(label, value),
            )
        is InvalidLogic ->
            Rendering(
                "%@ has invalid logic: '%@'. Expected one of: %@.",
                listOf(label, value, allowed),
            )
        is ActionDeltasNotDict ->
            Rendering(
                "%@: field 'action_deltas' must be a dictionary of Int values, got %@",
                listOf(label, got),
            )
        is ActionDeltasValueNotInt ->
            Rendering(
                "%@: action_deltas value for '%@' must be Int, got %@",
                listOf(label, key, got),
            )
        is PayoffNotList ->
            Rendering(
                "%@: field 'payoff' must be a list of {when, points} rows, got %@",
                listOf(label, got),
            )
        is PayoffRowInvalid ->
            Rendering(
                "%@: each 'payoff' row needs 'when' (2 strings) and 'points' (2 ints) — %@",
                listOf(label, detail),
            )
        is PhaseMissingType ->
            Rendering("%@ missing 'type'", listOf(label))
        is PhaseInvalidType ->
            Rendering("%@ has invalid type: '%@'", listOf(label, value))
        is OutputNotDict ->
            Rendering(
                "%@: field 'output' must be a dictionary of String values, got %@",
                listOf(label, got),
            )
        is OutputValueNotString ->
            Rendering(
                "%@: output schema value for '%@' must be String, got %@",
                listOf(label, key, got),
            )
        is BranchNotArray ->
            Rendering("%@: '%@' must be an array of phase objects", listOf(label, branch))
        is ExtraDataArrayOfDictNotString ->
            Rendering(
                "Top-level field '%@': array-of-dict values must all be String. " +
                    "Quote non-string values (e.g. `majority: \"1\"`).",
                listOf(key),
            )
        is ExtraDataMixedArray ->
            Rendering(
                "Top-level field '%@': mixed-type arrays are not supported. " +
                    "Use a pure [String] or [[String: String]].",
                listOf(key),
            )
        is ExtraDataDictNotString ->
            Rendering(
                "Top-level field '%@': dictionary values must all be String. " +
                    "Quote non-string values.",
                listOf(key),
            )
        is ExtraDataUnsupportedType ->
            Rendering(
                "Top-level field '%@' has unsupported type %@. Supported shapes: %@.",
                listOf(key, got, shapes),
            )
        is EventInjectMissingSource ->
            Rendering(
                "%@: missing 'source'. event_inject requires a 'source' key naming a " +
                    "top-level YAML field that lists the event strings.",
                listOf(label),
            )
        is EventInjectSourceEmptyStrings ->
            Rendering(
                "%@: source '%@' is empty. event_inject requires at least one string " +
                    "in the list; for a single fixed event use ['only_event'].",
                listOf(label, source),
            )
        is EventInjectSourceWrongShape ->
            Rendering(
                "%@: source '%@' must be a list of event strings or {text, favors} " +
                    "mappings; for a single fixed event use ['only_event'].",
                listOf(label, source),
            )
        is EventInjectSourceEmptyEvents ->
            Rendering(
                "%@: source '%@' is empty. event_inject requires at least one event " +
                    "in the list; for a single fixed event use ['only_event'].",
                listOf(label, source),
            )
        is EventInjectEntryMissingText ->
            Rendering(
                "%@: source '%@' has an event entry missing a non-empty 'text'. " +
                    "Dict-shaped events require 'text' (and may add 'favors').",
                listOf(label, source),
            )
        is EventInjectProbabilityOutOfRange ->
            Rendering(
                "%@: probability %@ is out of range. " +
                    "Must be between 0.0 and 1.0 inclusive.",
                listOf(label, probability),
            )
        is OutputFieldNameInvalid ->
            Rendering(
                "%@: output field name '%@' must be an ASCII identifier " +
                    "(letters, digits, and underscore, not starting with a digit or underscore). " +
                    "Agent text values may be any language.",
                listOf(label, name),
            )
        is MaxSentencesOutOfRange ->
            Rendering(
                "%@: max_sentences (%lld) must be between 1 and 6",
                listOf(label, value),
            )
    }
}
