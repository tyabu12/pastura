package com.pastura.engine

import com.pastura.models.AnyCodableValue
import com.pastura.models.AssignTarget
import com.pastura.models.Persona
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import com.pastura.models.SimulationError
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/**
 * commonTest sibling of Swift's `ScenarioValidatorTests.swift`,
 * `ScenarioValidatorTests+Language.swift`, `ScenarioValidatorTests+MaxSentences.swift`,
 * and `ScenarioValidatorTests+OutputFieldNames.swift`
 * (`Pastura/PasturaTests/Engine/`) — 63 tests: 62 are 1:1 by name with those four
 * files, plus one Kotlin-only pin (next paragraph).
 *
 * Three tests here and in [ConditionalValidatorTests] have **no Swift sibling** —
 * [rejectsEventInjectWithEmptyDictSource],
 * [ConditionalValidatorTests.rejectsMalformedConditionWithPhaseLabelPrefix], and
 * [ConditionalValidatorTests.rejectsEmptyConditionWithMissingIfMessage]. They were
 * added because the sweep below found their mechanisms uncovered on **both** sides;
 * see note 3.
 *
 * ## ADR-023 §12 condition-4 perturbation record
 *
 * Each mechanism of
 * `shared/engine/src/commonMain/kotlin/com/pastura/engine/ScenarioValidator.kt` was
 * broken in isolation and the named **dedicated claimant** — a test that detects the
 * break through **its own** assertion — confirmed to redden. Every mutation's anchor
 * count was asserted before applying (all 50 matched **exactly once**) and the
 * mutated text re-read to confirm it landed; a `replace` that silently no-ops leaves
 * the original behaviour and reads as verified. The file was restored byte-identically
 * after each run (`git diff --exit-code` on the file after the last revert). The
 * unmutated baseline was measured green (**120 tests across the three suites**)
 * immediately before the first mutation and again after the last revert, so every
 * reddening below is signal rather than pre-existing noise. Counts are measured, not
 * derived — re-measure rather than reason if you change a fixture. Measured
 * 2026-08-26, #1552 (PR B2; the run-gate rows were first measured in PR B1 and are
 * re-measured here — see note 1).
 *
 * The sweep ran **only** these three suites — [ScenarioValidatorTests],
 * [ConditionalValidatorTests], and [ScenarioValidatorCommitTests]. That is sufficient
 * rather than a shortcut: `grep` confirms no other `shared/engine` code constructs
 * [ScenarioValidator] — the gate is deliberately not wired into the engine yet (see
 * the class KDoc on [ScenarioValidator]), so no other suite could redden.
 *
 * | Mechanism broken | Mutation | Dedicated claimant | Incidental |
 * |---|---|---|---|
 * | `language` gate | `scenario.language !in ACCEPTED_LANGUAGES` → `in` | [rejectsInvalidLanguage] | 68 — every valid-language fixture then throws |
 * | `simulationLanguage` null-accept arm | `val simulationLanguage = scenario.simulationLanguage` → `… ?: "fr"` | [acceptsNilSimulationLanguage] | 66 — every fixture leaves it null; see note 2 |
 * | …membership polarity | `simulationLanguage !in …` → `in` | [rejectsInvalidSimulationLanguage] | none |
 * | `agentCount` ≥ 2 | `if (scenario.agentCount < 2)` → `if (false)` | [rejectsZeroAgents], [rejectsSingleAgent] | none |
 * | `agentCount` ≤ 10 | `if (scenario.agentCount > 10)` → `if (false)` | [rejectsMoreThan10Agents] | none |
 * | persona count matches `agentCount` | `!=` → `==` | [rejectsPersonaCountMismatch] | 67 — every matched-persona fixture then throws |
 * | `rounds` ≤ 30 | `if (scenario.rounds > 30)` → `if (false)` | [rejectsMoreThan30Rounds] | none |
 * | `logWindow` ≥ 1 | `logWindow < 1` → `logWindow < 0` (not `if (false)`; see note 2) | [rejectsZeroLogWindow] | none |
 * | Estimate > 100 is an error | `if (estimated > 100)` → `if (false)` | [errorsWhenInferencesExceed100] | none |
 * | Estimate > 50 is a warning | `if (estimated > 50)` → `if (false)` | [warnsWhenInferencesExceed50] | none |
 * | `validatePhases` ASSIGN arm | → `Unit` | all 7 top-level assign cases, e.g. [rejectsAssignAllWithDictionarySource] | none |
 * | `validatePhases` CONDITIONAL arm | → `Unit` | all 22 rejecting [ConditionalValidatorTests] cases, plus [rejectsOutOfRangeInNestedBranch], [rejectsCjkOutputKeyInsideConditionalBranch], [rejectsEventInjectWithEmptyArraySourceInsideConditional] | none — all 25 fail on their own assertion |
 * | `validatePhases` REFLECT arm | → `Unit` | [rejectsReflectWithoutNoteOutputAtRunGate] | none |
 * | `validatePhases` WHISPER arm | → `Unit` | [rejectsWhisperWithoutStatementOutputAtRunGate] | none |
 * | `validatePhases` RELATIONSHIP_UPDATE arm | → `Unit` | [rejectsRelationshipUpdateWithNoRuleAtRunGate], [rejectsRelationshipUpdateWithEmptyActionDeltas] | none |
 * | `validatePhases` EVENT_INJECT arm | → `Unit` | all 9 top-level event_inject cases, e.g. [rejectsEventInjectWithStringSource] | none |
 * | `max_sentences` range | `value !in 1..6` → `!in 0..7` | [rejectsMaxSentencesBelowRange], [rejectsMaxSentencesAboveRange], [rejectsOutOfRangeInNestedBranch] | none |
 * | …checked at the **branch** site too | the `validateMaxSentences(subPhase, subLabel)` call deleted (branch site only) | [rejectsOutOfRangeInNestedBranch] | none |
 * | Empty-`if` guard | `if (trimmedCondition.isEmpty())` → `if (false)` | [ConditionalValidatorTests.rejectsEmptyConditionWithMissingIfMessage] — **added**, note 3 | none |
 * | Conditional parse pre-flight | the `ConditionEvaluator().parse(…)` call removed | [ConditionalValidatorTests.rejectsMalformedConditionAtValidateTime], [ConditionalValidatorTests.rejectsDanglingCombinatorAtValidateTime], [ConditionalValidatorTests.rejectsMalformedConditionWithPhaseLabelPrefix] | none |
 * | `"$phaseLabel: "` rewrap of a parse error | the prefix dropped | [ConditionalValidatorTests.rejectsMalformedConditionWithPhaseLabelPrefix] — **added**, note 3 | none |
 * | Empty-branches guard | `if (thenCount == 0 && elseCount == 0)` → `if (false)` | [ConditionalValidatorTests.rejectsBothBranchesEmpty], [ConditionalValidatorTests.rejectsBothBranchesNil] | none |
 * | Depth guard | `if (depth > 0)` → `if (false)` | *(none — expected green, note 4)* | none |
 * | Branch rejects CONDITIONAL | arm → `Unit` | [ConditionalValidatorTests.rejectsNestedConditionalInThenBranch], [ConditionalValidatorTests.rejectsNestedConditionalInElseBranch] | none |
 * | Branch rejects REFLECT | arm → `Unit` | [ConditionalValidatorTests.rejectsReflectInThenBranch], [ConditionalValidatorTests.rejectsReflectInElseBranch] | none |
 * | Branch rejects WHISPER | arm → `Unit` | [ConditionalValidatorTests.rejectsWhisperInThenBranch], [ConditionalValidatorTests.rejectsWhisperInElseBranch] | none |
 * | Branch rejects RELATIONSHIP_UPDATE | arm → `Unit` | [ConditionalValidatorTests.rejectsRelationshipUpdateInThenBranch], [ConditionalValidatorTests.rejectsRelationshipUpdateInElseBranch] | none |
 * | Branch rejects NARRATE | arm → `Unit` | [ConditionalValidatorTests.rejectsNarrateInThenBranch], [ConditionalValidatorTests.rejectsNarrateInElseBranch] | none |
 * | Branch ASSIGN shape check | arm → `Unit` | [ConditionalValidatorTests.rejectsAssignShapeMismatchInThenBranch] | none |
 * | Branch EVENT_INJECT shape check | arm → `Unit` | [ConditionalValidatorTests.rejectsEventInjectInThenBranchWithMissingSource], [ConditionalValidatorTests.rejectsEventInjectInElseBranchWithProbabilityOutOfRange], [rejectsEventInjectWithEmptyArraySourceInsideConditional] | none |
 * | reflect `note` guard | `outputSchema["note"] == null` → `false` | [rejectsReflectWithoutNoteOutputAtRunGate] | none |
 * | whisper `statement` guard | `outputSchema["statement"] == null` → `false` | [rejectsWhisperWithoutStatementOutputAtRunGate] | none |
 * | relationship_update no-rule guard | `!hasVoteRule && !hasActionRule` → `false` | [rejectsRelationshipUpdateWithNoRuleAtRunGate], [rejectsRelationshipUpdateWithEmptyActionDeltas] | none |
 * | assign source-missing guard | the `?: throw …SourceNotFound` → `?: return` | [rejectsAssignAllWhenSourceKeyMissingFromExtraData], [rejectsAssignRandomOneWhenSourceKeyMissingFromExtraData] | none |
 * | assign ALL-arm rejection | grouped-shape arm → `Unit` | [rejectsAssignAllWithArrayOfDictionariesSource], [rejectsAssignAllWithDictionarySource], [rejectAssignAllWithBadShapeIncludesPhaseIndexAndSourceKey], [ConditionalValidatorTests.rejectsAssignShapeMismatchInThenBranch] | none |
 * | assign RANDOM_ONE-arm rejection | ungrouped-shape arm → `Unit` | [rejectsAssignRandomOneWithArraySource], [rejectsAssignRandomOneWithStringSource] | none |
 * | event_inject missing-`source` guard | `if (sourceKey.isEmpty())` → `if (false)` | [rejectsEventInjectWithMissingSource] | none — see note 5 |
 * | event_inject source-not-found guard | the `?: throw …SourceNotFound` → `?: return` | [rejectsEventInjectWhenSourceKeyAbsentFromExtraData], [ConditionalValidatorTests.rejectsEventInjectInThenBranchWithMissingSource] | none |
 * | event_inject empty-string-list guard | `if (sourceValue.value.isEmpty())` → `if (false)` | [rejectsEventInjectWithEmptyArraySource], [rejectsEventInjectWithEmptyArraySourceInsideConditional] | none |
 * | event_inject wrong-shape arm | string / dictionary arm → `Unit` | [rejectsEventInjectWithStringSource], [rejectsEventInjectWithDictionarySource] | none |
 * | event_inject empty-**events** guard (dict shape) | `if (entries.isEmpty())` → `if (false)` | [rejectsEventInjectWithEmptyDictSource] — **added**, note 3 | none |
 * | event_inject entry-missing-`text` guard | `if (entries.any { … })` → `if (false)` | [rejectsEventInjectDictEntryMissingText] | none |
 * | `probability` range | `value !in 0.0..1.0` → `!in -1.0..2.0` | [rejectsEventInjectWithProbabilityAboveOne], [rejectsEventInjectWithNegativeProbability], [ConditionalValidatorTests.rejectsEventInjectInElseBranchWithProbabilityOutOfRange] | none |
 * | Output-field-name check at the **top-level** site | the `validateOutputFieldNames(phase, label)` call deleted | [rejectsCjkPrimaryOutputKey], [rejectsCjkSecondaryOutputKey], [rejectsNonAsciiLatinAndEmojiOutputKeys] | none |
 * | …at the **branch** site | the `validateOutputFieldNames(subPhase, subLabel)` call deleted | [rejectsCjkOutputKeyInsideConditionalBranch] | none |
 * | The field-name predicate itself | `firstOrNull { !isValidFieldName(it) }` → `firstOrNull { false }` | all four of the above | none |
 * | `Long.clampToInt` narrowing | `coerceAtMost(Int.MAX_VALUE.toLong())` dropped | *(none — expected green, note 6)* | none |
 * | reflect message `type` arg | `type = phase.type.serialName()` → `"x"` | *(none — expected green, note 7)* | none |
 * | whisper message `type` arg | same, whisper site | *(none — expected green, note 7)* | none |
 * | relationship_update message `type` arg | same, relationship_update site | *(none — expected green, note 7)* | none |
 *
 * ### Commit gate ([ScenarioValidator.validateForCommit], PR B2)
 *
 * Same driver, same run, same baseline. Every claimant below lives in
 * [ScenarioValidatorCommitTests]; the class prefix is dropped for width.
 *
 * | Mechanism broken | Mutation | Dedicated claimant | Incidental |
 * |---|---|---|---|
 * | Commit gate runs [validate]'s checks first | `val result = validate(scenario)` → a literal `ValidationResult` | `runsValidateChecksFirst` | none |
 * | …then runs the canonical-field check at all | the `validateCanonicalFields(scenario)` call deleted | all 15 rejecting commit cases, e.g. `rejectsSpeakAllWithoutStatement` | none — all 15 fail on their own assertion |
 * | Canonical **primary** field required | `if (schema[canonical] == null)` → `if (false)` | 9 cases, e.g. `rejectsVoteWithoutVoteField`, `rejectsChooseWithFactionAlias` | none |
 * | …and code phases exempt from it | the primary `?: return` → `?: "statement"` | `acceptsCodePhases`, `acceptsSpeakAllInsideThenBranchWithStatement`, `acceptsCodePhaseDeclaringAStraySecondaryKey` | none |
 * | Canonical **thought** field enforced | `if (schema[key] != null && key != canonical)` → `if (false)` | 6 cases, e.g. `rejectsVoteWithInnerThought`, `rejectsSpeakAllWithReason` | none |
 * | …checked for **every** declared known-secondary key, not the priority pick | the loop iterates only `knownSecondaryKeys.firstOrNull { schema[it] != null }` | `rejectsChooseWithBothInnerThoughtAndReason` | none |
 * | …and code phases exempt from it | the thought `?: return` → `?: "inner_thought"` | `acceptsCodePhaseDeclaringAStraySecondaryKey` — **added**, note 8 | none |
 * | Descent into `then:` | the `validateBranchCanonicalFields(phase.thenPhases, …)` call deleted | `rejectsSpeakAllInsideThenBranchMissingStatement`, `rejectsChooseWithReasonInsideThenBranch`, `branchLabelCarriesTheParentPhaseTypeNotConditional` | none |
 * | Descent into `else:` | same, else site | `rejectsVoteInsideElseBranchMissingVoteField` | none |
 * | Parent label derived from the phase type | the `serialName()` interpolation → a hardcoded `"(conditional)"` | `branchLabelCarriesTheParentPhaseTypeNotConditional` — **added**, note 9 | none |
 * | Sub-phase index is 1-based | `subIndex + 1` → `subIndex` in the branch label | `branchLabelCarriesTheParentPhaseTypeNotConditional` | none |
 *
 * Nine things this table encodes that are easy to misread:
 *
 * 1. ⚠️ **Re-measure the whole table when you add a fixture, not the row you were
 *    thinking about** (the lesson [InferenceEstimatorTests]' record was corrected
 *    for). The second sweep proved it once: adding the three tests in note 3 moved
 *    three `Incidental` / claimant cells that had nothing to do with them
 *    (`validatePhases` CONDITIONAL 23 → 25 red, EVENT_INJECT 8 → 9, parse pre-flight
 *    2 → 3). This third sweep (PR B2) proved it twice over, at a longer range: a
 *    whole new suite chaining through [validate] moved the three global-gate rows
 *    and nothing else (`language` 53 → 68 red, `simulationLanguage` null-accept
 *    51 → 66, persona count 52 → 67 — each gaining exactly the accepting
 *    commit-gate fixtures), and then adding the single test in note 8 moved five
 *    more cells, three of them in rows that test has nothing to do with. Every row
 *    above was re-measured after each landing; none of the remaining run-gate rows
 *    moved, which is a measurement, not an assumption.
 * 2. **Two mutations do not compile in their obvious form, and the substitutes are
 *    not equivalent.** `if (false)` on the `logWindow` and `simulationLanguage`
 *    guards drops the smart cast their `!= null &&` left arm provides, so the throw
 *    argument stops type-checking — the run then reddens *nothing* because no test
 *    executes, which is a measurement defect, not a green. Both were re-run with
 *    compiling substitutes (`< 0`, and an `?: "fr"` on the binding) that break the
 *    same arm. A row that reports zero failures is only evidence when the suite
 *    actually ran; the driver asserts a non-zero test count for that reason.
 * 3. **Three mechanisms had no claimant on the first sweep, and the Swift suite has
 *    none either** — verified by grep, not assumed. Rather than paper over them:
 *    [rejectsEventInjectWithEmptyDictSource] (the dict-shaped source's own
 *    empty-list guard — only the string shape was covered),
 *    [ConditionalValidatorTests.rejectsMalformedConditionWithPhaseLabelPrefix], and
 *    [ConditionalValidatorTests.rejectsEmptyConditionWithMissingIfMessage]. The last
 *    two share one cause worth stating: `ConditionEvaluator.parse` throws the *same*
 *    `SimulationError.ScenarioValidationFailed` the validator's own guards throw, so
 *    every pre-existing test that asserts only the error **type** is blind to which
 *    layer produced it. Only a message assertion separates them.
 * 4. **The depth guard is unreachable, and that is the finding.** `validateBranch`
 *    rejects a nested `conditional` outright, so `validateConditionalPhase` is only
 *    ever entered with `depth = 0` and no fixture can reach `depth > 0`. It is
 *    defensive parity with the Swift original, not dead code to delete — but nothing
 *    here watches it.
 * 5. **The event_inject missing-`source` row is a claimant only because its test
 *    asserts the message.** With the guard disabled, the empty key falls through to
 *    the source-not-found lookup and still throws, so an error-type-only assertion
 *    would have stayed green; [rejectsEventInjectWithMissingSource] reddens on its
 *    `contains("missing 'source'")` line. Same mechanism as note 3, caught in time.
 * 6. **`clampToInt` is expected green.** Both call sites are documented as
 *    display-only (the `> 100` throw has already fired, and the `> 50` band cannot
 *    exceed `Int.MAX_VALUE`), so no reachable input distinguishes the clamp from a
 *    bare `toInt()`.
 * 7. **The three `serialName()` rows are an acknowledged gap, not a covered
 *    mechanism.** Only a message-inspecting test could see the phase-type token, and
 *    the reflect / whisper / relationship_update rejection tests assert the phase
 *    label and the missing field name but never the type. A swapped or hardcoded
 *    `type` argument would ship silently. Closing it (one `contains("reflect")`
 *    per test) was declined for Swift parity — the siblings assert type only —
 *    not overlooked.
 * 8. **The thought rule's code-phase exemption had no claimant on either side.**
 *    `ScenarioConventions.thoughtField` returns `null` for every code phase, so the
 *    `?: return` is what keeps a code phase from being measured against a canonical
 *    it does not have — but no Swift test constructs a code phase with an `output:`
 *    block at all, so replacing the early return with a fallback canonical reddened
 *    nothing. Rather than paper over it (note 3's precedent),
 *    `ScenarioValidatorCommitTests.acceptsCodePhaseDeclaringAStraySecondaryKey` was
 *    added. Its fixture is deliberately unrealistic — a `summarize` emits no LLM
 *    output, so authoring an `output:` for it is a mistake — and exists to make the
 *    exemption observable, not to bless the shape.
 * 9. **The branch-label rows are the port's one behavioural near-miss, caught here.**
 *    Swift's `validateCanonicalFields(_:)` descends into `then:` / `else:` for
 *    *every* phase type, unlike the run gate's [validatePhases], which reaches
 *    branches only through its `CONDITIONAL` arm. All three Swift branch cases build
 *    a `.conditional` parent, so a Kotlin port that hardcoded `"(conditional)"` into
 *    the parent label would have passed the whole 1:1 transcription — and diverged
 *    from Swift on any non-conditional phase carrying `thenPhases`, message text
 *    only, with no gate able to see it (a rejected scenario produces no parity
 *    transcript). `branchLabelCarriesTheParentPhaseTypeNotConditional` is the pin;
 *    it has no Swift sibling because no Swift test can distinguish the two shapes.
 */
class ScenarioValidatorTests {

    private val validator = ScenarioValidator()

    // region Core: agent count / round count / smoke

    @Test
    fun acceptsValidScenario() {
        val scenario = makeValidatorScenario(
            agents = 5,
            rounds = 3,
            phases = listOf(Phase(type = PhaseType.SPEAK_ALL)),
        )
        val result = validator.validate(scenario)
        assertTrue(result.warnings.isEmpty())
        assertEquals(15L, result.estimatedInferences)
    }

    @Test
    fun rejectsZeroAgents() {
        val scenario = makeValidatorScenario(
            agents = 0,
            rounds = 1,
            phases = listOf(Phase(type = PhaseType.SPEAK_ALL)),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun rejectsSingleAgent() {
        val scenario = makeValidatorScenario(
            agents = 1,
            rounds = 1,
            phases = listOf(Phase(type = PhaseType.SPEAK_ALL)),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun acceptsExactlyTwoAgents() {
        val scenario = makeValidatorScenario(
            agents = 2,
            rounds = 1,
            phases = listOf(Phase(type = PhaseType.SPEAK_ALL)),
        )
        val result = validator.validate(scenario)
        assertTrue(result.warnings.isEmpty())
    }

    @Test
    fun rejectsMoreThan10Agents() {
        val scenario = makeValidatorScenario(
            agents = 11,
            rounds = 1,
            phases = listOf(Phase(type = PhaseType.SPEAK_ALL)),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun rejectsMoreThan30Rounds() {
        val scenario = makeValidatorScenario(
            agents = 2,
            rounds = 31,
            phases = listOf(Phase(type = PhaseType.SPEAK_ALL)),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    // endregion

    // region log_window (#907)

    @Test
    fun rejectsZeroLogWindow() {
        val scenario = makeLogWindowScenario(logWindow = 0)
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun acceptsLogWindowOfOne() {
        val scenario = makeLogWindowScenario(logWindow = 1)
        val result = validator.validate(scenario)
        assertTrue(result.warnings.isEmpty())
    }

    @Test
    fun acceptsNilLogWindow() {
        val scenario = makeLogWindowScenario(logWindow = null)
        val result = validator.validate(scenario)
        assertTrue(result.warnings.isEmpty())
    }

    @Test
    fun warnsWhenInferencesExceed50() {
        // 10 agents × (speak_all + vote) × 3 rounds = 60
        val scenario = makeValidatorScenario(
            agents = 10,
            rounds = 3,
            phases = listOf(Phase(type = PhaseType.SPEAK_ALL), Phase(type = PhaseType.VOTE)),
        )
        val result = validator.validate(scenario)
        assertTrue(result.warnings.isNotEmpty())
        assertEquals(60L, result.estimatedInferences)
    }

    @Test
    fun errorsWhenInferencesExceed100() {
        // 10 agents × (speak_all + speak_each(3) + vote) × 3 rounds = 150
        val scenario = makeValidatorScenario(
            agents = 10,
            rounds = 3,
            phases = listOf(
                Phase(type = PhaseType.SPEAK_ALL),
                Phase(type = PhaseType.SPEAK_EACH, subRounds = 3),
                Phase(type = PhaseType.VOTE),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun returnsEstimatedInferences() {
        val scenario = makeValidatorScenario(
            agents = 5,
            rounds = 2,
            phases = listOf(Phase(type = PhaseType.SPEAK_ALL), Phase(type = PhaseType.VOTE)),
        )
        val result = validator.validate(scenario)
        assertEquals(20L, result.estimatedInferences)
    }

    @Test
    fun reflectPhaseAddsAgentCountPerRound() {
        // reflect costs one inference per agent per round (like speak_all / vote).
        // 5 agents × (speak_all + reflect) × 2 rounds = 20.
        val scenario = makeValidatorScenario(
            agents = 5,
            rounds = 2,
            phases = listOf(
                Phase(type = PhaseType.SPEAK_ALL),
                Phase(type = PhaseType.REFLECT, outputSchema = mapOf("note" to "string")),
            ),
        )
        val result = validator.validate(scenario)
        assertEquals(20L, result.estimatedInferences)
    }

    @Test
    fun rejectsReflectWithoutNoteOutputAtRunGate() {
        // Run-gate strictness beyond sibling LLM phases: a schema-less reflect is
        // a pure no-op inference (nothing stored, no visible symptom), so
        // `validate` — not just `validateForCommit` — requires the `note` field.
        val scenario = makeValidatorScenario(
            agents = 2,
            rounds = 1,
            phases = listOf(Phase(type = PhaseType.REFLECT)),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun acceptsReflectWithExtraOutputFieldAlongsideNote() {
        // Only `note` presence is required at the run gate; additional fields
        // (unusual but legal) do not trip it.
        val scenario = makeValidatorScenario(
            agents = 2,
            rounds = 1,
            phases = listOf(
                Phase(
                    type = PhaseType.REFLECT,
                    outputSchema = mapOf("note" to "string", "mood" to "string"),
                ),
            ),
        )
        validator.validate(scenario)
    }

    // endregion

    // region whisper (#908)

    @Test
    fun rejectsWhisperWithoutStatementOutputAtRunGate() {
        // Like reflect, a whisper without its canonical `statement` output burns
        // one inference per participant and stores nothing user-visible, so
        // `validate` (the run gate, not just `validateForCommit`) requires it.
        val scenario = makeValidatorScenario(
            agents = 2,
            rounds = 1,
            phases = listOf(Phase(type = PhaseType.WHISPER)),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun acceptsWhisperWithStatementOutput() {
        val scenario = makeValidatorScenario(
            agents = 2,
            rounds = 1,
            phases = listOf(
                Phase(type = PhaseType.WHISPER, outputSchema = mapOf("statement" to "string")),
            ),
        )
        validator.validate(scenario)
    }

    // endregion

    // region relationship_update (#910)

    @Test
    fun rejectsRelationshipUpdateWithNoRuleAtRunGate() {
        // A relationship_update with neither `vote_against` nor `action_deltas` is
        // a pure no-op (reads signals, applies zero deltas, injects nothing), so
        // the run gate requires at least one rule — like reflect/whisper shape.
        val scenario = makeValidatorScenario(
            agents = 2,
            rounds = 1,
            phases = listOf(Phase(type = PhaseType.RELATIONSHIP_UPDATE)),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun acceptsRelationshipUpdateWithVoteRuleOnly() {
        val scenario = makeValidatorScenario(
            agents = 2,
            rounds = 1,
            phases = listOf(Phase(type = PhaseType.RELATIONSHIP_UPDATE, voteAgainst = -1)),
        )
        validator.validate(scenario)
    }

    @Test
    fun acceptsRelationshipUpdateWithActionRuleOnly() {
        val scenario = makeValidatorScenario(
            agents = 2,
            rounds = 1,
            phases = listOf(
                Phase(
                    type = PhaseType.RELATIONSHIP_UPDATE,
                    actionDeltas = mapOf("cooperate" to 1),
                ),
            ),
        )
        validator.validate(scenario)
    }

    @Test
    fun rejectsRelationshipUpdateWithEmptyActionDeltas() {
        // An empty `action_deltas: {}` map counts as no rule — same no-op shape.
        val scenario = makeValidatorScenario(
            agents = 2,
            rounds = 1,
            phases = listOf(
                Phase(type = PhaseType.RELATIONSHIP_UPDATE, actionDeltas = emptyMap()),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun rejectsPersonaCountMismatch() {
        // Constructed directly because makeValidatorScenario auto-generates
        // matching personas.
        val scenario = Scenario(
            id = "test",
            name = "Test",
            description = "Test",
            language = "ja",
            agentCount = 3,
            rounds = 1,
            context = "Context",
            personas = listOf(Persona(name = "A", description = "D"), Persona(name = "B", description = "D")),
            phases = listOf(Phase(type = PhaseType.SPEAK_ALL)),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    // endregion

    // region Assign phase: target "all" (or nil) shape checks
    // Unknown-target rejection now lives in ScenarioLoaderTests (caught at parse).

    @Test
    fun acceptsAssignAllWithStringSource() {
        val scenario = makeAssignScenario(
            target = AssignTarget.ALL,
            source = "topic",
            extraData = mapOf("topic" to AnyCodableValue.StringValue("Hi")),
        )
        validator.validate(scenario)
    }

    @Test
    fun acceptsAssignAllWithArraySource() {
        val scenario = makeAssignScenario(
            target = AssignTarget.ALL,
            source = "topics",
            extraData = mapOf("topics" to AnyCodableValue.ArrayValue(listOf("A", "B"))),
        )
        validator.validate(scenario)
    }

    @Test
    fun rejectsAssignAllWhenSourceKeyMissingFromExtraData() {
        val scenario = makeAssignScenario(target = AssignTarget.ALL, source = "topics", extraData = emptyMap())
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val message = error.message
        assertTrue(message.contains("Phase 1 (assign)"))
        assertTrue(message.contains("'topics'"))
        assertTrue(message.contains("not found"))
    }

    @Test
    fun acceptsAssignAllWithNilSource() {
        // Visual Editor compat: no source specified, skip shape check
        val scenario = makeAssignScenario(target = AssignTarget.ALL, source = null, extraData = emptyMap())
        validator.validate(scenario)
    }

    @Test
    fun acceptsAssignWithDefaultTarget() {
        // nil target defaults to .all behaviour; valid array source should pass
        val scenario = makeAssignScenario(
            target = null,
            source = "topics",
            extraData = mapOf("topics" to AnyCodableValue.ArrayValue(listOf("A", "B"))),
        )
        validator.validate(scenario)
    }

    @Test
    fun rejectsAssignAllWithArrayOfDictionariesSource() {
        val scenario = makeAssignScenario(
            target = AssignTarget.ALL,
            source = "words",
            extraData = mapOf(
                "words" to AnyCodableValue.ArrayOfDictionariesValue(
                    listOf(mapOf("majority" to "x", "minority" to "y")),
                ),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun rejectsAssignAllWithDictionarySource() {
        val scenario = makeAssignScenario(
            target = AssignTarget.ALL,
            source = "w",
            extraData = mapOf("w" to AnyCodableValue.DictionaryValue(mapOf("a" to "b"))),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    /** User-facing error must include 1-based phase index and source key
     * — these end up in editor / import UI verbatim. */
    @Test
    fun rejectAssignAllWithBadShapeIncludesPhaseIndexAndSourceKey() {
        val scenario = makeAssignScenario(
            target = AssignTarget.ALL,
            source = "words",
            extraData = mapOf(
                "words" to AnyCodableValue.ArrayOfDictionariesValue(
                    listOf(mapOf("majority" to "x", "minority" to "y")),
                ),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val message = error.message
        assertTrue(message.contains("Phase 1 (assign)"))
        assertTrue(message.contains("'words'"))
    }

    // endregion

    // region Assign phase: target "random_one" shape checks

    @Test
    fun acceptsAssignRandomOneWithArrayOfDictionariesSource() {
        val scenario = makeAssignScenario(
            target = AssignTarget.RANDOM_ONE,
            source = "words",
            extraData = mapOf(
                "words" to AnyCodableValue.ArrayOfDictionariesValue(
                    listOf(mapOf("majority" to "x", "minority" to "y")),
                ),
            ),
        )
        validator.validate(scenario)
    }

    @Test
    fun rejectsAssignRandomOneWithArraySource() {
        val scenario = makeAssignScenario(
            target = AssignTarget.RANDOM_ONE,
            source = "topics",
            extraData = mapOf("topics" to AnyCodableValue.ArrayValue(listOf("A", "B"))),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun rejectsAssignRandomOneWithStringSource() {
        val scenario = makeAssignScenario(
            target = AssignTarget.RANDOM_ONE,
            source = "topic",
            extraData = mapOf("topic" to AnyCodableValue.StringValue("Hi")),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun rejectsAssignRandomOneWhenSourceKeyMissingFromExtraData() {
        val scenario = makeAssignScenario(target = AssignTarget.RANDOM_ONE, source = "words", extraData = emptyMap())
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val message = error.message
        assertTrue(message.contains("Phase 1 (assign)"))
        assertTrue(message.contains("'words'"))
        assertTrue(message.contains("not found"))
    }

    // endregion

    // region event_inject validation

    @Test
    fun acceptsEventInjectWithArraySource() {
        val scenario = makeEventInjectScenario(
            source = "events",
            probability = 0.5,
            extraData = mapOf("events" to AnyCodableValue.ArrayValue(listOf("x", "y"))),
        )
        val result = validator.validate(scenario)
        assertTrue(result.warnings.isEmpty())
    }

    @Test
    fun rejectsEventInjectWithMissingSource() {
        val scenario = makeEventInjectScenario(source = null, probability = 1.0, extraData = emptyMap())
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val message = error.message
        assertTrue(message.contains("Phase 1 (event_inject)"))
        assertTrue(message.contains("missing 'source'"))
    }

    @Test
    fun rejectsEventInjectWhenSourceKeyAbsentFromExtraData() {
        val scenario = makeEventInjectScenario(source = "events", probability = 1.0, extraData = emptyMap())
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val message = error.message
        assertTrue(message.contains("Phase 1 (event_inject)"))
        assertTrue(message.contains("'events'"))
        assertTrue(message.contains("not found"))
    }

    @Test
    fun rejectsEventInjectWithDictionarySource() {
        val scenario = makeEventInjectScenario(
            source = "events",
            probability = 1.0,
            extraData = mapOf("events" to AnyCodableValue.DictionaryValue(mapOf("a" to "x"))),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val message = error.message
        assertTrue(message.contains("Phase 1 (event_inject)"))
        assertTrue(message.contains("must be a list of event strings"))
        assertTrue(message.contains("['only_event']")) // workaround hint
    }

    @Test
    fun rejectsEventInjectWithEmptyArraySource() {
        val scenario = makeEventInjectScenario(
            source = "events",
            probability = 1.0,
            extraData = mapOf("events" to AnyCodableValue.ArrayValue(emptyList())),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val message = error.message
        assertTrue(message.contains("Phase 1 (event_inject)"))
        assertTrue(message.contains("'events'"))
        assertTrue(message.contains("empty"))
    }

    @Test
    fun rejectsEventInjectWithEmptyArraySourceInsideConditional() {
        // Locks in the engine.md invariant that validateBranch routes
        // sub-phase shape-checks through the same validateEventInjectShape
        // helper as top-level — a regression that bypassed the helper for
        // nested phases would silently re-allow empty arrays inside branches.
        val inner = Phase(type = PhaseType.EVENT_INJECT, source = "events", probability = 1.0)
        val conditional = Phase(
            type = PhaseType.CONDITIONAL,
            condition = "current_round == 1",
            thenPhases = listOf(inner),
        )
        val scenario = Scenario(
            id = "test",
            name = "Test",
            description = "Test",
            language = "ja",
            agentCount = 2,
            rounds = 1,
            context = "Context",
            personas = listOf(Persona(name = "A", description = "D"), Persona(name = "B", description = "D")),
            phases = listOf(conditional),
            extraData = mapOf("events" to AnyCodableValue.ArrayValue(emptyList())),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val message = error.message
        assertTrue(message.contains("event_inject"))
        assertTrue(message.contains("empty"))
    }

    @Test
    fun rejectsEventInjectWithStringSource() {
        val scenario = makeEventInjectScenario(
            source = "events",
            probability = 1.0,
            extraData = mapOf("events" to AnyCodableValue.StringValue("just one")),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.contains("must be a list of event strings"))
    }

    @Test
    fun acceptsEventInjectWithDictSource() {
        // #931: dict-shaped events `{ text, favors }` are a valid source shape.
        val scenario = makeEventInjectScenario(
            source = "events",
            probability = 1.0,
            extraData = mapOf(
                "events" to AnyCodableValue.ArrayOfDictionariesValue(
                    listOf(mapOf("text" to "抜け駆けが得", "favors" to "betray")),
                ),
            ),
        )
        // Must NOT throw.
        validator.validate(scenario)
    }

    @Test
    fun rejectsEventInjectWithEmptyDictSource() {
        // No Swift sibling: the string-shaped empty-source case is covered on both
        // sides, but nothing exercised `validateDictEventEntries`' own empty-list
        // guard — the condition-4 sweep found it green under mutation. Added here
        // because the guard is a distinct site from the string-shape one (#1552).
        val scenario = makeEventInjectScenario(
            source = "events",
            probability = 1.0,
            extraData = mapOf("events" to AnyCodableValue.ArrayOfDictionariesValue(emptyList())),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val message = error.message
        assertTrue(message.contains("Phase 1 (event_inject)"))
        assertTrue(message.contains("'events'"))
        assertTrue(message.contains("empty"))
        // Distinguishes the dict-shaped site from the string-shaped one — both
        // render the three fragments above. Fragment sourced from
        // `ScenarioValidationMessage.swift` (`eventInjectSourceEmptyEvents`).
        assertTrue(message.contains("at least one event"), message)
    }

    @Test
    fun rejectsEventInjectDictEntryMissingText() {
        // A dict entry without a non-empty `text` injects "" (silent no-op) — reject.
        val scenario = makeEventInjectScenario(
            source = "events",
            probability = 1.0,
            extraData = mapOf(
                "events" to AnyCodableValue.ArrayOfDictionariesValue(listOf(mapOf("favors" to "betray"))),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val message = error.message
        assertTrue(message.contains("Phase 1 (event_inject)"))
        assertTrue(message.contains("'text'"))
    }

    @Test
    fun rejectsEventInjectWithProbabilityAboveOne() {
        val scenario = makeEventInjectScenario(
            source = "events",
            probability = 1.5,
            extraData = mapOf("events" to AnyCodableValue.ArrayValue(listOf("x"))),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val message = error.message
        assertTrue(message.contains("probability"))
        assertTrue(message.contains("out of range"))
    }

    @Test
    fun rejectsEventInjectWithNegativeProbability() {
        val scenario = makeEventInjectScenario(
            source = "events",
            probability = -0.1,
            extraData = mapOf("events" to AnyCodableValue.ArrayValue(listOf("x"))),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.contains("out of range"))
    }

    @Test
    fun acceptsEventInjectAtProbabilityBoundaries() {
        val lower = makeEventInjectScenario(
            source = "events",
            probability = 0.0,
            extraData = mapOf("events" to AnyCodableValue.ArrayValue(listOf("x"))),
        )
        val upper = makeEventInjectScenario(
            source = "events",
            probability = 1.0,
            extraData = mapOf("events" to AnyCodableValue.ArrayValue(listOf("x"))),
        )
        validator.validate(lower)
        validator.validate(upper)
    }

    @Test
    fun acceptsEventInjectWithoutProbability() {
        // Default-1.0 (set at handler) is fine; no validation required.
        val scenario = makeEventInjectScenario(
            source = "events",
            probability = null,
            extraData = mapOf("events" to AnyCodableValue.ArrayValue(listOf("x"))),
        )
        validator.validate(scenario)
    }

    // endregion

    // region language + simulationLanguage validation (DoD #2, #5)

    @Test
    fun rejectsInvalidLanguage() {
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = emptyList(), language = "fr")
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val message = error.message
        assertTrue(message.contains("language"))
        assertTrue(message.contains("fr"))
    }

    @Test
    fun rejectsInvalidSimulationLanguage() {
        val scenario = makeValidatorScenario(
            agents = 2,
            rounds = 1,
            phases = emptyList(),
            simulationLanguage = "fr",
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val message = error.message
        assertTrue(message.contains("simulationLanguage"))
        assertTrue(message.contains("fr"))
    }

    @Test
    fun acceptsValidJa() {
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = emptyList(), language = "ja")
        validator.validate(scenario)
    }

    @Test
    fun acceptsValidEn() {
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = emptyList(), language = "en")
        validator.validate(scenario)
    }

    @Test
    fun acceptsNilSimulationLanguage() {
        // default simulationLanguage: null
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = emptyList())
        validator.validate(scenario)
    }

    // endregion

    // region Per-phase max_sentences range (#881)

    @Test
    fun rejectsMaxSentencesBelowRange() {
        val scenario = makeValidatorScenario(
            agents = 2,
            rounds = 1,
            phases = listOf(Phase(type = PhaseType.SPEAK_ALL, maxSentences = 0)),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun rejectsMaxSentencesAboveRange() {
        val scenario = makeValidatorScenario(
            agents = 2,
            rounds = 1,
            phases = listOf(Phase(type = PhaseType.SPEAK_ALL, maxSentences = 7)),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun acceptsMaxSentencesAtBounds() {
        for (value in listOf(1, 6)) {
            val scenario = makeValidatorScenario(
                agents = 2,
                rounds = 1,
                phases = listOf(Phase(type = PhaseType.SPEAK_ALL, maxSentences = value)),
            )
            validator.validate(scenario)
        }
    }

    @Test
    fun acceptsNilMaxSentences() {
        val scenario = makeValidatorScenario(
            agents = 2,
            rounds = 1,
            phases = listOf(Phase(type = PhaseType.SPEAK_ALL, maxSentences = null)),
        )
        validator.validate(scenario)
    }

    /** The range check runs at the `validateBranch` traversal site too — an
     * out-of-range value on a phase nested inside a conditional `then:` is
     * rejected, not silently skipped. */
    @Test
    fun rejectsOutOfRangeInNestedBranch() {
        val scenario = makeValidatorScenario(
            agents = 2,
            rounds = 1,
            phases = listOf(
                Phase(
                    type = PhaseType.CONDITIONAL,
                    condition = "max_score >= 10",
                    thenPhases = listOf(Phase(type = PhaseType.SPEAK_ALL, maxSentences = 0)),
                ),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    // endregion

    // region output field NAMES ASCII-identifier rule (#607)

    @Test
    fun rejectsCjkPrimaryOutputKey() {
        val scenario = makeValidatorScenario(
            agents = 2,
            rounds = 1,
            phases = listOf(
                Phase(type = PhaseType.SPEAK_ALL, prompt = "p", outputSchema = mapOf("内なる思考" to "string")),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    /** Critic Axis 2: a valid canonical primary does NOT excuse a hostile
     * *secondary* key — every output key reaches the grammar, so all keys are
     * gated, not just the canonical primary. */
    @Test
    fun rejectsCjkSecondaryOutputKey() {
        val scenario = makeValidatorScenario(
            agents = 2,
            rounds = 1,
            phases = listOf(
                Phase(
                    type = PhaseType.SPEAK_ALL,
                    prompt = "p",
                    outputSchema = mapOf("statement" to "string", "内なる思考" to "string"),
                ),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    /** Emoji / accented-Latin keys are equally rejected — the boundary is ASCII,
     * not "CJK specifically". */
    @Test
    fun rejectsNonAsciiLatinAndEmojiOutputKeys() {
        for (badKey in listOf("café", "emoji😀", "naïve")) {
            val scenario = makeValidatorScenario(
                agents = 2,
                rounds = 1,
                phases = listOf(
                    Phase(type = PhaseType.SPEAK_ALL, prompt = "p", outputSchema = mapOf(badKey to "string")),
                ),
            )
            assertFailsWith<SimulationException>("key '$badKey' should be rejected") {
                validator.validate(scenario)
            }
        }
    }

    /** Hostile keys buried inside a conditional `then:` / `else:` branch are
     * caught by the same recursion that runs the canonical-field check. */
    @Test
    fun rejectsCjkOutputKeyInsideConditionalBranch() {
        val nested = Phase(type = PhaseType.SPEAK_ALL, prompt = "p", outputSchema = mapOf("статус" to "string"))
        val conditional = Phase(
            type = PhaseType.CONDITIONAL,
            condition = "max_score >= 1",
            thenPhases = listOf(nested),
        )
        val scenario = makeValidatorScenario(agents = 2, rounds = 1, phases = listOf(conditional))
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    /** Control: ASCII snake_case keys (the shape every preset uses) pass clean. */
    @Test
    fun acceptsAsciiOutputKeys() {
        val scenario = makeValidatorScenario(
            agents = 2,
            rounds = 1,
            phases = listOf(
                Phase(
                    type = PhaseType.SPEAK_ALL,
                    prompt = "p",
                    outputSchema = mapOf("statement" to "string", "inner_thought" to "string"),
                ),
            ),
        )
        val result = validator.validate(scenario)
        assertTrue(result.warnings.isEmpty())
    }

    // endregion
}
