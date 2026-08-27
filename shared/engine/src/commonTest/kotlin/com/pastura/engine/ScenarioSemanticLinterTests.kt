package com.pastura.engine

import com.pastura.models.Phase
import com.pastura.models.PhaseType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Core-contract tests for [ScenarioSemanticLinter] / [LintFinding] /
 * [LintSeverity] — mirrors
 * `Pastura/PasturaTests/Engine/ScenarioSemanticLinterTests.swift` 1:1 (its
 * "Core contract" and "Severity" sections; the Ordering-rule tests land with
 * D2a item 2, which implements `orderingFindings`). Every function name below
 * matches its Swift twin exactly — see that file if a name here looks odd.
 */
class ScenarioSemanticLinterTests {

    private val linter = ScenarioSemanticLinter()

    // MARK: - Core contract

    @Test
    fun minimalValidScenarioHasNoFindings() {
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1, phases = listOf(Phase(type = PhaseType.SPEAK_ALL)),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    @Test
    fun findingEqualityHoldsForIdenticalFields() {
        val lhs = LintFinding(
            ruleId = "example-rule", severity = LintSeverity.WARNING, message = "msg", phaseIndex = 2,
        )
        val rhs = LintFinding(
            ruleId = "example-rule", severity = LintSeverity.WARNING, message = "msg", phaseIndex = 2,
        )
        assertEquals(lhs, rhs)
    }

    @Test
    fun findingEqualityDistinguishesEachField() {
        val base = LintFinding(
            ruleId = "example-rule", severity = LintSeverity.WARNING, message = "msg", phaseIndex = 2,
        )
        assertNotEquals(
            base,
            LintFinding(
                ruleId = "other-rule", severity = LintSeverity.WARNING, message = "msg", phaseIndex = 2,
            ),
        )
        assertNotEquals(
            base,
            LintFinding(
                ruleId = "example-rule", severity = LintSeverity.ERROR, message = "msg", phaseIndex = 2,
            ),
        )
        assertNotEquals(
            base,
            LintFinding(
                ruleId = "example-rule", severity = LintSeverity.WARNING, message = "other", phaseIndex = 2,
            ),
        )
        assertNotEquals(
            base,
            LintFinding(
                ruleId = "example-rule", severity = LintSeverity.WARNING, message = "msg", phaseIndex = null,
            ),
        )
    }

    @Test
    fun scenarioLevelFindingUsesNilPhaseIndex() {
        val finding = LintFinding(
            ruleId = "scenario-rule", severity = LintSeverity.INFO, message = "msg", phaseIndex = null,
        )
        assertNull(finding.phaseIndex)
    }

    // MARK: - Severity

    @Test
    fun severityCasesAreDistinct() {
        assertNotEquals(LintSeverity.ERROR, LintSeverity.WARNING)
        assertNotEquals(LintSeverity.WARNING, LintSeverity.INFO)
        assertNotEquals(LintSeverity.ERROR, LintSeverity.INFO)
    }

    @Test
    fun severityOrdersErrorAboveWarningAboveInfo() {
        // Comparable is by blocking-strength: error is the most severe. Kotlin's
        // enum-declaration-order Comparable matches Swift's explicit Comparable
        // conformance here because LintSeverity is declared INFO, WARNING, ERROR.
        assertTrue(LintSeverity.INFO < LintSeverity.WARNING)
        assertTrue(LintSeverity.WARNING < LintSeverity.ERROR)
        assertTrue(LintSeverity.INFO < LintSeverity.ERROR)
    }
}
