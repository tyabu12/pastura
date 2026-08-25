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
 * (`Pastura/PasturaTests/Engine/`) — 62 tests, 1:1 by name with those four files.
 *
 * The ADR-023 §12 condition-4 perturbation record is added in a later commit.
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
