package com.pastura.engine

import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.SimulationError
import kotlin.test.Test
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/**
 * Smoke coverage for [ScenarioValidator.validateForCommit] — the commit-gate
 * half of the validator, ported from Swift's
 * `Pastura/Pastura/Engine/ScenarioValidator+CanonicalFields.swift`.
 *
 * Deliberately minimal: three cases pinning accept, reject, and the
 * phase-type-derived branch label. The full 1:1 port of Swift's
 * `Pastura/PasturaTests/Engine/ScenarioValidatorTests+Commit.swift` (29 tests) lands in
 * the next commit on this branch.
 */
class ScenarioValidatorCommitTests {

    private val validator = ScenarioValidator()

    @Test
    fun acceptsSpeakAllWithCanonicalStatementField() {
        val scenario = makeValidatorScenario(
            agents = 2,
            rounds = 1,
            phases = listOf(
                Phase(type = PhaseType.SPEAK_ALL, outputSchema = mapOf("statement" to "string")),
            ),
        )
        val result = validator.validateForCommit(scenario)
        assertTrue(result.warnings.isEmpty())
    }

    @Test
    fun rejectsSpeakAllMissingCanonicalStatementField() {
        val scenario = makeValidatorScenario(
            agents = 2,
            rounds = 1,
            phases = listOf(
                Phase(type = PhaseType.SPEAK_ALL, outputSchema = mapOf("appeal" to "string")),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validateForCommit(scenario) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.contains("'statement'"))
    }

    /**
     * Pins the phase-type-derived branch parent label: the canonical-field
     * descent visits `thenPhases` / `elsePhases` for **every** phase type, not
     * just `conditional`, so a non-conditional carrier must render its own
     * `serialName()` in the label — never a hardcoded `(conditional)`.
     */
    @Test
    fun branchLabelCarriesTheParentPhaseTypeNotConditional() {
        val scenario = makeValidatorScenario(
            agents = 2,
            rounds = 1,
            phases = listOf(
                Phase(
                    type = PhaseType.SPEAK_ALL,
                    outputSchema = mapOf("statement" to "string"),
                    thenPhases = listOf(
                        Phase(
                            type = PhaseType.SPEAK_ALL,
                            outputSchema = mapOf("appeal" to "string"),
                        ),
                    ),
                ),
            ),
        )
        val caught = assertFailsWith<SimulationException> { validator.validateForCommit(scenario) }
        val error = caught.error
        assertTrue(error is SimulationError.ScenarioValidationFailed)
        assertTrue(error.message.startsWith("Phase 1 (speak_all) then[1] "))
    }
}
