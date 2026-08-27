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
 * Only the fields the linter's rules read carry meaning; the rest are
 * placeholders matching every Swift helper's defaults.
 *
 * **The helper layer is deliberately not 1:1.** Swift's linter tests use three
 * factories — `makeScenario` and `makeEventScenario`
 * (`ScenarioSemanticLinterTests+Ordering.swift`) and `makeLogWindowScenario`
 * (the tail of `ScenarioSemanticLinterTests+Config.swift`) — which differ only
 * in which optional fields they set. All three fold into this one builder via
 * named arguments ([extraData] for the event factory, [logWindow] for the R17
 * one); the test *cases* stay a strict 1:1 mirror, the factories do not.
 */
internal fun makeLinterScenario(
    agents: Int,
    rounds: Int,
    phases: List<Phase>,
    extraData: Map<String, AnyCodableValue> = emptyMap(),
    logWindow: Int? = null,
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
    logWindow = logWindow,
)
