package com.pastura.engine

import com.pastura.models.Persona
import com.pastura.models.Scenario

/**
 * Kotlin counterpart of the Swift `makeTestScenario(agentNames:rounds:)` helper
 * (`EngineTestHelpers.swift`). Builds a minimal [Scenario] for `ConditionEvaluator`
 * tests — only the fields the derived-variable resolver reads (`rounds`,
 * `personas`) carry meaning; the rest are placeholders.
 *
 * Note: unlike Swift (mutable `var` state), Kotlin [com.pastura.models.SimulationState]
 * is an immutable `data class` — tests set state via `SimulationState.initial(scenario).copy(...)`,
 * not field mutation.
 */
internal fun makeTestScenario(
    agentNames: List<String>,
    rounds: Int = 1,
): Scenario = Scenario(
    id = "test-condition",
    name = "Condition Test",
    description = "A scenario for ConditionEvaluator tests.",
    language = "en",
    agentCount = agentNames.size,
    rounds = rounds,
    context = "You are participating in a test.",
    personas = agentNames.map { Persona(name = it, description = "Test persona.") },
    phases = emptyList(),
)
