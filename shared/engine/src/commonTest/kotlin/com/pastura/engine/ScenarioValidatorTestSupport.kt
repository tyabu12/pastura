package com.pastura.engine

import com.pastura.models.AnyCodableValue
import com.pastura.models.AssignTarget
import com.pastura.models.Persona
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario

/**
 * Scenario builder for the [ScenarioValidator] test surface.
 *
 * Kotlin counterpart of the four private helpers on Swift's
 * `ScenarioValidatorTests` (`makeScenario` / `makeLogWindowScenario` /
 * `makeAssignScenario` / `makeEventInjectScenario`,
 * `Pastura/PasturaTests/Engine/ScenarioValidatorTests.swift`). They differ only
 * in which optional field they thread through, so this port collapses them into
 * one builder with defaults plus the thin wrappers below.
 *
 * Shared by `ScenarioValidatorTests.kt` and `ConditionalValidatorTests.kt` (the
 * latter lands with the rest of the 63-test port), which is why it is a
 * top-level file rather than a private helper on one suite. It is named
 * `makeValidatorScenario` rather than `makeScenario` because
 * `ConditionEvaluatorTestSupport.kt` already owns `makeTestScenario` in this
 * same package.
 *
 * Only the fields the validator reads carry meaning; the rest are placeholders.
 */
internal fun makeValidatorScenario(
    agents: Int,
    rounds: Int,
    phases: List<Phase>,
    logWindow: Int? = null,
    language: String = "en",
    simulationLanguage: String? = null,
    extraData: Map<String, AnyCodableValue> = emptyMap(),
): Scenario = Scenario(
    id = "test",
    name = "Test",
    description = "Test",
    language = language,
    simulationLanguage = simulationLanguage,
    agentCount = agents,
    rounds = rounds,
    logWindow = logWindow,
    context = "Context",
    personas = (1..agents).map { Persona(name = "Agent $it", description = "D") },
    phases = phases,
    extraData = extraData,
)

/** Two agents, one `speak_all` phase, and the `log_window` under test (#907). */
internal fun makeLogWindowScenario(logWindow: Int?): Scenario = makeValidatorScenario(
    agents = 2,
    rounds = 1,
    phases = listOf(Phase(type = PhaseType.SPEAK_ALL)),
    logWindow = logWindow,
)

/** Two agents, a single `assign` phase with the target/source shape under test. */
internal fun makeAssignScenario(
    target: AssignTarget?,
    source: String?,
    extraData: Map<String, AnyCodableValue>,
): Scenario = makeValidatorScenario(
    agents = 2,
    rounds = 1,
    phases = listOf(Phase(type = PhaseType.ASSIGN, source = source, target = target)),
    extraData = extraData,
)

/** Two agents, a single `event_inject` phase with the shape under test. */
internal fun makeEventInjectScenario(
    source: String?,
    probability: Double?,
    extraData: Map<String, AnyCodableValue>,
): Scenario = makeValidatorScenario(
    agents = 2,
    rounds = 1,
    phases = listOf(
        Phase(type = PhaseType.EVENT_INJECT, source = source, probability = probability),
    ),
    extraData = extraData,
)
