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
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
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
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
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
}
