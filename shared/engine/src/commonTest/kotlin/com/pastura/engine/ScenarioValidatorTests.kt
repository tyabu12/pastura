package com.pastura.engine

import com.pastura.models.AnyCodableValue
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.SimulationError
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/**
 * Smoke coverage for [ScenarioValidator]'s run gate — one accept, one limit
 * rejection, one shape rejection. The remaining 60 siblings of Swift's
 * `ScenarioValidatorTests` land in a follow-up commit, so three is the current
 * count, not the intended coverage.
 */
class ScenarioValidatorTests {

    private val validator = ScenarioValidator()

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
    fun rejectsEventInjectWithProbabilityAboveOne() {
        val scenario = makeEventInjectScenario(
            source = "events",
            probability = 1.5,
            extraData = mapOf("events" to AnyCodableValue.ArrayValue(listOf("A meteor lands."))),
        )
        val caught = assertFailsWith<SimulationException> { validator.validate(scenario) }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }
}
