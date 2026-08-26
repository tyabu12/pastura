package com.pastura.engine

import com.pastura.models.AssignTarget
import com.pastura.models.PairingStrategy
import com.pastura.models.PayoffRule
import com.pastura.models.PhaseType
import com.pastura.models.ScoreCalcLogic
import com.pastura.models.SimulationError
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * commonTest sibling of Swift's `ScenarioLoaderTests.swift`,
 * `ScenarioLoaderTests+Language.swift`, `ScenarioLoaderTests+StrictTypes.swift`,
 * `ScenarioLoaderTests+Payoff.swift`, `ScenarioLoaderTests+MaxSentences.swift`
 * and the loader-facing arms of `ConditionalScenarioIOTests.swift`
 * (`Pastura/PasturaTests/Engine/`) — **69 1:1 transcriptions**, 44 from PR C2a
 * and 25 from C2b, each complete. The suite also carries tests beyond those 69:
 * the two "condition-4 sweep additions" regions.
 *
 * **Scope.** Only [ScenarioLoader.load]'s behaviour is covered here, matching
 * [ScenarioLoader]'s own class KDoc. Two groups of Swift cases are therefore
 * deliberately absent rather than pending: the six `estimateInferenceCount`
 * tests, which belong to [InferenceEstimator] and live in
 * `InferenceEstimatorTests.kt` (`ScenarioLoader.swift` is a `SPLIT` ledger
 * row), and `ConditionalScenarioIOTests`' `roundTrip*` arms, which exercise
 * the Swift-only `ScenarioSerializer` (`STAY` per ADR-023 §4).
 *
 * ## ADR-023 §12 condition-4 perturbation record
 *
 * Each mechanism of
 * `shared/engine/src/commonMain/kotlin/com/pastura/engine/ScenarioLoader.kt` was
 * broken in isolation and the named **dedicated claimant** — a test that detects the
 * break through **its own** assertion — confirmed to redden. **42 mutations**, each
 * asserted to match its anchor **exactly once** before applying, with the mutated
 * text re-read to confirm it landed (a `replace` that silently no-ops leaves the
 * original behaviour and reads as verified) and the executed-test count asserted
 * non-zero and unchanged (a mutation that stops the suite compiling otherwise
 * reads as green — B2 recorded two that did). The file was restored
 * byte-identically after each run (`git diff --exit-code`), and the unmutated
 * baseline measured green immediately before the first mutation and again after
 * the last revert, so every reddening below is signal rather than pre-existing
 * noise. Measured 2026-08-26, #1558 (PR C2a).
 *
 * The sweep ran **only** this suite. That is sufficient rather than a shortcut:
 * `grep` confirms no other `shared/engine` code constructs [ScenarioLoader] — it
 * is deliberately not wired into the engine (see its class KDoc), so no other
 * suite could redden.
 *
 * **42 mutations executed, 39 reddened, 3 green** (one of them the negative
 * control). The three that stayed green are accounted for below the table. A
 * 43rd *attempt* — `if (false)` on the `simulation_language` arm — did not
 * compile (note 3) and was replaced by the polarity flip already in the
 * table; a non-executing attempt is not evidence and is not counted among the
 * 42.
 *
 * | Mechanism broken | Mutation | Dedicated claimant | Incidental |
 * |---|---|---|---|
 * | Code-fence strip | `filterNot { … startsWith("```") }` → `filterNot { false }` | [stripsCodeFencesBeforeParsing] | none |
 * | Decode failure → `InvalidYAMLFormat` | the `throw` → `JsonObject(emptyMap())` | [throwsOnInvalidYAML] — assertion **strengthened**, note 1; also [throwsOnIntegerBeyondLongRange] (added post-sweep — same fold, not itself sweep-mutated) | none |
 * | Non-mapping root → `InvalidYAMLFormat` | the `?: throw` → `?: JsonObject(emptyMap())` | [throwsOnNonMappingRoot], [throwsOnEmptyDocument] — both **added**, note 2 | none |
 * | `parseRequired` missing-key arm | `?: throw …MissingRequiredField` → `?: JsonNull` | [throwsOnMissingRequiredField] — assertion **strengthened**, note 1 | none |
 * | `parseRequired` wrong-type arm | early-return the cast, no throw | [throwsOnWrongTypeForRequiredString], [throwsOnWrongTypeForRequiredInt], [throwsOnWrongTypeForPersonasList], [throwsOnWrongTypeForPersonaName] | none |
 * | `parseOptional` absent-key arm | `?: return null` → `?: JsonNull` | [absentLogWindowIsNil] and 32 others | 32 — every fixture that omits an optional key then throws |
 * | `parseOptional` wrong-type arm | the `throw` dropped | [throwsOnQuotedSubRounds], [throwsOnQuotedExcludeSelf], [throwsOnIntExcludeSelf], [throwsOnMixedTypeOptions], [throwsOnWrongTypeForPersonaSecret], [bareSecretKeyWithNoValueIsATypeError] | 1 |
 * | `probability` quoted/bool guard | `!it.isString && !it.isYamlBooleanLiteral()` dropped | [throwsOnQuotedProbability] — **added**, note 2 | none |
 * | `language` membership | `if (…) {` → `if (false) {` | [rejectsLanguageInvalid] | none |
 * | `simulation_language` membership | `!in` → `in` (not `if (false)`; see note 3) | [rejectsSimulationLanguageInvalid] | 1 — [parsesSimulationLanguageEn] |
 * | persona count matches `agents` | `if (…) {` → `if (false) {` | [throwsOnAgentCountMismatch] | none |
 * | `STANDARD_KEYS` extra-data filter | `filterNot { it.key in STANDARD_KEYS }` → `filterNot { false }` | [parsesExtraDataStringArray] and 24 others | 24 — every fixture then routes `id` etc. through `convertToAnyCodableValue` |
 * | persona `secret` trim | `?.trim()` dropped | [trimsSurroundingWhitespaceFromPersonaSecret], [normalizesEmptyPersonaSecretToNil] | none |
 * | persona `secret` empty→null | `if (secret.isNullOrEmpty()) null else secret` → `secret` | [normalizesEmptyPersonaSecretToNil] | none |
 * | Nested-`conditional` depth guard | `if (… && depth > 0)` → `if (false)` | *(none — expected green, note 4)* | none |
 * | extra-data scalar `isString` guard | `&& value.isString` dropped | [throwsOnScalarTopLevelExtraData] | none |
 * | extra-data array-of-dicts whole-collection cast | `all { it is JsonObject }` → `any` | [throwsOnExtraDataArrayMixingDictAndScalar] — **added**, note 2 | none |
 * | …its non-String value throw | the `throw` → `?: ""` | [throwsOnNonStringValueInArrayOfDicts] | none |
 * | extra-data mixed-array throw | the `throw` → an empty `ArrayValue` | [throwsOnMixedTypeExtraDataArray] | none |
 * | extra-data dictionary non-String throw | the `throw` → `?: ""` | [throwsOnExtraDataDictWithNonStringValue] — **added**, note 2 | none |
 * | `YamlType.INT` quoted/bool guard | `!it.isString && !it.isYamlBooleanLiteral()` dropped | [throwsOnWrongTypeForRequiredInt], [throwsOnQuotedSubRounds] | none |
 * | `YamlType.INT` 32-bit range check | the range `takeIf` dropped | [throwsOnIntegerBeyond32Bits] — **added**, note 5 | none |
 * | `YamlType.BOOL` YAML-1.1 token set | the token lookup → `null` | [acceptsYAML11BooleanExcludeSelf] | none |
 * | `YamlType.BOOL` `isString`-aware literal check | the quoted arm tried as a literal first | [throwsOnQuotedExcludeSelf] | none |
 * | `STRING_LIST` whole-collection cast | `values.all { it != null }` → `any` | [throwsOnMixedTypeOptions] | none |
 * | `OBJECT_LIST` whole-collection cast | `list.all { it is JsonObject }` → `any` | [throwsOnPersonasListWithScalarElement] — **added**, note 2 | none |
 * | `stringContentOrNull` `isString` guard | `&& it.isString` dropped | [throwsOnWrongTypeForRequiredString], [throwsOnWrongTypeForPersonaName], [throwsOnWrongTypeForPersonaSecret], [throwsOnMixedTypeOptions], [throwsOnMixedTypeExtraDataArray], [throwsOnNonStringValueInArrayOfDicts] | none |
 * | `isYamlBooleanLiteral` `!isString` guard | the guard dropped | *(none — expected green, note 6)* | none |
 * | `renderActualType` `Int64` arm | `"Int64"` → `"Int"` | [throwsOnIntegerBeyond32Bits] — **added**, note 5 | none |
 * | `PhaseType` serial-name lookup | unknown type → `PhaseType.SPEAK_ALL` | [throwsOnInvalidPhaseType] | none |
 * | Missing-`type:` throw | `?: throw …PhaseMissingType` → `?: "speak_all"` | [throwsOnMissingPhaseType] — **added**, note 2 | none |
 * | Phase wiring: `prompt` | read → hardcoded `null` | [parsesPhaseSpeakAll] | none |
 * | Phase wiring: `exclude_self` | read → `null` | [acceptsYAML11BooleanExcludeSelf], [throwsOnQuotedExcludeSelf], [throwsOnIntExcludeSelf] | none |
 * | Phase wiring: `options` | read → `null` | [throwsOnMixedTypeOptions] | none |
 * | Phase wiring: `rounds` → `subRounds` | read → `null` | [throwsOnQuotedSubRounds] | none |
 * | Phase wiring: `probability` | read → `null` | [parsesProbabilityAsDouble], [parsesProbabilityAsIntCoercesToDouble], [throwsOnProbabilityWrongType], [throwsOnProbabilityBoolPretendingToBeInt], [parsesEventInjectFullSpec] | none |
 * | Phase wiring: `as` → `eventVariable` | read → `null` | [parsesEventInjectFullSpec] | none |
 * | Phase wiring: `no_repeat` | read → `null` | [parsesNoRepeat] — **added**, note 2 | none |
 * | Phase wiring: `source` | read → `null` | [parsesEventInjectFullSpec], [parsesEventInjectMinimalSpec] | none |
 * | Phase wiring: `if` → `condition` | read → `null` | [loadsConditionalWithBothBranches] — reassigned in C2b, note 7 | none |
 * | Scenario wiring: `log_window` | read → `null` | [parsesLogWindow], [rejectsNonIntLogWindow] | none |
 * | `YamlType.BOOL` token lookup on a **quoted** token (divergence 2) | *(not sweep-mutated; added post-sweep as a divergence pin)* | [throwsOnQuotedExcludeSelf] pins the rejecting case; [divergesOnQuotedYesExcludeSelf] pins the accepting (divergent) one | none
 * | **NEGATIVE CONTROL** — `acceptedLanguagesList` ordering | `.sorted()` → `.sortedDescending()` | *(none — expected green)* | none |
 *
 * 1. **Two mechanisms were claimed only by a bare "it throws" assertion**, so
 *    the mutation moved the failure to a *different* message and the test stayed
 *    green: the decode-failure fold ([throwsOnInvalidYAML]) and `parseRequired`'s
 *    missing-key arm ([throwsOnMissingRequiredField]). Common cause: the loader
 *    has one exception type, so a type-only assertion cannot tell its layers
 *    apart — the same shape B1's sweep found in `ScenarioValidator`. Fixed by
 *    asserting the rendered message.
 * 2. **Seven mechanisms had no claimant at all** — nothing in
 *    `ScenarioLoaderTests*.swift` drives a quoted `probability`, a
 *    dictionary-valued extra-data key, an extra-data array mixing mappings and
 *    scalars, a `personas:` list holding a scalar, an absent `type:`, `no_repeat`,
 *    or a non-mapping YAML root (a sequence, or an empty document) either — see
 *    each addition's own KDoc for the specific gap. Each gained a test in the
 *    "condition-4 sweep additions" region, except the non-mapping-root pair
 *    ([throwsOnNonMappingRoot], [throwsOnEmptyDocument]), which sit in the
 *    "Validation Errors" region next to the mechanism they share a fold with.
 * 3. `if (false)` does **not** compile on the `simulation_language` arm: the
 *    smart cast from the `!= null` half is lost and the later `!!`-free use
 *    fails. The polarity flip is the compiling substitute, and it reddens the
 *    accepting fixture as well as the rejecting one.
 * 4. The nested-`conditional` depth guard was **structurally unreachable when
 *    this row was measured**: `depth` had no non-zero caller until `mapBranch`
 *    landed. Green then, and claimed now — see the C2b table's
 *    `mapBranch: depth + 1 recursion` row.
 * 5. `Int` is 32-bit in Kotlin and 64-bit in Swift, so this mechanism and its
 *    `Int64` rendering exist only on this side and have no Swift twin to
 *    transcribe. [throwsOnIntegerBeyond32Bits] is the detector for what was
 *    otherwise a KDoc claim with nothing behind it.
 * 6. `isYamlBooleanLiteral`'s `!isString` guard is **defence in depth**: every
 *    caller that could be fooled by a quoted `"true"` is already `isString`-
 *    guarded on its own. Expected green — kept because a future caller without
 *    that guard would need it, and removing it would make this file's one
 *    boolean-literal predicate quietly wrong.
 * 7. **Reassigned in C2b.** The three cells above that named
 *    `phaseSpecialisationIsStillUnmapped` lost their claimant when C2b deleted
 *    that pin. Two were over-claimed and simply drop it ([parsesPhaseSpeakAll]
 *    and the two `event_inject` cases already detect those breaks on their
 *    own); `Phase wiring: if → condition` had the pin as its **sole** claimant
 *    and is reassigned to [loadsConditionalWithBothBranches], which asserts
 *    `phase.condition` directly. Re-measured under the C2b sweep below, not
 *    inferred.
 *
 * ## ADR-023 §12 condition-4 perturbation record — C2b surface
 *
 * Same procedure, same guarantees, scoped to what PR C2b added: the seven
 * phase-specialisation helpers, `mapBranch`'s recursion, and the seven
 * `mapPhase` arguments that stopped being `null`. C2a's ingest and
 * generic-helper surface is **not** re-swept — it was swept whole above, and
 * the table's three reassigned cells were re-measured rather than assumed.
 * **34 mutations executed, 33 reddened, 1 green** (the negative control).
 * Baseline: 85 tests green immediately before the first mutation and again
 * after the last revert. Measured 2026-08-26, #1560 (PR C2b).
 *
 * | Mechanism broken | Mutation | Dedicated claimant | Incidental |
 * |---|---|---|---|
 * | `target:` unknown-value throw | the `?: throw …InvalidTarget` dropped | [rejectsAssignWithUnknownTarget], [rejectsAssignWithCapitalizedTarget] | none |
 * | `target:` routes through [parseOptional] first | the `parseOptional` call → a raw type-name read | [throwsOnIntAssignTarget] | 5 |
 * | `pairing:` unknown-value throw | the `?: throw …InvalidPairing` dropped | [rejectsChooseWithUnknownPairing] | none |
 * | `pairing:` routes through [parseOptional] first | same shape | [throwsOnIntChoosePairing] | 2 |
 * | `logic:` unknown-value throw | the `?: throw …InvalidLogic` → a fallback enum case | [rejectsScoreCalcWithUnknownLogic] | none |
 * | `logic:` routes through [parseOptional] first | same shape | [throwsOnBoolScoreCalcLogic] | 5 |
 * | `allowed:` fragment derived from the lookup's key order | `.keys.joinToString` → `.keys.sorted().joinToString` | [rejectsScoreCalcWithUnknownLogic] — assertion **strengthened**, note 8 | none |
 * | `payoff:` absent → `null` | `?: return null` → `?: JsonNull` | [absentPayoffLeavesNilNotThrow] and 40 others | 40 |
 * | `payoff:` whole-collection cast | the `?: throw …PayoffNotList` → `?: emptyList()` | [throwsOnPayoffNotList] | none |
 * | `payoff:` row `when` string-list cast | `STRING_LIST.cast` → a lenient `toString()` map | [parsesPayoffTableOnScoreCalc] | none |
 * | `payoff:` row `when` arity 2 | `takeIf { it.size == 2 }` → `takeIf { true }` | [throwsOnWhenArityNotTwo] | none |
 * | `payoff:` row `points` array cast + arity | same `takeIf` flip | [throwsOnPointsArityNotTwo] | none |
 * | `payoff:` row `points` element throw | the `?: throw …PayoffRowInvalid` made unreachable | [throwsOnNonIntPayoffPointsValue] — **added**, note 9 | 1 |
 * | `payoff:` row `points` bool / quoted exclusion | `YamlType.INT.cast` → a lenient `content.toIntOrNull()` | [throwsOnQuotedPayoffPointsValue] — **added**, note 9 | none |
 * | `action_deltas:` absent → `null` | `?: return null` → `?: JsonNull` | [parsesRelationshipUpdateMinimalSpec] and 39 others | 39 |
 * | `action_deltas:` non-mapping throw | the `?: throw …ActionDeltasNotDict` → an empty mapping | [throwsOnNonDictActionDeltas] — **added**, note 9 | none |
 * | `action_deltas:` per-value `Int` throw | the `?: throw …ActionDeltasValueNotInt` → `?: 0` | [throwsOnNonIntActionDeltaValue] | none |
 * | `output:` absent → `null` | `?: return null` → `?: JsonNull` | [parsesPhaseWithAllFields] and 33 others | 33 |
 * | `output:` non-mapping throw | the `?: throw …OutputNotDict` → an empty mapping | [throwsOnNonDictOutputSchema] | none |
 * | `output:` per-value `String` throw | the `?: throw …OutputValueNotString` → `?: ""` | [throwsOnNonStringOutputSchemaValue] | none |
 * | `then:` / `else:` absent → `null` | `?: return null` → `?: JsonNull` | [loadsConditionalWithOnlyThenBranch] and 41 others | 41 |
 * | `mapBranch` whole-collection cast | the `?: throw …BranchNotArray` → `?: emptyList()` | [throwsOnScalarThenBranch] — **added** in the C2b gap-retirement commit | none |
 * | `mapBranch` names the **branch**, not the parent | `branch = branchLabel` → `branch = parentLabel` | [throwsOnScalarThenBranch] | none |
 * | `mapBranch` descends at `depth + 1` | `depth = depth + 1` → `depth = depth` | [rejectsNestedConditionalInThenBranch], [rejectsNestedConditionalInElseBranch] | none |
 * | `mapBranch` sub-phase label form | `"$parent.$branch[$i]"` → `"$parent"` | [namesTheOffendingSubPhaseInsideABranch] — **added**, note 9 | none |
 * | Phase wiring: `output` → `outputSchema` | read → `null` | [parsesPhaseSpeakAll] | none |
 * | Phase wiring: `pairing` | read → `null` | [parsesPhaseWithAllFields] | none |
 * | Phase wiring: `logic` | read → `null` | [parsesPhaseWithAllFields] | none |
 * | Phase wiring: `target` | read → `null` | [parsesPhaseWithAllFields] | none |
 * | Phase wiring: `then` → `thenPhases` | read → `null` | [loadsConditionalWithBothBranches], [loadsConditionalWithOnlyThenBranch] | none |
 * | Phase wiring: `else` → `elsePhases` | read → `null` | [loadsConditionalWithBothBranches] | none |
 * | Phase wiring: `action_deltas` | read → `null` | [parsesRelationshipUpdateFullSpec] | none |
 * | Phase wiring: `payoff` | read → `null` | [parsesPayoffTableOnScoreCalc] | none |
 * | **NEGATIVE CONTROL** — `parsePayoff` KDoc wording | "matching" → "mirroring" | *(none — expected green)* | none |
 *
 * 8. The `allowed:` fragment is derived from
 *    `ScenarioLoader.SCORE_CALC_LOGICS_BY_YAML_NAME`'s key order *so that* it
 *    cannot drift from the enum — but nothing detected a drift, because the
 *    transcribed case only asserted that loading throws. Re-ordering the
 *    fragment left the suite green. The assertion now spells the whole string
 *    out in declaration order.
 * 9. **Four mechanisms had no claimant on either side.** Swift's `+Payoff`
 *    suite covers both arity failures but never a well-sized row holding a bad
 *    value; no Swift test feeds a non-mapping `action_deltas:`; and every
 *    conditional test asserts on a *well-formed* branch, so nothing read the
 *    sub-phase label that is a curator's only way to locate the offending
 *    phase. Each gained a test in the "condition-4 sweep additions (C2b
 *    surface)" region.
 *
 *    Six mutations in an earlier pass — the `?: throw` arms — were first
 *    attempted as `if (false) { throw … }` and did **not** compile, the same
 *    shape as note 3. They were re-run as elvis-substitutions and are counted
 *    once, in the form that executed; the non-compiling attempts are not
 *    evidence and are not among the 34.
 */
class ScenarioLoaderTests {

    private val loader = ScenarioLoader()

    // region Valid Scenario Loading

    @Test
    fun loadsMinimalValidScenario() {
        val yaml = """
            id: test_scenario
            language: ja
            name: Test
            description: A test scenario
            agents: 2
            rounds: 3
            context: You are in a game.
            personas:
              - name: Alice
                description: A strategist
              - name: Bob
                description: An optimist
            phases:
              - type: speak_all
                prompt: "Speak your mind."
                output:
                  statement: string
                  inner_thought: string
        """.trimIndent()
        val scenario = loader.load(yaml)
        assertEquals("test_scenario", scenario.id)
        assertEquals("Test", scenario.name)
        assertEquals("A test scenario", scenario.description)
        assertEquals(2, scenario.agentCount)
        assertEquals(3, scenario.rounds)
        assertEquals("You are in a game.", scenario.context)
        assertEquals(2, scenario.personas.size)
        assertEquals(1, scenario.phases.size)
    }

    @Test
    fun parsesPhaseSpeakAll() {
        val scenario = loader.load(makeMinimalYAML())
        val phase = scenario.phases[0]
        assertEquals(PhaseType.SPEAK_ALL, phase.type)
        assertEquals("Speak your mind.", phase.prompt)
        assertEquals("string", phase.outputSchema?.get("statement"))
    }

    @Test
    fun parsesPhaseWithAllFields() {
        val yaml = """
            id: test
            language: ja
            name: Test
            description: Test
            agents: 2
            rounds: 1
            context: Context
            personas:
              - name: A
                description: A
              - name: B
                description: B
            phases:
              - type: choose
                prompt: "Choose!"
                output:
                  action: string
                options:
                  - cooperate
                  - betray
                pairing: round_robin
              - type: score_calc
                logic: prisoners_dilemma
              - type: summarize
                template: "{agent1}({action1}) vs {agent2}({action2})"
              - type: vote
                prompt: "Vote!"
                output:
                  vote: string
                exclude_self: true
              - type: speak_each
                prompt: "Talk"
                output:
                  statement: string
                rounds: 3
              - type: assign
                source: words
                target: random_one
              - type: eliminate
        """.trimIndent()
        val scenario = loader.load(yaml)

        // choose phase
        val choose = scenario.phases[0]
        assertEquals(PhaseType.CHOOSE, choose.type)
        assertEquals(listOf("cooperate", "betray"), choose.options)
        assertEquals(PairingStrategy.ROUND_ROBIN, choose.pairing)

        // score_calc phase
        val scoreCalc = scenario.phases[1]
        assertEquals(PhaseType.SCORE_CALC, scoreCalc.type)
        assertEquals(ScoreCalcLogic.PRISONERS_DILEMMA, scoreCalc.logic)

        // summarize phase
        val summarize = scenario.phases[2]
        assertEquals(PhaseType.SUMMARIZE, summarize.type)
        assertEquals("{agent1}({action1}) vs {agent2}({action2})", summarize.template)

        // vote phase
        val vote = scenario.phases[3]
        assertEquals(PhaseType.VOTE, vote.type)
        assertEquals(true, vote.excludeSelf)

        // speak_each phase
        val speakEach = scenario.phases[4]
        assertEquals(PhaseType.SPEAK_EACH, speakEach.type)
        assertEquals(3, speakEach.subRounds)

        // assign phase
        val assign = scenario.phases[5]
        assertEquals(PhaseType.ASSIGN, assign.type)
        assertEquals("words", assign.source)
        assertEquals(AssignTarget.RANDOM_ONE, assign.target)

        // eliminate phase
        val eliminate = scenario.phases[6]
        assertEquals(PhaseType.ELIMINATE, eliminate.type)
    }

    // endregion

    // region log_window (#907)

    @Test
    fun parsesLogWindow() {
        val yaml = """
            id: lw_test
            language: ja
            name: LW
            description: log window test
            agents: 2
            rounds: 1
            log_window: 5
            context: Context
            personas:
              - name: Alice
                description: A
              - name: Bob
                description: B
            phases:
              - type: speak_all
                prompt: Go
                output:
                  statement: string
        """.trimIndent()
        val scenario = loader.load(yaml)
        assertEquals(5, scenario.logWindow)
    }

    @Test
    fun absentLogWindowIsNil() {
        val scenario = loader.load(makeMinimalYAML())
        assertNull(scenario.logWindow)
    }

    @Test
    fun rejectsNonIntLogWindow() {
        val yaml = """
            id: lw_bad
            language: ja
            name: LW
            description: log window test
            agents: 2
            rounds: 1
            log_window: "five"
            context: Context
            personas:
              - name: Alice
                description: A
              - name: Bob
                description: B
            phases:
              - type: speak_all
                prompt: Go
                output:
                  statement: string
        """.trimIndent()
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val msg = error.message
        assertTrue(msg.contains("'log_window'"))
        assertTrue(msg.contains("Int"))
    }

    @Test
    fun parsesPersonasCorrectly() {
        val scenario = loader.load(makeMinimalYAML())
        assertEquals("Alice", scenario.personas[0].name)
        assertEquals("A strategist", scenario.personas[0].description)
        assertEquals("Bob", scenario.personas[1].name)
    }

    // endregion

    // region Extra Data

    @Test
    fun parsesExtraDataStringArray() {
        val yaml = """
            id: test
            language: ja
            name: Test
            description: Test
            agents: 2
            rounds: 1
            context: Context
            personas:
              - name: A
                description: A
              - name: B
                description: B
            phases:
              - type: speak_all
                prompt: "Go"
                output:
                  statement: string
            topics:
              - "A cat in a suit"
              - "A dog driving"
        """.trimIndent()
        val scenario = loader.load(yaml)
        val topics = scenario.extraData["topics"]
        assertTrue(topics is com.pastura.models.AnyCodableValue.ArrayValue)
        assertEquals(2, topics.value.size)
        assertEquals("A cat in a suit", topics.value[0])
    }

    @Test
    fun parsesExtraDataArrayOfDictionaries() {
        val yaml = """
            id: test
            language: ja
            name: Test
            description: Test
            agents: 2
            rounds: 1
            context: Context
            personas:
              - name: A
                description: A
              - name: B
                description: B
            phases:
              - type: assign
                source: words
                target: random_one
            words:
              - majority: りんご
                minority: みかん
              - majority: 温泉
                minority: プール
        """.trimIndent()
        val scenario = loader.load(yaml)
        val words = scenario.extraData["words"]
        assertTrue(words is com.pastura.models.AnyCodableValue.ArrayOfDictionariesValue)
        assertEquals(2, words.value.size)
        assertEquals("りんご", words.value[0]["majority"])
        assertEquals("みかん", words.value[0]["minority"])
    }

    // endregion

    // region Code Fence Stripping

    @Test
    fun stripsCodeFencesBeforeParsing() {
        val yaml = """
            ```yaml
            id: test
            language: ja
            name: Test
            description: Test
            agents: 2
            rounds: 1
            context: Context
            personas:
              - name: A
                description: A
              - name: B
                description: B
            phases:
              - type: speak_all
                prompt: "Go"
                output:
                  statement: string
            ```
        """.trimIndent()
        val scenario = loader.load(yaml)
        assertEquals("test", scenario.id)
    }

    // endregion

    // region Validation Errors

    @Test
    fun throwsOnMissingRequiredField() {
        val yaml = """
            name: Test
            description: Test
            agents: 2
            rounds: 1
            context: Context
            personas:
              - name: A
                description: A
              - name: B
                description: B
            phases:
              - type: speak_all
        """.trimIndent()
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        // Missing-vs-wrong-type is the whole point of parseRequired's two
        // branches, and the condition-4 sweep found that collapsing the missing
        // branch into the wrong-type one left this test green — both still
        // throw. Assert which one fired.
        assertTrue(error.message.contains("missing required field 'id'"))
    }

    /**
     * A phase with no `type:` at all.
     *
     * Added by the condition-4 sweep: [throwsOnInvalidPhaseType] covers an
     * *unknown* type, but nothing drove an *absent* one, so defaulting the
     * missing-type throw to `speak_all` left the suite green. Missing and
     * invalid do **not** collapse to one message — `parsePhaseType` throws
     * [com.pastura.models.ScenarioValidationMessage.PhaseMissingType] here and
     * [com.pastura.models.ScenarioValidationMessage.PhaseInvalidType] for
     * [throwsOnInvalidPhaseType], and this test's own assertion proves they
     * differ. What *does* collapse is missing-vs-**wrong-type**: `type: 42`
     * (a non-String value) also renders `PhaseMissingType`, per
     * `parsePhaseType`'s KDoc — and no test in this suite claims that arm.
     */
    @Test
    fun throwsOnMissingPhaseType() {
        val yaml = makeMinimalYAML(
            """
                phases:
                  - prompt: "No type here"
            """.trimIndent(),
        )
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.contains("missing 'type'"))
    }

    @Test
    fun throwsOnInvalidPhaseType() {
        val yaml = """
            id: test
            language: ja
            name: Test
            description: Test
            agents: 2
            rounds: 1
            context: Context
            personas:
              - name: A
                description: A
              - name: B
                description: B
            phases:
              - type: invalid_type
                prompt: "Go"
        """.trimIndent()
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val msg = error.message
        assertTrue(msg.contains("invalid type"))
        assertTrue(msg.contains("'invalid_type'"))
    }

    @Test
    fun throwsOnAgentCountMismatch() {
        val yaml = """
            id: test
            language: ja
            name: Test
            description: Test
            agents: 5
            rounds: 1
            context: Context
            personas:
              - name: A
                description: A
              - name: B
                description: B
            phases:
              - type: speak_all
                prompt: "Go"
        """.trimIndent()
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val msg = error.message
        assertTrue(msg.contains("agents (5)"))
        assertTrue(msg.contains("personas count (2)"))
    }

    @Test
    fun throwsOnInvalidYAML() {
        val yaml = "{{invalid yaml: [["
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        // The message, not just the throw: the condition-4 sweep found that
        // replacing the decode-failure fold with an empty mapping keeps this
        // test green, because the empty mapping then fails on `id` instead.
        assertTrue(error.message.contains("Invalid YAML format"))
    }

    /**
     * A sequence root — the second half of Swift's
     * `guard let raw = try? Yams.load(...), let dict = raw as? [String: Any]`.
     *
     * Added by the condition-4 sweep: no transcribed test drove a well-formed
     * document whose root is not a mapping, so replacing that fold with an
     * empty mapping left the suite green.
     */
    @Test
    fun throwsOnNonMappingRoot() {
        val caught = assertFailsWith<SimulationException> { loader.load("- 1\n- 2") }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.contains("Invalid YAML format"))
    }

    /**
     * An empty document, which `YamlCodec` decodes to `JsonNull` rather than
     * failing — so it reaches the same non-mapping fold as
     * [throwsOnNonMappingRoot] by a different route.
     */
    @Test
    fun throwsOnEmptyDocument() {
        val caught = assertFailsWith<SimulationException> { loader.load("   \n") }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.contains("Invalid YAML format"))
    }

    // endregion

    // region event_inject phase parsing

    @Test
    fun parsesEventInjectFullSpec() {
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: event_inject
                    source: random_events
                    probability: 0.3
                    as: my_event
                random_events:
                  - "停電が起きた"
                  - "謎の電話"
            """.trimIndent(),
        )
        val scenario = loader.load(yaml)
        val phase = scenario.phases[0]
        assertEquals(PhaseType.EVENT_INJECT, phase.type)
        assertEquals("random_events", phase.source)
        assertEquals(0.3, phase.probability)
        assertEquals("my_event", phase.eventVariable)
    }

    @Test
    fun parsesEventInjectMinimalSpec() {
        // Only `source:` is required — probability/as default at the handler.
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: event_inject
                    source: events
                events:
                  - "x"
            """.trimIndent(),
        )
        val scenario = loader.load(yaml)
        val phase = scenario.phases[0]
        assertEquals(PhaseType.EVENT_INJECT, phase.type)
        assertEquals("events", phase.source)
        assertNull(phase.probability)
        assertNull(phase.eventVariable)
    }

    @Test
    fun parsesProbabilityAsIntCoercesToDouble() {
        // Boundary values `0` and `1` are the most ergonomic in YAML; the
        // intentional Int -> Double coercion (parseOptionalDoubleAcceptingInt)
        // accepts both shapes.
        val yamlOne = makeMinimalYAML(
            """
                phases:
                  - type: event_inject
                    source: events
                    probability: 1
                events:
                  - "x"
            """.trimIndent(),
        )
        val scenarioOne = loader.load(yamlOne)
        assertEquals(1.0, scenarioOne.phases[0].probability)

        val yamlZero = makeMinimalYAML(
            """
                phases:
                  - type: event_inject
                    source: events
                    probability: 0
                events:
                  - "x"
            """.trimIndent(),
        )
        val scenarioZero = loader.load(yamlZero)
        assertEquals(0.0, scenarioZero.phases[0].probability)
    }

    @Test
    fun parsesProbabilityAsDouble() {
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: event_inject
                    source: events
                    probability: 0.5
                events:
                  - "x"
            """.trimIndent(),
        )
        val scenario = loader.load(yaml)
        assertEquals(0.5, scenario.phases[0].probability)
    }

    @Test
    fun throwsOnProbabilityWrongType() {
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: event_inject
                    source: events
                    probability: "half"
                events:
                  - "x"
            """.trimIndent(),
        )
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun throwsOnProbabilityBoolPretendingToBeInt() {
        // In Swift this guard is load-bearing: `as? Int` launders a Bool, so
        // without an explicit Bool check `probability: true` would silently
        // pass. In Kotlin it is not — the condition-4 sweep found that
        // deleting `!it.isYamlBooleanLiteral()` from
        // `parseOptionalDoubleAcceptingInt` leaves `"true".toDoubleOrNull() ==
        // null`, so this fixture still throws either way and no input here
        // can distinguish the guard's presence from its absence. Kept for
        // parity with the Swift transcription and because a no-op guard is
        // still correct, not because it detects anything on this side.
        // (`YamlType.INT`'s copy of the same `!it.isYamlBooleanLiteral()`
        // guard is redundant for the identical reason; its `!it.isString`
        // sibling is not — see [throwsOnQuotedSubRounds].)
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: event_inject
                    source: events
                    probability: true
                events:
                  - "x"
            """.trimIndent(),
        )
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    // endregion

    // region relationship_update phase parsing (#910)

    @Test
    fun parsesRelationshipUpdateFullSpec() {
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: relationship_update
                    vote_against: -1
                    action_deltas:
                      cooperate: 1
                      betray: -2
            """.trimIndent(),
        )
        val scenario = loader.load(yaml)
        val phase = scenario.phases[0]
        assertEquals(PhaseType.RELATIONSHIP_UPDATE, phase.type)
        assertEquals(-1, phase.voteAgainst)
        assertEquals(mapOf("cooperate" to 1, "betray" to -2), phase.actionDeltas)
    }

    @Test
    fun parsesRelationshipUpdateMinimalSpec() {
        // Both rule fields are optional at parse time; the shape check that
        // requires >= 1 rule lives at the validator gate (#910 later commit).
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: relationship_update
            """.trimIndent(),
        )
        val scenario = loader.load(yaml)
        val phase = scenario.phases[0]
        assertEquals(PhaseType.RELATIONSHIP_UPDATE, phase.type)
        assertNull(phase.voteAgainst)
        assertNull(phase.actionDeltas)
    }

    @Test
    fun throwsOnNonIntActionDeltaValue() {
        // Strict per #130: a String delta value is a typo, not a coercion.
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: relationship_update
                    action_deltas:
                      cooperate: "one"
            """.trimIndent(),
        )
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    // endregion

    // region language field (DoD #2, #5, #6)

    @Test
    fun rejectsLanguageAbsent() {
        val yaml = makeBaseYAML() // no language: line
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.contains("language"))
    }

    @Test
    fun parsesLanguageJa() {
        val yaml = makeBaseYAML(language = "ja")
        val scenario = loader.load(yaml)
        assertEquals("ja", scenario.language)
    }

    @Test
    fun parsesLanguageEn() {
        val yaml = makeBaseYAML(language = "en")
        val scenario = loader.load(yaml)
        assertEquals("en", scenario.language)
    }

    @Test
    fun rejectsLanguageInvalid() {
        val yaml = makeBaseYAML(language = "fr")
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.contains("language"))
        assertTrue(error.message.contains("fr"))
    }

    @Test
    fun parsesSimulationLanguageEn() {
        val yaml = makeBaseYAML(language = "ja", simulationLanguage = "en")
        val scenario = loader.load(yaml)
        assertEquals("en", scenario.simulationLanguage)
    }

    @Test
    fun simulationLanguageAbsent() {
        val yaml = makeBaseYAML(language = "ja")
        val scenario = loader.load(yaml)
        assertNull(scenario.simulationLanguage)
    }

    @Test
    fun rejectsSimulationLanguageInvalid() {
        val yaml = makeBaseYAML(language = "ja", simulationLanguage = "fr")
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.contains("simulation_language"))
        assertTrue(error.message.contains("fr"))
    }

    // endregion

    // region Scenario top-level wrong-type errors

    /** Numeric id (YAML auto-type) previously coerced silently to "42". Strict
     * loader throws with a wrong-type message distinguishing it from "missing
     * field" — the prior stringify fallback would have hidden typos like
     * `id: 001` (YAML 1.1 auto-types to Int 1). */
    @Test
    fun throwsOnWrongTypeForRequiredString() {
        val yaml = """
            id: 42
            language: ja
            name: Test
            description: Test
            agents: 2
            rounds: 1
            context: Context
            personas:
              - name: A
                description: A
              - name: B
                description: B
            phases:
              - type: speak_all
                prompt: "Go"
        """.trimIndent()
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val msg = error.message
        assertTrue(msg.contains("'id'"))
        assertTrue(msg.contains("String"))
        assertTrue(!msg.lowercase().contains("missing"))
    }

    /** Quoted integer (`agents: "2"`) previously threw a misleading "Missing
     * required field" error. Strict loader surfaces the real cause. */
    @Test
    fun throwsOnWrongTypeForRequiredInt() {
        val yaml = """
            id: test
            language: ja
            name: Test
            description: Test
            agents: "2"
            rounds: 1
            context: Context
            personas:
              - name: A
                description: A
              - name: B
                description: B
            phases:
              - type: speak_all
                prompt: "Go"
        """.trimIndent()
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val msg = error.message
        assertTrue(msg.contains("'agents'"))
        assertTrue(msg.contains("Int"))
        assertTrue(!msg.lowercase().contains("missing"))
    }

    // endregion

    // region Personas / phases strict (#130 item 1 follow-up)

    /** `personas: "alice"` (scalar instead of list-of-dict) previously threw
     * with "Missing or invalid field: personas" — strict loader uses the new
     * helper so missing vs wrong-type produce distinct messages. */
    @Test
    fun throwsOnWrongTypeForPersonasList() {
        val yaml = """
            id: t
            language: ja
            name: T
            description: T
            agents: 2
            rounds: 1
            context: C
            personas: "alice"
            phases:
              - type: speak_all
                prompt: "Go"
        """.trimIndent()
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val msg = error.message
        assertTrue(msg.contains("'personas'"))
        assertTrue(!msg.lowercase().contains("missing"))
    }

    /** Persona with a numeric name (`- name: 42`) previously became a Scenario
     * whose persona name wasn't the Int the author typed — `as? String` failed
     * silently at the `mapPersona` boundary. Strict loader throws. */
    @Test
    fun throwsOnWrongTypeForPersonaName() {
        val yaml = """
            id: t
            language: ja
            name: T
            description: T
            agents: 2
            rounds: 1
            context: C
            personas:
              - name: 42
                description: D
              - name: B
                description: D
            phases:
              - type: speak_all
                prompt: "Go"
        """.trimIndent()
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val msg = error.message
        assertTrue(msg.contains("'name'"))
        assertTrue(msg.contains("String"))
    }

    // endregion

    // region Persona secret (#914)

    @Test
    fun parsesPersonaSecret() {
        val yaml = """
            id: t
            language: ja
            name: T
            description: T
            agents: 2
            rounds: 1
            context: C
            personas:
              - name: A
                description: D
                secret: You already sold the house.
              - name: B
                description: D
            phases:
              - type: speak_all
                prompt: "Go"
        """.trimIndent()
        val scenario = loader.load(yaml)
        assertEquals("You already sold the house.", scenario.personas[0].secret)
        // Absent key -> nil (backward compatible: existing scenarios are unchanged).
        assertNull(scenario.personas[1].secret)
    }

    /** Empty ≡ absent (#914): the loader normalizes an empty — or
     * whitespace-only — `secret` to nil so a header-only prompt section can
     * never render, and the patcher's `reparsed == visual` safety-net can't be
     * pinned to a permanent fallback. Whitespace-only is included so this
     * matches the editor boundary's trim-then-check rule exactly. */
    @Test
    fun normalizesEmptyPersonaSecretToNil() {
        for (authored in listOf("\"\"", "\"   \"")) {
            val yaml = """
                id: t
                language: ja
                name: T
                description: T
                agents: 2
                rounds: 1
                context: C
                personas:
                  - name: A
                    description: D
                    secret: $authored
                  - name: B
                    description: D
                phases:
                  - type: speak_all
                    prompt: "Go"
            """.trimIndent()
            assertNull(loader.load(yaml).personas[0].secret, "authored=$authored")
        }
    }

    /** Trimming is normalization, not mutation: a secret with incidental
     * surrounding whitespace keeps its content. */
    @Test
    fun trimsSurroundingWhitespaceFromPersonaSecret() {
        val yaml = """
            id: t
            language: ja
            name: T
            description: T
            agents: 2
            rounds: 1
            context: C
            personas:
              - name: A
                description: D
                secret: "  She sold the house  "
              - name: B
                description: D
            phases:
              - type: speak_all
                prompt: "Go"
        """.trimIndent()
        assertEquals("She sold the house", loader.load(yaml).personas[0].secret)
    }

    /** A bare `secret:` with no value is a plausible hand-authoring shape.
     * The YAML decodes it to an explicit null, which fails `parseOptional`'s
     * String cast — so it is a type error, not a silent nil. Pinned so the
     * behavior is a decision rather than an accident. */
    @Test
    fun bareSecretKeyWithNoValueIsATypeError() {
        val yaml = """
            id: t
            language: ja
            name: T
            description: T
            agents: 2
            rounds: 1
            context: C
            personas:
              - name: A
                description: D
                secret:
              - name: B
                description: D
            phases:
              - type: speak_all
                prompt: "Go"
        """.trimIndent()
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.contains("'secret'"))
    }

    @Test
    fun throwsOnWrongTypeForPersonaSecret() {
        val yaml = """
            id: t
            language: ja
            name: T
            description: T
            agents: 2
            rounds: 1
            context: C
            personas:
              - name: A
                description: D
                secret: 42
              - name: B
                description: D
            phases:
              - type: speak_all
                prompt: "Go"
        """.trimIndent()
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val msg = error.message
        assertTrue(msg.contains("'secret'"))
        assertTrue(msg.contains("String"))
    }

    // endregion

    // region Assign target parsing (strict)

    /**
     * Typo'd target string is rejected at parse time (was a silent `.all`
     * default before #108 / typed `AssignTarget`).
     */
    @Test
    fun rejectsAssignWithUnknownTarget() {
        val yaml = makeYAMLWithAssignTarget("randomOne") // typo of random_one
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    /**
     * Case is significant — `target: All` was previously silently treated as
     * the default; now rejected.
     */
    @Test
    fun rejectsAssignWithCapitalizedTarget() {
        val yaml = makeYAMLWithAssignTarget("All")
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun acceptsAssignWithCanonicalTargetAll() {
        loader.load(makeYAMLWithAssignTarget("all"))
    }

    @Test
    fun acceptsAssignWithCanonicalTargetRandomOne() {
        loader.load(makeYAMLWithAssignTarget("random_one"))
    }

    // endregion

    // region Pairing / logic parsing (strict)

    @Test
    fun rejectsChooseWithUnknownPairing() {
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: choose
                    pairing: roundRobin
                    options: [a, b]
            """.trimIndent(),
        )
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    /**
     * Assertion **strengthened** beyond the Swift original, which only checks
     * that loading throws.
     *
     * The `allowed:` fragment is derived from
     * `ScenarioLoader.SCORE_CALC_LOGICS_BY_YAML_NAME`'s key order rather than
     * hand-written, precisely so it cannot drift from the enum — but the
     * condition-4 sweep found that nothing detected a drift: re-ordering the
     * fragment left the suite green. This spells the whole string out, in
     * `ScoreCalcLogic` declaration order, matching what Swift's
     * `allCases.map(\.rawValue).joined(separator: ", ")` renders. A sixth
     * case, or a re-ordering, reddens here.
     */
    @Test
    fun rejectsScoreCalcWithUnknownLogic() {
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: score_calc
                    logic: made_up_logic
            """.trimIndent(),
        )
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(
            error.message.contains(
                "prisoners_dilemma, vote_tally, wordwolf_judge, event_reactive, pairwise_payoff",
            ),
            error.message,
        )
    }

    // endregion

    // region Phase-optional field wrong-type errors (#130 item 2)

    /** `rounds: "3"` (accidentally quoted in YAML) previously coerced silently
     * to `nil` -> `subRounds` defaulted to 1 -> `speak_each` ran one pass
     * instead of three. Strict loader now throws. */
    @Test
    fun throwsOnQuotedSubRounds() {
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: speak_each
                    prompt: "Talk"
                    rounds: "3"
            """.trimIndent(),
        )
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val msg = error.message
        assertTrue(msg.contains("'rounds'"))
        assertTrue(msg.contains("Int"))
    }

    /** `exclude_self: "true"` (quoted string) previously became `nil`
     * silently; strict loader throws. Contrast with `exclude_self: yes`
     * (bare) which is a valid YAML 1.1 boolean — see
     * [acceptsYAML11BooleanExcludeSelf]. */
    @Test
    fun throwsOnQuotedExcludeSelf() {
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: vote
                    prompt: "Vote"
                    exclude_self: "true"
            """.trimIndent(),
        )
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val msg = error.message
        assertTrue(msg.contains("'exclude_self'"))
        assertTrue(msg.contains("Bool"))
    }

    /** `exclude_self: 1` (integer) also fails strictly — no 0/1 -> bool
     * coercion. */
    @Test
    fun throwsOnIntExcludeSelf() {
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: vote
                    prompt: "Vote"
                    exclude_self: 1
            """.trimIndent(),
        )
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val msg = error.message
        assertTrue(msg.contains("'exclude_self'"))
        assertTrue(msg.contains("Bool"))
    }

    /** YAML 1.1 treats bare `yes`/`no`/`on`/`off` as booleans. This loader
     * re-accepts that token set locally (see [ScenarioLoader]'s class KDoc,
     * divergence 2) so `exclude_self: yes` parses to `true` — this is *not* a
     * silent-coerce bug, it's the canonical spelling. Pinned as a positive
     * test so a future "fix" doesn't break it. */
    @Test
    fun acceptsYAML11BooleanExcludeSelf() {
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: vote
                    prompt: "Vote"
                    exclude_self: yes
            """.trimIndent(),
        )
        val scenario = loader.load(yaml)
        assertEquals(true, scenario.phases[0].excludeSelf)
    }

    // endregion

    // region parseOutputSchema strict (#130 item 3)

    /**
     * `output: { count: 1 }` previously stringified `1` to `"1"` silently. The
     * schema is an LLM prompt hint — a non-String value is almost always a typo.
     */
    @Test
    fun throwsOnNonStringOutputSchemaValue() {
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: speak_all
                    prompt: "Go"
                    output:
                      statement: string
                      count: 1
            """.trimIndent(),
        )
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val msg = error.message
        assertTrue(msg.contains("output"))
        assertTrue(msg.contains("'count'"))
    }

    /**
     * `output: "string"` (scalar instead of dict) previously just skipped the
     * schema (no-op). Strict loader throws so users catch the mis-shape.
     */
    @Test
    fun throwsOnNonDictOutputSchema() {
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: speak_all
                    prompt: "Go"
                    output: "string"
            """.trimIndent(),
        )
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    // endregion

    // region convertToAnyCodableValue strict (#130 item 4)

    /** Top-level scalar extraData (`count: 42`) previously silently
     * disappeared — `convertToAnyCodableValue` returned nil and
     * `collectExtraData` dropped it. Strict loader throws naming the
     * offending field and listing supported shapes. */
    @Test
    fun throwsOnScalarTopLevelExtraData() {
        val yaml = """
            id: t
            language: ja
            name: T
            description: T
            agents: 2
            rounds: 1
            context: C
            personas:
              - name: A
                description: D
              - name: B
                description: D
            phases:
              - type: speak_all
                prompt: "Go"
            count: 42
        """.trimIndent()
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val msg = error.message
        assertTrue(msg.contains("'count'"))
        // Error message should hint at the supported shapes so users know how to fix.
        assertTrue(msg.contains("String") || msg.contains("string"))
    }

    /** Quoting the scalar works — `count: "42"` parses as `.string("42")`. */
    @Test
    fun acceptsQuotedScalarTopLevelExtraData() {
        val yaml = """
            id: t
            language: ja
            name: T
            description: T
            agents: 2
            rounds: 1
            context: C
            personas:
              - name: A
                description: D
              - name: B
                description: D
            phases:
              - type: speak_all
                prompt: "Go"
            count: "42"
        """.trimIndent()
        val scenario = loader.load(yaml)
        val value = scenario.extraData["count"]
        assertTrue(value is com.pastura.models.AnyCodableValue.StringValue)
        assertEquals("42", value.value)
    }

    /** Mixed-type top-level array previously silently dropped the whole field
     * (string-array conversion failed, array-of-dict conversion also failed,
     * so the function returned nil). */
    @Test
    fun throwsOnMixedTypeExtraDataArray() {
        val yaml = """
            id: t
            language: ja
            name: T
            description: T
            agents: 2
            rounds: 1
            context: C
            personas:
              - name: A
                description: D
              - name: B
                description: D
            phases:
              - type: speak_all
                prompt: "Go"
            topics:
              - a
              - 42
        """.trimIndent()
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.contains("'topics'"))
    }

    /** `words: [{ majority: 1, minority: 2 }]` previously stringified the Int
     * values silently (`"1"`, `"2"`). Strict loader throws — word-wolf preset
     * authors intending a numeric tag would fail to notice the coercion. */
    @Test
    fun throwsOnNonStringValueInArrayOfDicts() {
        val yaml = """
            id: t
            language: ja
            name: T
            description: T
            agents: 2
            rounds: 1
            context: C
            personas:
              - name: A
                description: D
              - name: B
                description: D
            phases:
              - type: assign
                source: words
                target: random_one
            words:
              - majority: 1
                minority: 2
        """.trimIndent()
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.contains("'words'"))
    }

    /** `options` containing a non-String element previously silently dropped
     * the whole array. Strict loader throws so the typo surfaces to the
     * user. */
    @Test
    fun throwsOnMixedTypeOptions() {
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: choose
                    prompt: "Choose"
                    options:
                      - cooperate
                      - 42
            """.trimIndent(),
        )
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.contains("'options'"))
    }

    // endregion

    // region Enum-valued phase fields wrong-type (#211)

    /**
     * `target: 42` previously coerced silently via `as? String` -> `nil`,
     * running the assign phase with no target. Strict loader throws with the
     * unified wrong-type format (via `parseOptional<String>`).
     */
    @Test
    fun throwsOnIntAssignTarget() {
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: assign
                    source: words
                    target: 42
            """.trimIndent(),
        )
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val msg = error.message
        assertTrue(msg.contains("'target'"))
        assertTrue(msg.contains("String"))
        assertTrue(!msg.lowercase().contains("missing"))
        // Distinguish from the invalid-enum-value branch ("has invalid target: ...").
        assertTrue(!msg.contains("invalid target"))
    }

    /**
     * `pairing: 42` previously coerced silently to `nil`, running `choose`
     * with no pairing strategy. Strict loader throws.
     */
    @Test
    fun throwsOnIntChoosePairing() {
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: choose
                    pairing: 42
                    options: [a, b]
            """.trimIndent(),
        )
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val msg = error.message
        assertTrue(msg.contains("'pairing'"))
        assertTrue(msg.contains("String"))
        assertTrue(!msg.lowercase().contains("missing"))
        assertTrue(!msg.contains("invalid pairing"))
    }

    /**
     * `logic: true` (YAML 1.1 bare boolean) previously coerced silently to
     * `nil`, producing a score_calc phase with no scoring logic. Strict
     * loader throws.
     */
    @Test
    fun throwsOnBoolScoreCalcLogic() {
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: score_calc
                    logic: true
            """.trimIndent(),
        )
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val msg = error.message
        assertTrue(msg.contains("'logic'"))
        assertTrue(msg.contains("String"))
        assertTrue(!msg.lowercase().contains("missing"))
        assertTrue(!msg.contains("invalid logic"))
    }

    // endregion

    // region max_sentences on phase (#881)

    /**
     * Parse coverage for the per-phase `max_sentences:` key (#881) — guards
     * the literal YAML key name, which a serializer<->loader round-trip alone
     * cannot (a symmetric mis-key would still round-trip).
     */
    @Test
    fun parsesMaxSentencesOnPhase() {
        val yaml = """
            id: t
            language: ja
            name: T
            description: d
            agents: 2
            rounds: 1
            context: c
            personas:
              - name: Alice
                description: a
              - name: Bob
                description: b
            phases:
              - type: speak_each
                prompt: "Speak."
                max_sentences: 5
                output:
                  statement: string
              - type: speak_all
                prompt: "Speak."
                output:
                  statement: string
        """.trimIndent()
        val scenario = loader.load(yaml)
        assertEquals(5, scenario.phases[0].maxSentences)
        // Absent key -> null (no backward-compat fill).
        assertNull(scenario.phases[1].maxSentences)
    }

    // endregion

    // region payoff table on score_calc phase (ADR-027)

    /**
     * Parse coverage for the `payoff:` table on a `pairwise_payoff`
     * `score_calc` phase (ADR-027). Guards the literal YAML key names + strict
     * arity, which a serializer<->loader round-trip alone cannot (a symmetric
     * mis-key round-trips). Kotlin counterpart of Swift's `payoffHeader`
     * private computed property (`ScenarioLoaderTests+Payoff.swift`); local to
     * this region rather than [makeMinimalYAML] since only these five tests
     * use its Alice/Bob-named personas.
     */
    private fun makePayoffYAML(phasesBlock: String): String = buildString {
        appendLine("id: t")
        appendLine("language: ja")
        appendLine("name: T")
        appendLine("description: d")
        appendLine("agents: 2")
        appendLine("rounds: 1")
        appendLine("context: c")
        appendLine("personas:")
        appendLine("  - name: Alice")
        appendLine("    description: a")
        appendLine("  - name: Bob")
        appendLine("    description: b")
        appendLine("phases:")
        append(phasesBlock)
    }

    @Test
    fun parsesPayoffTableOnScoreCalc() {
        val yaml = makePayoffYAML(
            """
                - type: choose
                  options: [協力, 裏切り]
                  pairing: round_robin
                - type: score_calc
                  logic: pairwise_payoff
                  payoff:
                    - when: [協力, 協力]
                      points: [3, 3]
                    - when: [裏切り, 裏切り]
                      points: [1, 1]
            """.trimIndent(),
        )
        val scenario = loader.load(yaml)
        val payoff = scenario.phases[1].payoff
        assertNotNull(payoff)
        assertEquals(2, payoff.size)
        assertEquals(PayoffRule(`when` = listOf("協力", "協力"), points = listOf(3, 3)), payoff[0])
        assertEquals(PayoffRule(`when` = listOf("裏切り", "裏切り"), points = listOf(1, 1)), payoff[1])
    }

    @Test
    fun absentPayoffLeavesNilNotThrow() {
        // `load` stays non-validating (#665): a pairwise_payoff phase with no
        // `payoff:` loads with `payoff == null` — the guaranteed-no-op is a
        // linter concern (R20a), not a load throw.
        val yaml = makePayoffYAML(
            """
                - type: score_calc
                  logic: pairwise_payoff
            """.trimIndent(),
        )
        val scenario = loader.load(yaml)
        assertNull(scenario.phases[0].payoff)
    }

    @Test
    fun throwsOnWhenArityNotTwo() {
        val yaml = makePayoffYAML(
            """
                - type: score_calc
                  logic: pairwise_payoff
                  payoff:
                    - when: [協力]
                      points: [3, 3]
            """.trimIndent(),
        )
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        // The message template names both fields, so assert the discriminating
        // detail suffix, not a bare "when" substring.
        assertTrue(error.message.contains("'when' must be 2 strings"))
    }

    @Test
    fun throwsOnPointsArityNotTwo() {
        val yaml = makePayoffYAML(
            """
                - type: score_calc
                  logic: pairwise_payoff
                  payoff:
                    - when: [協力, 協力]
                      points: [3]
            """.trimIndent(),
        )
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.contains("'points' must be 2 ints"))
    }

    @Test
    fun throwsOnPayoffNotList() {
        val yaml = makePayoffYAML(
            """
                - type: score_calc
                  logic: pairwise_payoff
                  payoff: not_a_list
            """.trimIndent(),
        )
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.contains("payoff"))
    }

    // endregion

    // region conditional phase parsing (loader-facing arms of Swift's ConditionalScenarioIOTests)

    @Test
    fun loadsConditionalWithBothBranches() {
        val yaml = """
            id: test
            language: ja
            name: Test
            description: test
            agents: 2
            rounds: 1
            context: ctx
            personas:
              - name: Alice
                description: a
              - name: Bob
                description: b
            phases:
              - type: conditional
                if: "max_score >= 10"
                then:
                  - type: summarize
                    template: won
                else:
                  - type: speak_all
                    prompt: keep going
                    output:
                      statement: string
        """.trimIndent()

        val scenario = loader.load(yaml)
        assertEquals(1, scenario.phases.size)

        val phase = scenario.phases[0]
        assertEquals(PhaseType.CONDITIONAL, phase.type)
        assertEquals("max_score >= 10", phase.condition)
        assertEquals(1, phase.thenPhases?.size)
        assertEquals(PhaseType.SUMMARIZE, phase.thenPhases?.first()?.type)
        assertEquals("won", phase.thenPhases?.first()?.template)
        assertEquals(1, phase.elsePhases?.size)
        assertEquals(PhaseType.SPEAK_ALL, phase.elsePhases?.first()?.type)
        assertEquals("keep going", phase.elsePhases?.first()?.prompt)
    }

    @Test
    fun loadsConditionalWithOnlyThenBranch() {
        val yaml = """
            id: test
            language: ja
            name: Test
            description: test
            agents: 2
            rounds: 1
            context: ctx
            personas:
              - name: Alice
                description: a
              - name: Bob
                description: b
            phases:
              - type: conditional
                if: "current_round == 1"
                then:
                  - type: summarize
                    template: intro
        """.trimIndent()

        val scenario = loader.load(yaml)
        val phase = scenario.phases[0]
        assertEquals(1, phase.thenPhases?.size)
        // Unspecified `else:` parses as null — the handler falls back to a
        // no-op branch when the condition is false.
        assertNull(phase.elsePhases)
    }

    @Test
    fun rejectsNestedConditionalInThenBranch() {
        val yaml = """
            id: test
            language: ja
            name: Test
            description: test
            agents: 2
            rounds: 1
            context: ctx
            personas:
              - name: Alice
                description: a
              - name: Bob
                description: b
            phases:
              - type: conditional
                if: "current_round == 1"
                then:
                  - type: conditional
                    if: "max_score > 0"
                    then:
                      - type: summarize
                        template: nested
        """.trimIndent()

        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun rejectsNestedConditionalInElseBranch() {
        val yaml = """
            id: test
            language: ja
            name: Test
            description: test
            agents: 2
            rounds: 1
            context: ctx
            personas:
              - name: Alice
                description: a
              - name: Bob
                description: b
            phases:
              - type: conditional
                if: "current_round == 1"
                then:
                  - type: summarize
                    template: fine
                else:
                  - type: conditional
                    if: "current_round == 2"
                    then:
                      - type: summarize
                        template: bad
        """.trimIndent()

        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    /**
     * A `then:` / `else:` that is not a list of mappings is rejected, naming
     * the branch.
     *
     * **No Swift twin to transcribe.** `ScenarioValidationMessage.branchNotArray`
     * is rendered by `ScenarioValidationMessageTests.swift` but no Swift loader
     * test reaches `mapBranch`'s cast, so the mechanism ships unclaimed on both
     * sides; this is the Kotlin-side claimant, in the same category as the
     * "condition-4 sweep additions" region below.
     *
     * Asserts the rendered branch name rather than the exception type alone:
     * `then:` and `else:` share the mechanism, and a `label`/`branch` argument
     * swap is exactly the kind of break a type-only assertion sleeps through.
     */
    @Test
    fun throwsOnScalarThenBranch() {
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: conditional
                    if: "current_round == 1"
                    then: not_a_list
            """.trimIndent(),
        )
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.contains("'then'"), error.message)
    }

    // endregion

    // region condition-4 sweep additions

    /*
     * Every test in this region was added because the ADR-023 §12 condition-4
     * sweep broke the mechanism it names and the suite stayed green — no
     * transcribed Swift case reached it. Only [throwsOnIntegerBeyond32Bits]
     * and [throwsOnIntegerBeyondLongRange] cover Kotlin-only mechanisms with no
     * Swift twin to transcribe. The rest — [throwsOnQuotedProbability],
     * [throwsOnExtraDataArrayMixingDictAndScalar],
     * [throwsOnPersonasListWithScalarElement], and [parsesNoRepeat] — cover
     * mechanisms Swift shares and equally lacks a dedicated claimant for; the
     * absent-`type:` throw ([throwsOnMissingPhaseType], in a different
     * region above) is the same case. The sweep's full table is in the #501
     * record for #1558.
     */

    /**
     * `probability: "0.5"` — a quoted scalar that would parse as a number.
     *
     * `throwsOnProbabilityWrongType` and `throwsOnProbabilityBoolPretendingToBeInt`
     * both survive dropping `parseOptionalDoubleAcceptingInt`'s `isString`
     * guard, because their fixtures fail the `toDoubleOrNull` step anyway. This
     * is the one input the guard alone rejects.
     */
    @Test
    fun throwsOnQuotedProbability() {
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: event_inject
                    source: events
                    probability: "0.5"
                events:
                  - storm
            """.trimIndent(),
        )
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.contains("'probability'"))
    }

    /**
     * A top-level extra-data array mixing a mapping and a scalar.
     *
     * `throwsOnMixedTypeExtraDataArray` mixes only scalars, so it never
     * exercises the whole-collection `all { it is JsonObject }` that decides
     * whether the array-of-dictionaries branch is taken at all.
     */
    @Test
    fun throwsOnExtraDataArrayMixingDictAndScalar() {
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: speak_all
                    prompt: "Speak"
                rules:
                  - name: first
                  - plain_string
            """.trimIndent(),
        )
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.contains("'rules'"))
        assertTrue(error.message.contains("mixed-type arrays are not supported"))
    }

    /**
     * A top-level extra-data mapping whose value is not a String — the
     * `ExtraDataDictNotString` arm, which no transcribed case reached.
     */
    @Test
    fun throwsOnExtraDataDictWithNonStringValue() {
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: speak_all
                    prompt: "Speak"
                config:
                  majority: 1
            """.trimIndent(),
        )
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.contains("'config'"))
        assertTrue(error.message.contains("String"))
        assertTrue(error.message.contains("dictionary values must all be String"))
    }

    /**
     * An integral scalar beyond 32-bit `Int`.
     *
     * Kotlin-only: Swift's `Int` is 64-bit and accepts this, so there is no
     * Swift twin to transcribe. This is the detector for divergence 4 in
     * [ScenarioLoader]'s class KDoc — a claim that had none until the sweep —
     * and it pins the `Int64` fragment [renderActualType] emits so the message
     * is not the bewildering "must be Int, got Int".
     */
    @Test
    fun throwsOnIntegerBeyond32Bits() {
        val yaml = """
            id: t
            language: ja
            name: T
            description: T
            agents: 2147483648
            rounds: 1
            context: C
            personas:
              - name: A
                description: A
            phases:
              - type: speak_all
                prompt: "Speak"
        """.trimIndent()
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.contains("'agents'"))
        assertTrue(error.message.contains("must be Int, got Int64"))
    }

    /**
     * A `personas:` list holding a scalar element.
     *
     * `throwsOnWrongTypeForPersonasList` supplies a non-list, which fails the
     * `as? JsonArray` step first — so it never reaches the whole-collection
     * `all { it is JsonObject }`. Swift's `as? [[String: Any]]` fails for the
     * WHOLE list here, which is why the error names `personas` rather than the
     * offending element.
     */
    @Test
    fun throwsOnPersonasListWithScalarElement() {
        val yaml = """
            id: t
            language: ja
            name: T
            description: T
            agents: 2
            rounds: 1
            context: C
            personas:
              - name: A
                description: A
              - just_a_string
            phases:
              - type: speak_all
                prompt: "Speak"
        """.trimIndent()
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.contains("'personas'"))
    }

    /** `no_repeat:` (#1006) — mapped, but claimed by nothing until the sweep. */
    @Test
    fun parsesNoRepeat() {
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: assign
                    source: words
                    no_repeat: true
                words:
                  - alpha
            """.trimIndent(),
        )
        assertEquals(true, loader.load(yaml).phases[0].noRepeat)
    }

    // endregion

    // region Divergence pins (class KDoc divergences 2 and 4)

    /**
     * An integral scalar beyond even `Long` range.
     *
     * Referenced by name in [ScenarioLoader]'s class KDoc, divergence 4:
     * `YamlCodec`'s `yamlValueToJson` handles `Int` / `Long` / `Float` / `Double`
     * only, so a value outside all four raises `YamlDecodeError.UnsupportedScalar`,
     * which [ScenarioLoader.load] folds into
     * [com.pastura.models.ScenarioValidationMessage.InvalidYAMLFormat] — a
     * whole-document rejection naming no field, unlike
     * [throwsOnIntegerBeyond32Bits]'s field-level [FieldWrongType]-shaped message.
     * Swift's `Int` is 64-bit and has no failure mode at this magnitude at all, so
     * this has no Swift twin either.
     */
    @Test
    fun throwsOnIntegerBeyondLongRange() {
        val yaml = """
            id: t
            language: ja
            name: T
            description: T
            agents: 9223372036854775808
            rounds: 1
            context: C
            personas:
              - name: A
                description: A
            phases:
              - type: speak_all
                prompt: "Speak"
        """.trimIndent()
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.contains("Invalid YAML format"))
    }

    /**
     * **Divergence pin, not desirable behaviour.** Pins [ScenarioLoader]'s class
     * KDoc divergence 2's over-acceptance: a **quoted** `exclude_self: "yes"`
     * parses to `true` here, because [YamlType.BOOL] routes every `isString`
     * primitive through `YAML_11_BOOLEAN_TOKENS` without checking whether the
     * source token was quoted, and snakeyaml gives bare `yes` and quoted `"yes"`
     * the same `isString == true`. Yams keeps a quoted `"yes"` a `String` and
     * Swift rejects it. [throwsOnQuotedExcludeSelf] only drives `"true"`, a token
     * outside [YamlType.BOOL]'s YAML-1.1 token map, so nothing previously pinned
     * this input. A future fix that closes divergence 2 should make this test
     * go red — that is the point of writing it as a pin rather than silently
     * leaving the gap undetected.
     */
    @Test
    fun divergesOnQuotedYesExcludeSelf() {
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: vote
                    prompt: "Vote"
                    exclude_self: "yes"
            """.trimIndent(),
        )
        val scenario = loader.load(yaml)
        assertEquals(true, scenario.phases[0].excludeSelf)
    }

    // endregion

    // region condition-4 sweep additions (C2b surface)

    /*
     * Every test in this region was added because the ADR-023 §12 condition-4
     * sweep over C2b's surface broke the mechanism it names and the suite
     * stayed green — no transcribed Swift case reached it, and Swift has no
     * dedicated claimant for it either. They are Kotlin-side claimants for
     * mechanisms both ports share, the same category as the region above.
     */

    /**
     * A non-Int `points:` element is rejected. Swift's `+Payoff` suite covers
     * both arity failures but never a well-sized row holding a bad value, so
     * the per-element guard (`YamlType.INT`, i.e. Swift's
     * `as? Int, !(value is Bool)`) shipped unclaimed.
     */
    @Test
    fun throwsOnNonIntPayoffPointsValue() {
        val yaml = makePayoffYAML(
            """
                - type: score_calc
                  logic: pairwise_payoff
                  payoff:
                    - when: [a, b]
                      points: [3, "x"]
            """.trimIndent(),
        )
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.contains("'points' has a non-Int value"), error.message)
    }

    /**
     * A **quoted** `points:` element is rejected too.
     *
     * Separate from [throwsOnNonIntPayoffPointsValue] because it claims a
     * different half of the guard: that one detects the throw going missing,
     * this one detects the *cast* being loosened to a lenient
     * `content.toIntOrNull()`, which would accept `"3"` and drop the 32-bit
     * range check with it. Swift needs its explicit `!(value is Bool)` at the
     * same spot for the same reason — `as? Int` launders a boolean — and
     * rejects a quoted scalar identically, so this is parity, not a Kotlin
     * house rule.
     */
    @Test
    fun throwsOnQuotedPayoffPointsValue() {
        val yaml = makePayoffYAML(
            """
                - type: score_calc
                  logic: pairwise_payoff
                  payoff:
                    - when: [a, b]
                      points: [3, "3"]
            """.trimIndent(),
        )
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.contains("'points' has a non-Int value"), error.message)
    }

    /** A scalar `action_deltas:` is rejected, naming the field. */
    @Test
    fun throwsOnNonDictActionDeltas() {
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: relationship_update
                    action_deltas: not_a_dict
            """.trimIndent(),
        )
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.contains("'action_deltas'"), error.message)
    }

    /**
     * An error raised **inside** a `then:` sub-phase names that sub-phase, not
     * its parent.
     *
     * `mapBranch`'s `"$parentLabel.$branchLabel[$subIndex]"` label is the only
     * thing that lets a curator find the offending phase in a conditional, and
     * the sweep showed that collapsing it to the bare parent label left the
     * suite green — every other conditional test asserts on a *well-formed*
     * branch.
     */
    @Test
    fun namesTheOffendingSubPhaseInsideABranch() {
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: conditional
                    if: "current_round == 1"
                    then:
                      - type: speak_each
                        prompt: "Talk"
                        rounds: "3"
            """.trimIndent(),
        )
        val caught = assertFailsWith<SimulationException> { loader.load(yaml) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.contains("Phase 0.then[0]"), error.message)
    }

    // endregion
}
