package com.pastura.engine

import com.pastura.models.AnyCodableValue
import com.pastura.models.Persona
import com.pastura.models.Phase
import com.pastura.models.Scenario

/**
 * Scenario builder for the [ScenarioSemanticLinter] test surface.
 *
 * Kotlin counterpart of the private `makeScenario` helper on Swift's
 * `ScenarioSemanticLinterTests` (`Pastura/PasturaTests/Engine/ScenarioSemanticLinterTests.swift`).
 *
 * Named `makeLinterScenario` rather than `makeScenario` because
 * `ScenarioValidatorTestSupport.kt` already owns `makeValidatorScenario` and
 * `ConditionEvaluatorTestSupport.kt` already owns `makeTestScenario` in this
 * same package.
 *
 * Only the fields the linter's ordering rules read carry meaning; the rest
 * are placeholders matching every Swift helper's defaults.
 */
internal fun makeLinterScenario(
    agents: Int,
    rounds: Int,
    phases: List<Phase>,
    extraData: Map<String, AnyCodableValue> = emptyMap(),
): Scenario = Scenario(
    id = "test",
    name = "Test",
    description = "Test",
    language = "ja",
    agentCount = agents,
    rounds = rounds,
    context = "Context",
    personas = (0 until agents).map { Persona(name = "A$it", description = "D") },
    phases = phases,
    extraData = extraData,
)
