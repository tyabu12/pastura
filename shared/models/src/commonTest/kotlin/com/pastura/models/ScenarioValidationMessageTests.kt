package com.pastura.models

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Locks [ScenarioValidationMessage.render] to byte-identical strings against the
 * Swift original (`Pastura/Pastura/Models/ScenarioValidationMessage.swift`), the
 * single source of truth for both the case set and every expected literal below
 * — this file never sources an expected string from `ScenarioValidationMessage.kt`
 * itself (the file under test), which would blind it to a transcription error.
 *
 * Four parts, per issue #1464 / ADR-023 §12:
 *
 * (a) [caseSetMatchesSwiftEnumBidirectionally] — the 53 hand-transcribed Swift
 *     case names vs. the Kotlin subtype names, both directions.
 * (b) [rosterCoversExactlyFiftyThreeSubtypesWithNoDuplicatesOrOmissions] — a
 *     count pin plus an else-free `when` roster ([swiftCaseNameOf]).
 * (c) [rendersAllFiftyThreeCasesWithArgumentOrderIntact] — every one of the 53
 *     cases rendered and asserted by full-string equality, seeded from the 16
 *     Swift tests in `Pastura/PasturaTests/Models/ScenarioValidationMessageTests.swift`.
 * (d) this KDoc's perturbation-record table, below.
 *
 * ## Mutual distinguishability is what makes (c) an argument-order check
 *
 * [rosterWithExpectedRenderings] constructs every case so that, within one case,
 * no two `String` arguments are equal and no two `Int` arguments are equal.
 * Without that, a swapped pair renders identically and full-string equality
 * cannot see it — the same reason a `.contains` substring test cannot catch an
 * arg-order swap. This transfers wholesale from the Swift suite's own framing:
 * an argument-order swap in a Kotlin string template is exactly as available as
 * one in Swift's `String(format:)`.
 *
 * ## En-only pin is Stage-5-scoped
 *
 * `shared/models` has four targets (`jvm`, `iosArm64`, `iosSimulatorArm64`,
 * `macosArm64`). [ScenarioValidationMessage.render] is a single common-code
 * function today, so pinning its English output here is sound. The day
 * `render()` becomes an `expect`/`actual` leaf (see its own KDoc's "Stage-5
 * debt" section), this file's single-locale full-string pins go stale for the
 * non-`jvm` targets and need a per-target parameterization.
 *
 * ## Rejected alternative: a per-case `template` property
 *
 * Considered exposing a `template: String` on every subtype so this test could
 * mechanically match `template` against the `Localizable.xcstrings` keys instead
 * of hand-transcribing 53 expected strings. Rejected for one reason only: it
 * adds test-only public API to a Models-layer type. (Case-set completeness in
 * (a) does not independently justify skipping this — a missing case and a
 * literal/key mismatch are different failure modes, and (a) only ever sees the
 * first.)
 *
 * ## §12 condition-4 perturbation record
 *
 * Each mutation is an **argument swap inside a multi-argument case** — never a
 * `when`-arm inversion, which is caught trivially and proves nothing about
 * argument order (the thing these tests exist to catch). Each mutation's anchor
 * text was confirmed to match **exactly once** in `ScenarioValidationMessage.kt`
 * before applying — a `replace` that silently no-ops leaves the original
 * behaviour and reads as verified. The unmutated baseline was reconfirmed green
 * both before the first mutation and after the last revert, so every red below
 * is signal. `ScenarioValidationMessage.kt` is byte-identical to how this PR
 * found it — `git diff --stat shared/models/src/commonMain/` shows no changes.
 * Counts are measured, not derived. Measured 2026-08-14, #1464.
 *
 * | Argument swapped | Mutation | Dedicated claimant | Incidental |
 * |---|---|---|---|
 * | `PersonaCountMismatch` — `personaCount`/`agentCount` (2 Ints) | swapped the two interpolations in the render arm | [rendersAllFiftyThreeCasesWithArgumentOrderIntact] (personaCountMismatch entry) | 0 |
 * | `SecondaryFieldMismatch` — `canonical`/`key` (of 4 Strings) | swapped `$canonical` and `$key` in the render arm | [rendersAllFiftyThreeCasesWithArgumentOrderIntact] (secondaryFieldMismatch entry) | 0 |
 * | `SourceNotFound` — repeated `source` slot | second `'$source'` occurrence changed to `'$label'` | [rendersAllFiftyThreeCasesWithArgumentOrderIntact] (sourceNotFound entry) | 0 |
 *
 * All three mutations reddened only [rendersAllFiftyThreeCasesWithArgumentOrderIntact]
 * — `forEach` throws on the first mismatched roster entry it hits, so one
 * mutation reddens one `assertEquals` failure naming exactly the mutated case
 * (Kotlin/JUnit reports this as one failing test method, not one failure per
 * roster entry — "dedicated claimant" above names the entry the failure message
 * identifies, not a per-entry test count). No other test in this file reddened
 * for any of the three mutations, and no mutation left the suite green.
 */
class ScenarioValidationMessageTests {

    /**
     * Hand-transcribed from
     * `Pastura/Pastura/Models/ScenarioValidationMessage.swift` lines 23–93, in
     * file (declaration) order. The Kotlin naming rule is "Swift case name with
     * the first character uppercased, nothing else rewritten"
     * (`ScenarioValidationMessage.kt`'s own "Naming" KDoc section), so this list
     * needs no translation table beyond that capitalisation.
     */
    private val swiftCaseNames: List<String> = listOf(
        "languageNotAccepted",
        "simulationLanguageNotAccepted",
        "simulationLanguageYAMLNotAccepted",
        "agentCountBelowMinimum",
        "agentCountExceedsMaximum",
        "personaCountMismatch",
        "roundCountExceedsMaximum",
        "logWindowBelowMinimum",
        "estimatedInferencesExceedsMaximum",
        "highInferenceCount",
        "conditionalMissingIf",
        "conditionalEmptyBranches",
        "nestedConditionalNotAllowed",
        "branchNestedConditional",
        "branchReflectNotAllowed",
        "branchWhisperNotAllowed",
        "branchRelationshipUpdateNotAllowed",
        "branchNarrateNotAllowed",
        "requiresOutputField",
        "secondaryFieldMismatch",
        "relationshipUpdateMissingRule",
        "sourceNotFound",
        "assignSourceGroupedForAll",
        "assignSourceNotGroupedForRandomOne",
        "invalidYAMLFormat",
        "missingRequiredField",
        "fieldWrongType",
        "fieldNotDoubleOrInt",
        "agentsPersonasCountMismatch",
        "invalidTarget",
        "invalidPairing",
        "invalidLogic",
        "actionDeltasNotDict",
        "actionDeltasValueNotInt",
        "payoffNotList",
        "payoffRowInvalid",
        "phaseMissingType",
        "phaseInvalidType",
        "outputNotDict",
        "outputValueNotString",
        "branchNotArray",
        "extraDataArrayOfDictNotString",
        "extraDataMixedArray",
        "extraDataDictNotString",
        "extraDataUnsupportedType",
        "eventInjectMissingSource",
        "eventInjectSourceEmptyStrings",
        "eventInjectSourceWrongShape",
        "eventInjectSourceEmptyEvents",
        "eventInjectEntryMissingText",
        "eventInjectProbabilityOutOfRange",
        "outputFieldNameInvalid",
        "maxSentencesOutOfRange",
    )

    // ── (a) Case-set completeness ────────────────────────────────────────────

    @Test
    fun caseSetMatchesSwiftEnumBidirectionally() {
        assertEquals(53, swiftCaseNames.size, "swiftCaseNames transcription itself must list 53")
        val expectedKotlinNames = swiftCaseNames.map { it.replaceFirstChar(Char::uppercaseChar) }.toSet()
        val actualKotlinNames = roster().map { it::class.simpleName }.toSet()
        val missingInKotlin = expectedKotlinNames - actualKotlinNames
        val extraInKotlin = actualKotlinNames - expectedKotlinNames
        assertTrue(
            missingInKotlin.isEmpty() && extraInKotlin.isEmpty(),
            "Case-set mismatch. In Swift but not Kotlin: $missingInKotlin. " +
                "In Kotlin but not Swift: $extraInKotlin.",
        )
    }

    // ── (b) Count pin + else-free `when` roster ─────────────────────────────

    /**
     * This is a **pin, not a proof.** `KClass.sealedSubclasses` is JVM-only and
     * ADR-023 Decision 5 requires the `macosArm64` rung, so commonTest cannot
     * enumerate a sealed hierarchy reflectively — see
     * `.claude/rules/kmp-interop.md` Pattern 4. The count pin below, plus the
     * else-free `when` in [swiftCaseNameOf] (which fails to *compile* if a
     * subtype is added without a matching arm), is the strongest available
     * substitute for real reflective completeness.
     */
    @Test
    fun rosterCoversExactlyFiftyThreeSubtypesWithNoDuplicatesOrOmissions() {
        val entries = roster()
        assertEquals(53, entries.size, "Roster size pin — see kmp-interop.md Pattern 4")
        val caseNames = entries.map(::swiftCaseNameOf)
        assertEquals(
            caseNames.size,
            caseNames.toSet().size,
            "Roster has a duplicate subtype: $caseNames",
        )
        assertEquals(swiftCaseNames.toSet(), caseNames.toSet())
    }

    /**
     * Deliberately has **no `else` branch** — a Kotlin subtype added to
     * [ScenarioValidationMessage] without an arm here fails the build, which is
     * the compile-time half of the "pin, not proof" substitute described on
     * [rosterCoversExactlyFiftyThreeSubtypesWithNoDuplicatesOrOmissions].
     */
    private fun swiftCaseNameOf(msg: ScenarioValidationMessage): String = when (msg) {
        is ScenarioValidationMessage.LanguageNotAccepted -> "languageNotAccepted"
        is ScenarioValidationMessage.SimulationLanguageNotAccepted -> "simulationLanguageNotAccepted"
        is ScenarioValidationMessage.SimulationLanguageYAMLNotAccepted -> "simulationLanguageYAMLNotAccepted"
        is ScenarioValidationMessage.AgentCountBelowMinimum -> "agentCountBelowMinimum"
        is ScenarioValidationMessage.AgentCountExceedsMaximum -> "agentCountExceedsMaximum"
        is ScenarioValidationMessage.PersonaCountMismatch -> "personaCountMismatch"
        is ScenarioValidationMessage.RoundCountExceedsMaximum -> "roundCountExceedsMaximum"
        is ScenarioValidationMessage.LogWindowBelowMinimum -> "logWindowBelowMinimum"
        is ScenarioValidationMessage.EstimatedInferencesExceedsMaximum -> "estimatedInferencesExceedsMaximum"
        is ScenarioValidationMessage.HighInferenceCount -> "highInferenceCount"
        is ScenarioValidationMessage.ConditionalMissingIf -> "conditionalMissingIf"
        is ScenarioValidationMessage.ConditionalEmptyBranches -> "conditionalEmptyBranches"
        is ScenarioValidationMessage.NestedConditionalNotAllowed -> "nestedConditionalNotAllowed"
        is ScenarioValidationMessage.BranchNestedConditional -> "branchNestedConditional"
        is ScenarioValidationMessage.BranchReflectNotAllowed -> "branchReflectNotAllowed"
        is ScenarioValidationMessage.BranchWhisperNotAllowed -> "branchWhisperNotAllowed"
        is ScenarioValidationMessage.BranchRelationshipUpdateNotAllowed -> "branchRelationshipUpdateNotAllowed"
        is ScenarioValidationMessage.BranchNarrateNotAllowed -> "branchNarrateNotAllowed"
        is ScenarioValidationMessage.RequiresOutputField -> "requiresOutputField"
        is ScenarioValidationMessage.SecondaryFieldMismatch -> "secondaryFieldMismatch"
        is ScenarioValidationMessage.RelationshipUpdateMissingRule -> "relationshipUpdateMissingRule"
        is ScenarioValidationMessage.SourceNotFound -> "sourceNotFound"
        is ScenarioValidationMessage.AssignSourceGroupedForAll -> "assignSourceGroupedForAll"
        is ScenarioValidationMessage.AssignSourceNotGroupedForRandomOne -> "assignSourceNotGroupedForRandomOne"
        is ScenarioValidationMessage.InvalidYAMLFormat -> "invalidYAMLFormat"
        is ScenarioValidationMessage.MissingRequiredField -> "missingRequiredField"
        is ScenarioValidationMessage.FieldWrongType -> "fieldWrongType"
        is ScenarioValidationMessage.FieldNotDoubleOrInt -> "fieldNotDoubleOrInt"
        is ScenarioValidationMessage.AgentsPersonasCountMismatch -> "agentsPersonasCountMismatch"
        is ScenarioValidationMessage.InvalidTarget -> "invalidTarget"
        is ScenarioValidationMessage.InvalidPairing -> "invalidPairing"
        is ScenarioValidationMessage.InvalidLogic -> "invalidLogic"
        is ScenarioValidationMessage.ActionDeltasNotDict -> "actionDeltasNotDict"
        is ScenarioValidationMessage.ActionDeltasValueNotInt -> "actionDeltasValueNotInt"
        is ScenarioValidationMessage.PayoffNotList -> "payoffNotList"
        is ScenarioValidationMessage.PayoffRowInvalid -> "payoffRowInvalid"
        is ScenarioValidationMessage.PhaseMissingType -> "phaseMissingType"
        is ScenarioValidationMessage.PhaseInvalidType -> "phaseInvalidType"
        is ScenarioValidationMessage.OutputNotDict -> "outputNotDict"
        is ScenarioValidationMessage.OutputValueNotString -> "outputValueNotString"
        is ScenarioValidationMessage.BranchNotArray -> "branchNotArray"
        is ScenarioValidationMessage.ExtraDataArrayOfDictNotString -> "extraDataArrayOfDictNotString"
        is ScenarioValidationMessage.ExtraDataMixedArray -> "extraDataMixedArray"
        is ScenarioValidationMessage.ExtraDataDictNotString -> "extraDataDictNotString"
        is ScenarioValidationMessage.ExtraDataUnsupportedType -> "extraDataUnsupportedType"
        is ScenarioValidationMessage.EventInjectMissingSource -> "eventInjectMissingSource"
        is ScenarioValidationMessage.EventInjectSourceEmptyStrings -> "eventInjectSourceEmptyStrings"
        is ScenarioValidationMessage.EventInjectSourceWrongShape -> "eventInjectSourceWrongShape"
        is ScenarioValidationMessage.EventInjectSourceEmptyEvents -> "eventInjectSourceEmptyEvents"
        is ScenarioValidationMessage.EventInjectEntryMissingText -> "eventInjectEntryMissingText"
        is ScenarioValidationMessage.EventInjectProbabilityOutOfRange -> "eventInjectProbabilityOutOfRange"
        is ScenarioValidationMessage.OutputFieldNameInvalid -> "outputFieldNameInvalid"
        is ScenarioValidationMessage.MaxSentencesOutOfRange -> "maxSentencesOutOfRange"
    }

    // ── (c) Argument-order assertions ───────────────────────────────────────

    @Test
    fun rendersAllFiftyThreeCasesWithArgumentOrderIntact() {
        rosterWithExpectedRenderings().forEach { (msg, expected) ->
            assertEquals(expected, msg.render(), "Render mismatch for ${swiftCaseNameOf(msg)}")
        }
    }

    private fun roster(): List<ScenarioValidationMessage> =
        rosterWithExpectedRenderings().map { it.first }

    /**
     * Every one of the 53 cases, constructed with mutually distinguishable
     * arguments (see the class KDoc), paired with its expected rendered string
     * transcribed from `ScenarioValidationMessage.swift`'s `String(localized:)`
     * base literals with `%@` / `%lld` substituted positionally — never copied
     * from `ScenarioValidationMessage.kt`.
     *
     * 16 of these entries are ported directly from
     * `Pastura/PasturaTests/Models/ScenarioValidationMessageTests.swift`,
     * keeping its exact argument values and expected strings, including
     * `personaCountMismatch` (both Ints ordered), `secondaryFieldMismatch` (all
     * four Strings ordered), and `sourceNotFound` (one argument rendered twice
     * in one literal).
     */
    private fun rosterWithExpectedRenderings(): List<Pair<ScenarioValidationMessage, String>> = listOf(
        ScenarioValidationMessage.LanguageNotAccepted(allowed = "en, ja", got = "fr") to
            "Scenario: field 'language' must be one of {en, ja}, got 'fr'",
        ScenarioValidationMessage.SimulationLanguageNotAccepted(allowed = "en", got = "ja") to
            "Scenario: field 'simulationLanguage' must be one of {en} or nil, got 'ja'",
        ScenarioValidationMessage.SimulationLanguageYAMLNotAccepted(allowed = "en", got = "fr") to
            "Scenario: field 'simulation_language' must be one of {en} or absent, got 'fr'",
        ScenarioValidationMessage.AgentCountBelowMinimum(count = 1) to
            "Agent count (1) is below minimum of 2",
        ScenarioValidationMessage.AgentCountExceedsMaximum(count = 11) to
            "Agent count (11) exceeds maximum of 10",
        // Two %lld — arg order is personaCount then agentCount.
        ScenarioValidationMessage.PersonaCountMismatch(personaCount = 3, agentCount = 5) to
            "Persona count (3) does not match agent count (5)",
        ScenarioValidationMessage.RoundCountExceedsMaximum(rounds = 31) to
            "Round count (31) exceeds maximum of 30",
        ScenarioValidationMessage.LogWindowBelowMinimum(window = 0) to
            "Log window (0) must be at least 1",
        ScenarioValidationMessage.EstimatedInferencesExceedsMaximum(estimated = 101) to
            "Estimated inferences (101) exceeds maximum of 100",
        // The `rg 'String(localized:'` blind spot — literal was multi-line-wrapped.
        ScenarioValidationMessage.HighInferenceCount(estimated = 72) to
            "High inference count (72). Simulation may take several minutes.",
        ScenarioValidationMessage.ConditionalMissingIf(label = "Phase 1") to
            "Phase 1: missing or empty 'if' expression.",
        ScenarioValidationMessage.ConditionalEmptyBranches(label = "Phase 2") to
            "Phase 2: must have at least one sub-phase in 'then' or 'else'.",
        ScenarioValidationMessage.NestedConditionalNotAllowed(label = "Phase 4") to
            "Phase 4: nested 'conditional' inside another conditional is not allowed (depth-1 rule).",
        ScenarioValidationMessage.BranchNestedConditional(label = "Phase 5") to
            "Phase 5 is another conditional, which is not allowed (depth-1 rule).",
        ScenarioValidationMessage.BranchReflectNotAllowed(label = "Phase 6") to
            "Phase 6 is a reflect phase, which is not allowed inside a conditional.",
        ScenarioValidationMessage.BranchWhisperNotAllowed(label = "Phase 7") to
            "Phase 7 is a whisper phase, which is not allowed inside a conditional.",
        ScenarioValidationMessage.BranchRelationshipUpdateNotAllowed(label = "Phase 8") to
            "Phase 8 is a relationship_update phase, which is not allowed inside a conditional.",
        ScenarioValidationMessage.BranchNarrateNotAllowed(label = "Phase 9") to
            "Phase 9 is a narrate phase, which is not allowed inside a conditional.",
        ScenarioValidationMessage.RequiresOutputField(label = "Phase 1", type = "reflect", field = "note") to
            "Phase 1 (reflect) requires field 'note' in output.",
        // Four %@ — arg order is label, type, canonical, key.
        ScenarioValidationMessage.SecondaryFieldMismatch(
            label = "Phase 2", type = "vote", canonical = "reason", key = "inner_thought",
        ) to
            "Phase 2 (vote) secondary field must be 'reason', not 'inner_thought'.",
        ScenarioValidationMessage.RelationshipUpdateMissingRule(label = "Phase A", type = "vote") to
            "Phase A (vote) requires at least one affinity rule: " +
                "'vote_against' and/or 'action_deltas'.",
        // Literal has three %@; `source` is substituted into positions 2 and 3.
        ScenarioValidationMessage.SourceNotFound(label = "Phase 3", source = "roles") to
            "Phase 3: source 'roles' not found in scenario data. " +
                "Add a top-level 'roles' field to the scenario YAML.",
        ScenarioValidationMessage.AssignSourceGroupedForAll(label = "Phase 7", source = "teams") to
            "Phase 7: source 'teams' contains grouped values (e.g., majority/minority pairs). " +
                "Use target: random_one to distribute these. Use target: all only for a flat list " +
                "of strings or a single string.",
        ScenarioValidationMessage.AssignSourceNotGroupedForRandomOne(label = "Phase 8", source = "roles") to
            "Phase 8: source 'roles' must be a list of grouped values " +
                "(e.g., majority/minority pairs) when target is random_one.",
        ScenarioValidationMessage.InvalidYAMLFormat to
            "Invalid YAML format",
        ScenarioValidationMessage.MissingRequiredField(label = "Scenario", key = "agents") to
            "Scenario: missing required field 'agents'",
        ScenarioValidationMessage.FieldWrongType(
            label = "Scenario", key = "agents", expected = "Int", got = "String",
        ) to
            "Scenario: field 'agents' must be Int, got String",
        ScenarioValidationMessage.FieldNotDoubleOrInt(label = "Phase X", key = "weight", got = "String") to
            "Phase X: field 'weight' must be Double or Int, got String",
        ScenarioValidationMessage.AgentsPersonasCountMismatch(agentCount = 5, personaCount = 3) to
            "agents (5) does not match personas count (3)",
        ScenarioValidationMessage.InvalidTarget(label = "Phase Y", value = "everyone") to
            "Phase Y has invalid target: 'everyone'. Use 'all' or 'random_one'.",
        ScenarioValidationMessage.InvalidPairing(label = "Phase Z", value = "snake") to
            "Phase Z has invalid pairing: 'snake'. Use 'round_robin'.",
        ScenarioValidationMessage.InvalidLogic(label = "Phase W", value = "xor", allowed = "and, or") to
            "Phase W has invalid logic: 'xor'. Expected one of: and, or.",
        ScenarioValidationMessage.ActionDeltasNotDict(label = "Phase V", got = "String") to
            "Phase V: field 'action_deltas' must be a dictionary of Int values, got String",
        ScenarioValidationMessage.ActionDeltasValueNotInt(label = "Phase U", key = "score", got = "String") to
            "Phase U: action_deltas value for 'score' must be Int, got String",
        ScenarioValidationMessage.PayoffNotList(label = "Phase T", got = "Dict") to
            "Phase T: field 'payoff' must be a list of {when, points} rows, got Dict",
        ScenarioValidationMessage.PayoffRowInvalid(label = "Phase S", detail = "missing when") to
            "Phase S: each 'payoff' row needs 'when' (2 strings) and 'points' (2 ints) — missing when",
        ScenarioValidationMessage.PhaseMissingType(label = "Phase R") to
            "Phase R missing 'type'",
        ScenarioValidationMessage.PhaseInvalidType(label = "Phase Q", value = "unknown_type") to
            "Phase Q has invalid type: 'unknown_type'",
        ScenarioValidationMessage.OutputNotDict(label = "Phase P", got = "Array") to
            "Phase P: field 'output' must be a dictionary of String values, got Array",
        ScenarioValidationMessage.OutputValueNotString(label = "Phase O", key = "note", got = "Int") to
            "Phase O: output schema value for 'note' must be String, got Int",
        ScenarioValidationMessage.BranchNotArray(label = "Phase N", branch = "then") to
            "Phase N: 'then' must be an array of phase objects",
        // Preserves the embedded backtick + escaped quote byte-identically.
        ScenarioValidationMessage.ExtraDataArrayOfDictNotString(key = "teams") to
            "Top-level field 'teams': array-of-dict values must all be String. " +
                "Quote non-string values (e.g. `majority: \"1\"`).",
        ScenarioValidationMessage.ExtraDataMixedArray(key = "roles") to
            "Top-level field 'roles': mixed-type arrays are not supported. " +
                "Use a pure [String] or [[String: String]].",
        ScenarioValidationMessage.ExtraDataDictNotString(key = "scores") to
            "Top-level field 'scores': dictionary values must all be String. " +
                "Quote non-string values.",
        ScenarioValidationMessage.ExtraDataUnsupportedType(
            key = "weights", got = "Double", shapes = "[String], [[String: String]]",
        ) to
            "Top-level field 'weights' has unsupported type Double. " +
                "Supported shapes: [String], [[String: String]].",
        ScenarioValidationMessage.EventInjectMissingSource(label = "Phase M") to
            "Phase M: missing 'source'. event_inject requires a 'source' key naming a " +
                "top-level YAML field that lists the event strings.",
        ScenarioValidationMessage.EventInjectSourceEmptyStrings(label = "Phase L", source = "events") to
            "Phase L: source 'events' is empty. event_inject requires at least one string " +
                "in the list; for a single fixed event use ['only_event'].",
        ScenarioValidationMessage.EventInjectSourceWrongShape(label = "Phase K", source = "triggers") to
            "Phase K: source 'triggers' must be a list of event strings or {text, favors} " +
                "mappings; for a single fixed event use ['only_event'].",
        ScenarioValidationMessage.EventInjectSourceEmptyEvents(label = "Phase J", source = "news") to
            "Phase J: source 'news' is empty. event_inject requires at least one event " +
                "in the list; for a single fixed event use ['only_event'].",
        ScenarioValidationMessage.EventInjectEntryMissingText(label = "Phase I", source = "feed") to
            "Phase I: source 'feed' has an event entry missing a non-empty 'text'. " +
                "Dict-shaped events require 'text' (and may add 'favors').",
        ScenarioValidationMessage.EventInjectProbabilityOutOfRange(label = "Phase 5", probability = "1.5") to
            "Phase 5: probability 1.5 is out of range. Must be between 0.0 and 1.0 inclusive.",
        ScenarioValidationMessage.OutputFieldNameInvalid(label = "Phase 6", name = "感想") to
            "Phase 6: output field name '感想' must be an ASCII identifier " +
                "(letters, digits, and underscore, not starting with a digit or underscore). " +
                "Agent text values may be any language.",
        ScenarioValidationMessage.MaxSentencesOutOfRange(label = "Phase H", value = 7) to
            "Phase H: max_sentences (7) must be between 1 and 6",
    )
}
