package com.pastura.engine

import com.pastura.models.PhaseType
import com.pastura.models.SimulationError
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * commonTest sibling of Swift's `ScenarioLoaderTests.swift`,
 * `ScenarioLoaderTests+Language.swift`, and `ScenarioLoaderTests+StrictTypes.swift`
 * (`Pastura/PasturaTests/Engine/`) — 43 of the port's 44 planned 1:1 transcriptions
 * landed; see the note below on the one that did not.
 *
 * **Scope.** Only [ScenarioLoader.load]'s YAML-ingest and top-level-mapping
 * behaviour is covered here, matching [ScenarioLoader]'s own class KDoc: the
 * six `estimateInferenceCount` tests (that estimator landed separately, in
 * [InferenceEstimator]), `parsesPhaseWithAllFields`, the three
 * `relationship_update` tests, and the eleven enum / `outputSchema` /
 * `payoff` arms of `ScenarioLoaderTests+StrictTypes.swift` are deferred to a
 * follow-up PR — [ScenarioLoader.mapPhase]'s KDoc documents `output`,
 * `target`, `pairing`, `logic`, `then` / `else`, `action_deltas`, and `payoff`
 * as unmapped "C2b" fields, so a test asserting on any of them cannot pass
 * against today's loader.
 *
 * **`parsesPhaseSpeakAll` is the one planned transcription NOT landed here.**
 * Swift's version asserts `phase.outputSchema?["statement"] == "string"`, and
 * `outputSchema` is exactly the C2b gap above — [ScenarioLoader.mapPhase]
 * passes it through as a hardcoded `null`. Fixing that would mean widening
 * `mapPhase` (adding `parseOutputSchema`), which is out of bounds for a
 * mechanical transcription task; the test belongs with the rest of C2b's
 * `outputSchema` coverage. `loadsMinimalValidScenario` already exercises the
 * same YAML shape (a `speak_all` phase carrying an `output:` block) without
 * asserting on the unmapped field, so the "does an `output:` block break
 * parsing" question stays covered.
 *
 * ## ADR-023 §12 condition-4 perturbation record
 *
 * Each mechanism of
 * `shared/engine/src/commonMain/kotlin/com/pastura/engine/ScenarioLoader.kt` was
 * broken in isolation and the named **dedicated claimant** — a test that detects the
 * break through **its own** assertion — confirmed to redden. **43 mutations**, each
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
 * **40 of the 43 reddened.** The three that did not are accounted for below the
 * table; one of them is a deliberate negative control.
 *
 * | Mechanism broken | Mutation | Dedicated claimant | Incidental |
 * |---|---|---|---|
 * | Code-fence strip | `filterNot { … startsWith("```") }` → `filterNot { false }` | [stripsCodeFencesBeforeParsing] | none |
 * | Decode failure → `InvalidYAMLFormat` | the `throw` → `JsonObject(emptyMap())` | [throwsOnInvalidYAML] — assertion **strengthened**, note 1 | none |
 * | Non-mapping root → `InvalidYAMLFormat` | the `?: throw` → `?: JsonObject(emptyMap())` | [throwsOnNonMappingRoot], [throwsOnEmptyDocument] — both **added**, note 1 | none |
 * | `parseRequired` missing-key arm | `?: throw …MissingRequiredField` → `?: JsonNull` | [throwsOnMissingRequiredField] — assertion **strengthened**, note 1 | none |
 * | `parseRequired` wrong-type arm | early-return the cast, no throw | [throwsOnWrongTypeForRequiredString], [throwsOnWrongTypeForRequiredInt], [throwsOnWrongTypeForPersonasList], [throwsOnWrongTypeForPersonaName] | none |
 * | `parseOptional` absent-key arm | `?: return null` → `?: JsonNull` | [absentLogWindowIsNil] and 32 others | 32 — every fixture that omits an optional key then throws |
 * | `parseOptional` wrong-type arm | the `throw` dropped | [throwsOnQuotedSubRounds], [throwsOnQuotedExcludeSelf], [throwsOnIntExcludeSelf], [throwsOnMixedTypeOptions], [throwsOnWrongTypeForPersonaSecret], [bareSecretKeyWithNoValueIsATypeError] | 1 |
 * | `probability` quoted/bool guard | `!it.isString && !it.isYamlBooleanLiteral()` dropped | [throwsOnQuotedProbability] — **added**, note 2 | none |
 * | `language` membership | `!in` → `in` | [rejectsLanguageInvalid] | none |
 * | `simulation_language` membership | `!in` → `in` (not `if (false)`; see note 3) | [rejectsSimulationLanguageInvalid] | 1 — [parsesSimulationLanguageEn] |
 * | persona count matches `agents` | `!=` → `==` | [throwsOnAgentCountMismatch] | none |
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
 * | Phase wiring: `prompt` | read → hardcoded `null` | [parsesPhaseSpeakAll], [phaseSpecialisationIsStillUnmapped] | none |
 * | Phase wiring: `exclude_self` | read → `null` | [acceptsYAML11BooleanExcludeSelf], [throwsOnQuotedExcludeSelf], [throwsOnIntExcludeSelf] | none |
 * | Phase wiring: `options` | read → `null` | [throwsOnMixedTypeOptions] | none |
 * | Phase wiring: `rounds` → `subRounds` | read → `null` | [throwsOnQuotedSubRounds] | none |
 * | Phase wiring: `probability` | read → `null` | [parsesProbabilityAsDouble], [parsesProbabilityAsIntCoercesToDouble], [throwsOnProbabilityWrongType], [throwsOnProbabilityBoolPretendingToBeInt], [parsesEventInjectFullSpec] | none |
 * | Phase wiring: `as` → `eventVariable` | read → `null` | [parsesEventInjectFullSpec] | none |
 * | Phase wiring: `no_repeat` | read → `null` | [parsesNoRepeat] — **added**, note 2 | none |
 * | Phase wiring: `source` | read → `null` | [parsesEventInjectFullSpec], [parsesEventInjectMinimalSpec], [phaseSpecialisationIsStillUnmapped] | none |
 * | Phase wiring: `if` → `condition` | read → `null` | [phaseSpecialisationIsStillUnmapped] | none |
 * | Scenario wiring: `log_window` | read → `null` | [parsesLogWindow], [rejectsNonIntLogWindow] | none |
 * | **NEGATIVE CONTROL** — `acceptedLanguagesList` ordering | `.sorted()` → `.sortedDescending()` | *(none — expected green)* | none |
 *
 * 1. **Three mechanisms were claimed only by a bare "it throws" assertion**, so
 *    the mutation moved the failure to a *different* message and the test stayed
 *    green. Common cause: the loader has one exception type, so a type-only
 *    assertion cannot tell its layers apart — the same shape B1's sweep found in
 *    `ScenarioValidator`. Fixed by asserting the rendered message.
 * 2. **Six mechanisms had no claimant at all**, and five of them have none on the
 *    **Swift** side either — nothing in `ScenarioLoaderTests*.swift` drives a
 *    quoted `probability`, a dictionary-valued extra-data key, an extra-data
 *    array mixing mappings and scalars, a `personas:` list holding a scalar, an
 *    absent `type:`, or `no_repeat`. Each gained a test in the
 *    "condition-4 sweep additions" region.
 * 3. `if (false)` does **not** compile on the `simulation_language` arm: the
 *    smart cast from the `!= null` half is lost and the later `!!`-free use
 *    fails. The polarity flip is the compiling substitute, and it reddens the
 *    accepting fixture as well as the rejecting one.
 * 4. The nested-`conditional` depth guard is **structurally unreachable in this
 *    port**: `depth` has no non-zero caller until C2b's `mapBranch` descends
 *    into `then:` / `else:`. Expected green; C2b must claim it.
 * 5. `Int` is 32-bit in Kotlin and 64-bit in Swift, so this mechanism and its
 *    `Int64` rendering exist only on this side and have no Swift twin to
 *    transcribe. [throwsOnIntegerBeyond32Bits] is the detector for what was
 *    otherwise a KDoc claim with nothing behind it.
 * 6. `isYamlBooleanLiteral`'s `!isString` guard is **defence in depth**: every
 *    caller that could be fooled by a quoted `"true"` is already `isString`-
 *    guarded on its own. Expected green — kept because a future caller without
 *    that guard would need it, and removing it would make this file's one
 *    boolean-literal predicate quietly wrong.
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

    /**
     * Swift's `parsesPhaseSpeakAll`, minus its third assertion.
     *
     * Swift also reads `phase.outputSchema?["statement"]`; `output:` is one of
     * the seven C2b fields [ScenarioLoader.mapPhase] leaves `null`, and
     * [phaseSpecialisationIsStillUnmapped] is what pins that gap until C2b
     * closes it. The two `speak_all` fields this port *does* map are asserted
     * here so the case is not silently absent from the suite in the meantime.
     */
    @Test
    fun parsesPhaseSpeakAll() {
        val scenario = loader.load(makeMinimalYAML())
        val phase = scenario.phases[0]
        assertEquals(PhaseType.SPEAK_ALL, phase.type)
        assertEquals("Speak your mind.", phase.prompt)
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
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun parsesPersonasCorrectly() {
        val scenario = loader.load(makeMinimalYAML())
        assertEquals("Alice", scenario.personas[0].name)
        assertEquals("A strategist", scenario.personas[0].description)
        assertEquals("Bob", scenario.personas[1].name)
    }

    // `parsesPhaseSpeakAll` is deliberately NOT transcribed here — see the
    // class KDoc's "parsesPhaseSpeakAll is the one planned transcription NOT
    // landed here" paragraph. Its Swift assertion on `phase.outputSchema` hits
    // ScenarioLoader.kt's C2b gap (outputSchema is a hardcoded `null` today),
    // and watering the assertion down to only the fields that do parse would
    // silently narrow the test's meaning rather than flag the gap — the STOP
    // RULE calls for removal plus a report, not a weakened stand-in.

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
     * missing-type throw to `speak_all` left the suite green. The two collapse
     * to one message by design — see `parsePhaseType`'s KDoc.
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
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
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
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
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
        // Bool-as-Int laundering would let `probability: true` pass — guard
        // against it explicitly so the Int-coercion exception stays narrow.
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
            assertNull(loader.load(yaml).personas[0].secret)
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
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
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

    // region condition-4 sweep additions

    /*
     * Every test in this region was added because the ADR-023 §12 condition-4
     * sweep broke the mechanism it names and the suite stayed green — no
     * transcribed Swift case reached it. Three of them (the `probability`
     * quoted-scalar guard, the dictionary-valued extra-data guard, and the
     * absent-`type:` throw, above) have no dedicated claimant on the **Swift**
     * side either; the rest cover Kotlin-only mechanisms the port introduced.
     * The sweep's full table is in the #501 record for #1558.
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

    // region C2b gap pin

    /**
     * Pins the seven phase fields this port deliberately leaves unmapped.
     *
     * The YAML below populates every one of them, and every assertion says
     * `null`. That inverts the usual polarity on purpose: the test is **not**
     * asserting correct behaviour — it is asserting a known-incomplete state,
     * so that the moment C2b teaches [ScenarioLoader.mapPhase] to read any of
     * these keys, this test goes red and forces both itself and the
     * `PORT IN PROGRESS` section of [ScenarioLoader]'s class KDoc to be
     * deleted. A pin that self-destructs is the point; one that stayed green
     * after the gap closed would be the coverage theater
     * `.claude/rules/kmp-interop.md` Pattern 4 warns about.
     *
     * The `assertEquals(5, …)` guards the pin's own reachability: if a future
     * edit made `load` reject this fixture outright, every `assertNull` below
     * would become vacuous rather than failing.
     *
     * **Delete this whole region in C2b**, together with the KDoc section it
     * names.
     */
    @Test
    fun phaseSpecialisationIsStillUnmapped() {
        val yaml = makeMinimalYAML(
            """
                phases:
                  - type: choose
                    prompt: "Choose"
                    output:
                      action: string
                    pairing: round_robin
                  - type: assign
                    source: words
                    target: random_one
                  - type: score_calc
                    logic: pairwise_payoff
                    payoff:
                      - when: [cooperate, cooperate]
                        points: [3, 3]
                  - type: relationship_update
                    action_deltas:
                      betray: -2
                  - type: conditional
                    if: "round == 1"
                    then:
                      - type: speak_all
                        prompt: "Hi"
                    else:
                      - type: eliminate
            """.trimIndent(),
        )
        val phases = loader.load(yaml).phases
        assertEquals(5, phases.size)

        assertNull(phases[0].outputSchema, "output: is C2b")
        assertNull(phases[0].pairing, "pairing: is C2b")
        assertNull(phases[1].target, "target: is C2b")
        assertNull(phases[2].logic, "logic: is C2b")
        assertNull(phases[2].payoff, "payoff: is C2b")
        assertNull(phases[3].actionDeltas, "action_deltas: is C2b")
        assertNull(phases[4].thenPhases, "then: is C2b")
        assertNull(phases[4].elsePhases, "else: is C2b")

        // The C2a-mapped fields on the same phases DO land — this half of the
        // pin is a positive control, so a `load` that silently returned an
        // empty phase would fail here rather than passing the assertNulls.
        assertEquals("Choose", phases[0].prompt)
        assertEquals("words", phases[1].source)
        assertEquals("round == 1", phases[4].condition)
    }

    // endregion
}
