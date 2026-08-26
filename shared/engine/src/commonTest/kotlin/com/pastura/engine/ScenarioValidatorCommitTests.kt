package com.pastura.engine

import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.SimulationError
import kotlin.test.Test
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/**
 * Strict-validation checks that fire only at commit-to-persist time
 * (`ScenarioEditorViewModel.save()`), not on every keystroke and not at
 * runtime. See `ScenarioConventions` for the canonical-field convention these
 * checks enforce.
 *
 * commonTest sibling of Swift's
 * `Pastura/PasturaTests/Engine/ScenarioValidatorTests+Commit.swift` — 29
 * tests, all 1:1 by name (with the Swift `validateForCommit_` / `validate_`
 * prefix dropped; two run-gate-leniency cases keep a disambiguating
 * `...AtRunGate` suffix instead, noted at their definitions, mirroring how
 * `ScenarioValidatorTests.kt` disambiguates its own run-gate cases) — plus two
 * Kotlin-only pins with no Swift sibling, for a suite total of 31.
 *
 * Both pins close a mechanism the ADR-023 §12 condition-4 sweep found
 * unclaimed on **both** sides;
 * [branchLabelCarriesTheParentPhaseTypeNotConditional] and
 * [acceptsCodePhaseDeclaringAStraySecondaryKey] carry the reasoning at their
 * definitions, and notes 8–9 of [ScenarioValidatorTests]' perturbation record
 * carry the measurement. That record covers this suite too — the sweep ran
 * all three validator suites as one measurement, so it is the single place
 * the commit gate's mechanism-to-claimant mapping lives.
 */
class ScenarioValidatorCommitTests {

    private val validator = ScenarioValidator()

    // region Speak phases (canonical: statement)

    @Test
    fun acceptsSpeakAllWithStatement() {
        val phase = Phase(
            type = PhaseType.SPEAK_ALL,
            prompt = "Speak.",
            outputSchema = mapOf("statement" to "string", "inner_thought" to "string"),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(phase))
        validator.validateForCommit(scenario)
    }

    @Test
    fun acceptsSpeakEachWithStatement() {
        val phase = Phase(
            type = PhaseType.SPEAK_EACH,
            prompt = "Speak.",
            outputSchema = mapOf("statement" to "string"),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(phase))
        validator.validateForCommit(scenario)
    }

    @Test
    fun rejectsSpeakAllWithoutStatement() {
        val phase = Phase(
            type = PhaseType.SPEAK_ALL,
            prompt = "Speak.",
            outputSchema = mapOf("appeal" to "string", "inner_thought" to "string"),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(phase))
        val caught = assertFailsWith<SimulationException> { validator.validateForCommit(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun rejectsSpeakEachWithBokeAlias() {
        // The legacy `boke:` alias was dropped in #309 — must now error.
        val phase = Phase(
            type = PhaseType.SPEAK_EACH,
            prompt = "Speak.",
            outputSchema = mapOf("boke" to "string"),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(phase))
        val caught = assertFailsWith<SimulationException> { validator.validateForCommit(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun rejectsSpeakAllWithMissingOutputSchema() {
        val phase = Phase(type = PhaseType.SPEAK_ALL, prompt = "Speak.")
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(phase))
        val caught = assertFailsWith<SimulationException> { validator.validateForCommit(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    // endregion

    // region Choose (canonical: action)

    @Test
    fun acceptsChooseWithAction() {
        val phase = Phase(
            type = PhaseType.CHOOSE,
            prompt = "Choose.",
            outputSchema = mapOf("action" to "string"),
            options = listOf("yes", "no"),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(phase))
        validator.validateForCommit(scenario)
    }

    @Test
    fun rejectsChooseWithFactionAlias() {
        // The kinoko gallery scenario was previously broken by `faction:` —
        // OutputSchema.from binds the GBNF enum constraint only on field name
        // `action`, and ChooseHandler reads `output.action` directly, so any
        // other name silently defaults every agent to options[0]. The
        // canonical check at commit time is the structural fix.
        val phase = Phase(
            type = PhaseType.CHOOSE,
            prompt = "Choose.",
            outputSchema = mapOf("faction" to "string"),
            options = listOf("kinoko", "takenoko"),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(phase))
        val caught = assertFailsWith<SimulationException> { validator.validateForCommit(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    // endregion

    // region Vote (canonical: vote)

    @Test
    fun acceptsVoteWithVoteField() {
        val phase = Phase(
            type = PhaseType.VOTE,
            prompt = "Vote.",
            outputSchema = mapOf("vote" to "string", "reason" to "string"),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(phase))
        validator.validateForCommit(scenario)
    }

    @Test
    fun rejectsVoteWithoutVoteField() {
        val phase = Phase(
            type = PhaseType.VOTE,
            prompt = "Vote.",
            outputSchema = mapOf("target" to "string"),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(phase))
        val caught = assertFailsWith<SimulationException> { validator.validateForCommit(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    // endregion

    // region Reflect (canonical: note, no secondary field)

    @Test
    fun acceptsReflectWithNote() {
        val phase = Phase(
            type = PhaseType.REFLECT,
            prompt = "Reflect.",
            outputSchema = mapOf("note" to "string"),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(phase))
        validator.validateForCommit(scenario)
    }

    @Test
    fun rejectsReflectWithoutNote() {
        val phase = Phase(
            type = PhaseType.REFLECT,
            prompt = "Reflect.",
            outputSchema = mapOf("memo" to "string"),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(phase))
        val caught = assertFailsWith<SimulationException> { validator.validateForCommit(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun rejectsReflectWithMissingOutputSchema() {
        val phase = Phase(type = PhaseType.REFLECT, prompt = "Reflect.")
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(phase))
        val caught = assertFailsWith<SimulationException> { validator.validateForCommit(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    // endregion

    // region Code phases (no canonical field — exempt)

    @Test
    fun acceptsCodePhases() {
        // Code phases (score_calc / summarize / assign / eliminate) emit no
        // LLM output and have no canonical primary field — they should pass
        // the commit gate without an `output:` schema.
        val phases = listOf(
            Phase(
                type = PhaseType.SPEAK_ALL,
                prompt = "Speak.",
                outputSchema = mapOf("statement" to "string"),
            ),
            Phase(type = PhaseType.SUMMARIZE, template = "Round done"),
            Phase(type = PhaseType.ELIMINATE),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = phases)
        validator.validateForCommit(scenario)
    }

    // endregion

    // region Composes with validate()

    @Test
    fun runsValidateChecksFirst() {
        // A scenario that fails the agent-count check should still throw —
        // validateForCommit composes by calling validate(_:) before adding
        // the canonical-field check.
        val phase = Phase(
            type = PhaseType.SPEAK_ALL,
            prompt = "Speak.",
            outputSchema = mapOf("statement" to "string"),
        )
        val scenario = makeValidatorScenario(agents = 0, rounds = 1, phases = listOf(phase))
        val caught = assertFailsWith<SimulationException> { validator.validateForCommit(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    // endregion

    // region Runtime path is lenient (regression guard)

    /** Swift sibling: `validate_acceptsScenarioMissingCanonicalSpeakField`. */
    @Test
    fun acceptsScenarioMissingCanonicalSpeakFieldAtRunGate() {
        // The regular `validate(_:)` path (used by `SimulationRunner`) must
        // NOT enforce the canonical-field rule — only `validateForCommit`
        // does. Otherwise a scenario authored before this convention landed
        // could refuse to run.
        val phase = Phase(
            type = PhaseType.SPEAK_ALL,
            prompt = "Speak.",
            outputSchema = mapOf("appeal" to "string"),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(phase))
        validator.validate(scenario)
    }

    // endregion

    // region Conditional sub-phases (canonical-field check recurses depth-1)

    @Test
    fun rejectsSpeakAllInsideThenBranchMissingStatement() {
        // Regression: `validateCanonicalPrimaryFields` originally walked only
        // `scenario.phases` and ignored `thenPhases` / `elsePhases`. A
        // conditional branch with a misnamed canonical field would slip past
        // the commit gate and recreate the exact "speak_all missing statement"
        // bug class #318 was meant to prevent. Recursion is depth-1 by validator
        // construction so termination is trivial.
        val nested = Phase(
            type = PhaseType.SPEAK_ALL,
            prompt = "Inner.",
            outputSchema = mapOf("appeal" to "string"),
        )
        val conditional = Phase(
            type = PhaseType.CONDITIONAL,
            condition = "max_score >= 1",
            thenPhases = listOf(nested),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(conditional))
        val caught = assertFailsWith<SimulationException> { validator.validateForCommit(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun rejectsVoteInsideElseBranchMissingVoteField() {
        val nested = Phase(
            type = PhaseType.VOTE,
            prompt = "Vote.",
            outputSchema = mapOf("target" to "string"),
        )
        val conditional = Phase(
            type = PhaseType.CONDITIONAL,
            condition = "max_score >= 1",
            thenPhases = listOf(Phase(type = PhaseType.SUMMARIZE, template = "ok")),
            elsePhases = listOf(nested),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(conditional))
        val caught = assertFailsWith<SimulationException> { validator.validateForCommit(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun acceptsSpeakAllInsideThenBranchWithStatement() {
        val nested = Phase(
            type = PhaseType.SPEAK_ALL,
            prompt = "Inner.",
            outputSchema = mapOf("statement" to "string"),
        )
        val conditional = Phase(
            type = PhaseType.CONDITIONAL,
            condition = "max_score >= 1",
            thenPhases = listOf(nested),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(conditional))
        validator.validateForCommit(scenario)
    }

    // endregion

    // region Error message includes phase index + canonical field name

    @Test
    fun errorMentionsPhaseAndCanonicalField() {
        val phase = Phase(
            type = PhaseType.SPEAK_ALL,
            prompt = "Speak.",
            outputSchema = mapOf("appeal" to "string"),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(phase))
        val caught = assertFailsWith<SimulationException> { validator.validateForCommit(scenario) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        // Partial-match per CLAUDE.md i18n rule — assert the message names
        // the canonical field, phase type, and 1-based phase index, not exact
        // wording. The phase-index part of the contract is what lets a user
        // disambiguate when several phases share a type.
        val message = error.message
        assertTrue(message.contains("statement"))
        assertTrue(message.contains("speak_all"))
        assertTrue(message.contains("Phase 1"))
    }

    // endregion

    // region Canonical thought (secondary) field
    //
    // Companion to the primary-field checks above. The secondary field is
    // OPTIONAL, but when a known secondary key (`inner_thought` / `reason`)
    // is declared it must be the phase's canonical one
    // (`ScenarioConventions.thoughtField(for:)`): vote→reason,
    // speak*/choose→inner_thought. This keeps the streaming THINKING source
    // (`OutputSchema.thoughtFieldName`, schema-driven) and the committed
    // source (`TurnOutput.secondaryText`, phase-hardcoded) reading the same
    // key — a choose authored with `reason` streamed live but went blank on
    // commit (#760).

    @Test
    fun acceptsChooseWithInnerThought() {
        val phase = Phase(
            type = PhaseType.CHOOSE,
            prompt = "Choose.",
            outputSchema = mapOf("action" to "string", "inner_thought" to "string"),
            options = listOf("yes", "no"),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(phase))
        validator.validateForCommit(scenario)
    }

    @Test
    fun rejectsChooseWithReason() {
        // The #760 root case: choose authored `reason` (not canonical
        // `inner_thought`). Streaming surfaced it but the committed row read
        // the empty `inner_thought`, so the reasoning vanished on commit.
        val phase = Phase(
            type = PhaseType.CHOOSE,
            prompt = "Choose.",
            outputSchema = mapOf("action" to "string", "reason" to "string"),
            options = listOf("kinoko", "takenoko"),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(phase))
        val caught = assertFailsWith<SimulationException> { validator.validateForCommit(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun rejectsSpeakAllWithReason() {
        // Speak phases are canonical-`inner_thought` too, so a stray `reason`
        // is rejected — symmetric to the choose case.
        val phase = Phase(
            type = PhaseType.SPEAK_ALL,
            prompt = "Speak.",
            outputSchema = mapOf("statement" to "string", "reason" to "string"),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(phase))
        val caught = assertFailsWith<SimulationException> { validator.validateForCommit(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun rejectsVoteWithInnerThought() {
        // Vote's canonical secondary is `reason`; `inner_thought` is the wrong
        // key for vote (the inverse of the choose/speak direction).
        val phase = Phase(
            type = PhaseType.VOTE,
            prompt = "Vote.",
            outputSchema = mapOf("vote" to "string", "inner_thought" to "string"),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(phase))
        val caught = assertFailsWith<SimulationException> { validator.validateForCommit(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun rejectsChooseWithBothInnerThoughtAndReason() {
        // The rule must inspect EVERY declared known-secondary key, not just
        // `OutputSchema.thoughtFieldName`'s priority pick (which returns
        // `inner_thought` here and would miss the stray `reason`).
        val phase = Phase(
            type = PhaseType.CHOOSE,
            prompt = "Choose.",
            outputSchema = mapOf(
                "action" to "string",
                "inner_thought" to "string",
                "reason" to "string",
            ),
            options = listOf("yes", "no"),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(phase))
        val caught = assertFailsWith<SimulationException> { validator.validateForCommit(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun acceptsChooseWithNoSecondaryField() {
        // Secondary is optional — only the canonical primary (`action`) plus
        // no thought field still passes.
        val phase = Phase(
            type = PhaseType.CHOOSE,
            prompt = "Choose.",
            outputSchema = mapOf("action" to "string"),
            options = listOf("yes", "no"),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(phase))
        validator.validateForCommit(scenario)
    }

    @Test
    fun acceptsUnknownSecondaryKey() {
        // The rule keys only on `OutputSchema.knownSecondaryKeys`
        // (inner_thought / reason). A non-known extra field (`notes`) is not a
        // secondary key and must not trip the check.
        val phase = Phase(
            type = PhaseType.CHOOSE,
            prompt = "Choose.",
            outputSchema = mapOf("action" to "string", "notes" to "string"),
            options = listOf("yes", "no"),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(phase))
        validator.validateForCommit(scenario)
    }

    /** Swift sibling: `validate_acceptsChooseWithReason`. */
    @Test
    fun acceptsChooseWithReasonAtRunGate() {
        // Runtime `validate(_:)` stays lenient — only `validateForCommit`
        // enforces the canonical thought-field rule, so a scenario authored
        // before this convention still runs.
        val phase = Phase(
            type = PhaseType.CHOOSE,
            prompt = "Choose.",
            outputSchema = mapOf("action" to "string", "reason" to "string"),
            options = listOf("kinoko", "takenoko"),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(phase))
        validator.validate(scenario)
    }

    @Test
    fun rejectsChooseWithReasonInsideThenBranch() {
        // Recurses into conditional branches, same as the primary-field check.
        val nested = Phase(
            type = PhaseType.CHOOSE,
            prompt = "Choose.",
            outputSchema = mapOf("action" to "string", "reason" to "string"),
            options = listOf("yes", "no"),
        )
        val conditional = Phase(
            type = PhaseType.CONDITIONAL,
            condition = "max_score >= 1",
            thenPhases = listOf(nested),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(conditional))
        val caught = assertFailsWith<SimulationException> { validator.validateForCommit(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun thoughtFieldErrorMentionsPhaseAndKeys() {
        val phase = Phase(
            type = PhaseType.CHOOSE,
            prompt = "Choose.",
            outputSchema = mapOf("action" to "string", "reason" to "string"),
            options = listOf("yes", "no"),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(phase))
        val caught = assertFailsWith<SimulationException> { validator.validateForCommit(scenario) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        // Partial-match per CLAUDE.md i18n rule — the message names the
        // canonical field, the offending field, the phase type, and the
        // 1-based phase index.
        val message = error.message
        assertTrue(message.contains("inner_thought"))
        assertTrue(message.contains("reason"))
        assertTrue(message.contains("choose"))
        assertTrue(message.contains("Phase 1"))
    }

    // endregion

    // region Kotlin-only pins (no Swift sibling)

    /**
     * Pins the thought-field rule's code-phase exemption:
     * [com.pastura.models.ScenarioConventions.thoughtField] returns `null` for
     * every code phase, so a code phase declaring a known secondary key is
     * accepted rather than measured against a canonical it does not have.
     *
     * Added because the ADR-023 §12 condition-4 sweep found the exemption's
     * `?: return` had **no** claimant on either side — no Swift test constructs
     * a code phase with an `output:` block at all, so replacing the early
     * return with a fallback canonical reddened nothing. The fixture is
     * deliberately unrealistic (`summarize` emits no LLM output, so authoring
     * an `output:` for it is a mistake); it exists to make the exemption
     * observable, not to bless the shape.
     */
    @Test
    fun acceptsCodePhaseDeclaringAStraySecondaryKey() {
        val scenario = makeValidatorScenario(
            agents = 2,
            rounds = 1,
            phases = listOf(
                Phase(
                    type = PhaseType.SPEAK_ALL,
                    prompt = "Speak.",
                    outputSchema = mapOf("statement" to "string"),
                ),
                Phase(
                    type = PhaseType.SUMMARIZE,
                    template = "Round done",
                    outputSchema = mapOf("reason" to "string"),
                ),
            ),
        )
        validator.validateForCommit(scenario)
    }


    /**
     * Pins the phase-type-derived branch parent label: the canonical-field
     * descent visits `thenPhases` / `elsePhases` for **every** phase type, not
     * just `conditional`, so a non-conditional carrier must render its own
     * `serialName()` in the label — never a hardcoded `(conditional)`.
     */
    @Test
    fun branchLabelCarriesTheParentPhaseTypeNotConditional() {
        val scenario = makeValidatorScenario(
            agents = 2,
            rounds = 1,
            phases = listOf(
                Phase(
                    type = PhaseType.SPEAK_ALL,
                    outputSchema = mapOf("statement" to "string"),
                    thenPhases = listOf(
                        Phase(
                            type = PhaseType.SPEAK_ALL,
                            outputSchema = mapOf("appeal" to "string"),
                        ),
                    ),
                ),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validateForCommit(scenario) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.startsWith("Phase 1 (speak_all) then[1] "))
    }

    // endregion
}
