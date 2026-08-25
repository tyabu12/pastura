package com.pastura.engine

import com.pastura.models.AnyCodableValue
import com.pastura.models.AssignTarget
import com.pastura.models.Persona
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import com.pastura.models.SimulationError
import kotlin.test.Test
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/**
 * commonTest sibling of Swift's `ConditionalValidatorTests.swift`,
 * `ConditionalValidatorTests+Narrate.swift`,
 * `ConditionalValidatorTests+ParseTime.swift`,
 * `ConditionalValidatorTests+Reflect.swift`,
 * `ConditionalValidatorTests+RelationshipUpdate.swift`, and
 * `ConditionalValidatorTests+Whisper.swift`
 * (`Pastura/PasturaTests/Engine/`) — 24 tests, 1:1 by name with those six files.
 *
 * The parse-time tests (`rejectsMalformedConditionAtValidateTime`,
 * `rejectsDanglingCombinatorAtValidateTime`) exercise
 * `ConditionEvaluator.parse` indirectly: `ScenarioValidator.validateConditionalPhase`
 * calls it as a pre-flight check and, on a
 * `SimulationError.ScenarioValidationFailed`, rewraps the message as
 * `"$phaseLabel: ..."` before rethrowing — so these tests pin the wrapped
 * validator-level message, not `ConditionEvaluator.parse`'s own rendering.
 */
class ConditionalValidatorTests {

    private val validator = ScenarioValidator()

    /**
     * Kotlin counterpart of Swift's `ConditionalValidatorTests.makeScenario`.
     * Two agents, one round, `ja` scenario language — shared by every sibling
     * test group below via the same suite-scoped helper Swift uses.
     */
    private fun makeScenario(phases: List<Phase>): Scenario = Scenario(
        id = "t",
        name = "T",
        description = "t",
        language = "ja",
        agentCount = 2,
        rounds = 1,
        context = "c",
        personas = listOf(Persona(name = "A", description = "a"), Persona(name = "B", description = "b")),
        phases = phases,
    )

    // region ConditionalValidatorTests.swift

    @Test
    fun acceptsValidConditional() {
        val scenario = makeScenario(
            phases = listOf(
                Phase(
                    type = PhaseType.CONDITIONAL,
                    condition = "current_round == 1",
                    thenPhases = listOf(Phase(type = PhaseType.SUMMARIZE, template = "t")),
                ),
            ),
        )
        validator.validate(scenario)
    }

    @Test
    fun rejectsEmptyCondition() {
        val scenario = makeScenario(
            phases = listOf(
                Phase(
                    type = PhaseType.CONDITIONAL,
                    condition = "",
                    thenPhases = listOf(Phase(type = PhaseType.SUMMARIZE, template = "t")),
                ),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun rejectsMissingCondition() {
        val scenario = makeScenario(
            phases = listOf(
                Phase(
                    type = PhaseType.CONDITIONAL,
                    thenPhases = listOf(Phase(type = PhaseType.SUMMARIZE, template = "t")),
                ),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun rejectsWhitespaceOnlyCondition() {
        val scenario = makeScenario(
            phases = listOf(
                Phase(
                    type = PhaseType.CONDITIONAL,
                    condition = "   \n  ",
                    thenPhases = listOf(Phase(type = PhaseType.SUMMARIZE, template = "t")),
                ),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun rejectsBothBranchesEmpty() {
        val scenario = makeScenario(
            phases = listOf(
                Phase(
                    type = PhaseType.CONDITIONAL,
                    condition = "current_round == 1",
                    thenPhases = emptyList(),
                    elsePhases = emptyList(),
                ),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun rejectsBothBranchesNil() {
        val scenario = makeScenario(
            phases = listOf(Phase(type = PhaseType.CONDITIONAL, condition = "current_round == 1")),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun acceptsOnlyThenBranch() {
        val scenario = makeScenario(
            phases = listOf(
                Phase(
                    type = PhaseType.CONDITIONAL,
                    condition = "current_round == 1",
                    thenPhases = listOf(Phase(type = PhaseType.SUMMARIZE, template = "t")),
                ),
            ),
        )
        validator.validate(scenario)
    }

    @Test
    fun acceptsOnlyElseBranch() {
        val scenario = makeScenario(
            phases = listOf(
                Phase(
                    type = PhaseType.CONDITIONAL,
                    condition = "current_round == 1",
                    elsePhases = listOf(Phase(type = PhaseType.SUMMARIZE, template = "t")),
                ),
            ),
        )
        validator.validate(scenario)
    }

    @Test
    fun rejectsNestedConditionalInThenBranch() {
        // Non-YAML construction path — the loader covers the YAML side. This
        // validator check catches scenarios built programmatically (tests,
        // future editors, migrations).
        val scenario = makeScenario(
            phases = listOf(
                Phase(
                    type = PhaseType.CONDITIONAL,
                    condition = "current_round == 1",
                    thenPhases = listOf(Phase(type = PhaseType.CONDITIONAL, condition = "max_score > 0")),
                ),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun rejectsNestedConditionalInElseBranch() {
        val scenario = makeScenario(
            phases = listOf(
                Phase(
                    type = PhaseType.CONDITIONAL,
                    condition = "current_round == 1",
                    thenPhases = listOf(Phase(type = PhaseType.SUMMARIZE, template = "ok")),
                    elsePhases = listOf(Phase(type = PhaseType.CONDITIONAL, condition = "max_score > 0")),
                ),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    // Regression: sub-phase semantic checks (e.g. assign target/source shape)
    // must run inside conditional branches, not only at the top level.
    @Test
    fun rejectsAssignShapeMismatchInThenBranch() {
        val scenario = Scenario(
            id = "t",
            name = "T",
            description = "t",
            language = "ja",
            agentCount = 2,
            rounds = 1,
            context = "c",
            personas = listOf(Persona(name = "A", description = "a"), Persona(name = "B", description = "b")),
            phases = listOf(
                Phase(
                    type = PhaseType.CONDITIONAL,
                    condition = "current_round == 1",
                    thenPhases = listOf(
                        // target .all with arrayOfDictionaries source is the exact
                        // shape bug `validateAssignPhaseShape` exists to catch.
                        Phase(type = PhaseType.ASSIGN, source = "topics", target = AssignTarget.ALL),
                    ),
                ),
            ),
            extraData = mapOf(
                "topics" to AnyCodableValue.ArrayOfDictionariesValue(
                    listOf(mapOf("majority" to "cat", "minority" to "dog")),
                ),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    // event_inject is allowed inside a conditional branch (consistent with
    // assign / score_calc nesting). The validator applies the same
    // shape-check it does at the top level.

    @Test
    fun acceptsEventInjectInThenBranch() {
        val scenario = Scenario(
            id = "t",
            name = "T",
            description = "t",
            language = "ja",
            agentCount = 2,
            rounds = 1,
            context = "c",
            personas = listOf(Persona(name = "A", description = "a"), Persona(name = "B", description = "b")),
            phases = listOf(
                Phase(
                    type = PhaseType.CONDITIONAL,
                    condition = "current_round == 1",
                    thenPhases = listOf(
                        Phase(type = PhaseType.EVENT_INJECT, source = "events", probability = 0.5),
                    ),
                ),
            ),
            extraData = mapOf("events" to AnyCodableValue.ArrayValue(listOf("x", "y"))),
        )
        validator.validate(scenario)
    }

    @Test
    fun rejectsEventInjectInThenBranchWithMissingSource() {
        val scenario = Scenario(
            id = "t",
            name = "T",
            description = "t",
            language = "ja",
            agentCount = 2,
            rounds = 1,
            context = "c",
            personas = listOf(Persona(name = "A", description = "a"), Persona(name = "B", description = "b")),
            phases = listOf(
                Phase(
                    type = PhaseType.CONDITIONAL,
                    condition = "current_round == 1",
                    thenPhases = listOf(
                        // source key absent from extraData — should fail with the same
                        // "not found" message we'd see at the top level, prefixed with
                        // the branch label.
                        Phase(type = PhaseType.EVENT_INJECT, source = "missing_events", probability = 1.0),
                    ),
                ),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val message = error.message
        assertTrue(message.contains("then[1]"))
        assertTrue(message.contains("'missing_events'"))
        assertTrue(message.contains("not found"))
    }

    @Test
    fun rejectsEventInjectInElseBranchWithProbabilityOutOfRange() {
        val scenario = Scenario(
            id = "t",
            name = "T",
            description = "t",
            language = "ja",
            agentCount = 2,
            rounds = 1,
            context = "c",
            personas = listOf(Persona(name = "A", description = "a"), Persona(name = "B", description = "b")),
            phases = listOf(
                Phase(
                    type = PhaseType.CONDITIONAL,
                    condition = "current_round == 99",
                    thenPhases = listOf(Phase(type = PhaseType.SUMMARIZE, template = "ok")),
                    elsePhases = listOf(
                        Phase(type = PhaseType.EVENT_INJECT, source = "events", probability = 2.0),
                    ),
                ),
            ),
            extraData = mapOf("events" to AnyCodableValue.ArrayValue(listOf("x"))),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val message = error.message
        assertTrue(message.contains("else[1]"))
        assertTrue(message.contains("out of range"))
    }

    // endregion

    // region ConditionalValidatorTests+Narrate.swift
    // narrate is NOT allowed inside a conditional branch in v1 (#909). The
    // validator rejects it at load-time (mirroring the reflect / whisper /
    // relationship_update rejections) so it fails at the load gate rather than
    // mid-run at `ConditionalHandler` dispatch (which omits narrate from its
    // sub-handler map).

    @Test
    fun rejectsNarrateInThenBranch() {
        val scenario = makeScenario(
            phases = listOf(
                Phase(
                    type = PhaseType.CONDITIONAL,
                    condition = "current_round == 1",
                    thenPhases = listOf(Phase(type = PhaseType.NARRATE, prompt = "Narrate.")),
                ),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun rejectsNarrateInElseBranch() {
        val scenario = makeScenario(
            phases = listOf(
                Phase(
                    type = PhaseType.CONDITIONAL,
                    condition = "current_round == 1",
                    thenPhases = listOf(Phase(type = PhaseType.SUMMARIZE, template = "ok")),
                    elsePhases = listOf(Phase(type = PhaseType.NARRATE, prompt = "Narrate.")),
                ),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val message = error.message
        assertTrue(message.contains("else[1]"))
        assertTrue(message.contains("narrate"))
    }

    // endregion

    // region ConditionalValidatorTests+ParseTime.swift
    // Pre-flight parse-time validation for conditional `if:` expressions.
    // These cases ensure that malformed expressions surface at scenario-load
    // time (validator), not mid-simulation when the handler dispatches —
    // critical for gallery curation where curated scenarios must fail before
    // shipping.

    @Test
    fun rejectsMalformedConditionAtValidateTime() {
        val scenario = makeScenario(
            phases = listOf(
                Phase(
                    type = PhaseType.CONDITIONAL,
                    condition = "(current_round == 1 && max_score > 0",
                    thenPhases = listOf(Phase(type = PhaseType.SUMMARIZE, template = "t")),
                ),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun rejectsDanglingCombinatorAtValidateTime() {
        val scenario = makeScenario(
            phases = listOf(
                Phase(
                    type = PhaseType.CONDITIONAL,
                    condition = "current_round == 1 &&",
                    thenPhases = listOf(Phase(type = PhaseType.SUMMARIZE, template = "t")),
                ),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    // endregion

    // region ConditionalValidatorTests+Reflect.swift
    // reflect is NOT allowed inside a conditional branch in v1. The validator
    // rejects it at load-time (mirroring the nested-conditional rejection) so
    // it fails here rather than at `ConditionalHandler` dispatch.

    @Test
    fun rejectsReflectInThenBranch() {
        val scenario = makeScenario(
            phases = listOf(
                Phase(
                    type = PhaseType.CONDITIONAL,
                    condition = "current_round == 1",
                    thenPhases = listOf(
                        Phase(
                            type = PhaseType.REFLECT,
                            prompt = "Reflect.",
                            outputSchema = mapOf("note" to "string"),
                        ),
                    ),
                ),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun rejectsReflectInElseBranch() {
        val scenario = makeScenario(
            phases = listOf(
                Phase(
                    type = PhaseType.CONDITIONAL,
                    condition = "current_round == 1",
                    thenPhases = listOf(Phase(type = PhaseType.SUMMARIZE, template = "ok")),
                    elsePhases = listOf(
                        Phase(
                            type = PhaseType.REFLECT,
                            prompt = "Reflect.",
                            outputSchema = mapOf("note" to "string"),
                        ),
                    ),
                ),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val message = error.message
        assertTrue(message.contains("else[1]"))
        assertTrue(message.contains("reflect"))
    }

    // endregion

    // region ConditionalValidatorTests+RelationshipUpdate.swift
    // relationship_update is NOT allowed inside a conditional branch in v1.
    // The validator rejects it at load-time (mirroring the nested-conditional,
    // reflect, and whisper rejections) so it fails here rather than at
    // `ConditionalHandler` dispatch — where it is also absent from
    // `subHandlers` as a structural backstop.

    @Test
    fun rejectsRelationshipUpdateInThenBranch() {
        val scenario = makeScenario(
            phases = listOf(
                Phase(
                    type = PhaseType.CONDITIONAL,
                    condition = "current_round == 1",
                    thenPhases = listOf(Phase(type = PhaseType.RELATIONSHIP_UPDATE, voteAgainst = -1)),
                ),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun rejectsRelationshipUpdateInElseBranch() {
        val scenario = makeScenario(
            phases = listOf(
                Phase(
                    type = PhaseType.CONDITIONAL,
                    condition = "current_round == 1",
                    thenPhases = listOf(Phase(type = PhaseType.SUMMARIZE, template = "ok")),
                    elsePhases = listOf(
                        Phase(type = PhaseType.RELATIONSHIP_UPDATE, actionDeltas = mapOf("cooperate" to 1)),
                    ),
                ),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val message = error.message
        assertTrue(message.contains("else[1]"))
        assertTrue(message.contains("relationship_update"))
    }

    // endregion

    // region ConditionalValidatorTests+Whisper.swift
    // whisper is NOT allowed inside a conditional branch in v1. The validator
    // rejects it at load-time (mirroring the nested-conditional and reflect
    // rejections) so it fails here rather than at `ConditionalHandler`
    // dispatch.

    @Test
    fun rejectsWhisperInThenBranch() {
        val scenario = makeScenario(
            phases = listOf(
                Phase(
                    type = PhaseType.CONDITIONAL,
                    condition = "current_round == 1",
                    thenPhases = listOf(
                        Phase(
                            type = PhaseType.WHISPER,
                            prompt = "Whisper.",
                            outputSchema = mapOf("statement" to "string"),
                        ),
                    ),
                ),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }

    @Test
    fun rejectsWhisperInElseBranch() {
        val scenario = makeScenario(
            phases = listOf(
                Phase(
                    type = PhaseType.CONDITIONAL,
                    condition = "current_round == 1",
                    thenPhases = listOf(Phase(type = PhaseType.SUMMARIZE, template = "ok")),
                    elsePhases = listOf(
                        Phase(
                            type = PhaseType.WHISPER,
                            prompt = "Whisper.",
                            outputSchema = mapOf("statement" to "string"),
                        ),
                    ),
                ),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        val message = error.message
        assertTrue(message.contains("else[1]"))
        assertTrue(message.contains("whisper"))
    }

    // endregion
}
