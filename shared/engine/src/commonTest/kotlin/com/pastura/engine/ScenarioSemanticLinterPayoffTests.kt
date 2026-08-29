package com.pastura.engine

import com.pastura.models.AnyCodableValue
import com.pastura.models.AssignTarget
import com.pastura.models.PairingStrategy
import com.pastura.models.PayoffRule
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import com.pastura.models.ScenarioLintMessage
import com.pastura.models.ScoreCalcLogic
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * R20a/R20b options <-> `payoff.when` token-rule tests for
 * [ScenarioSemanticLinter] (ADR-024 § Amendment 2026-07-17), mirroring
 * `Pastura/PasturaTests/Engine/ScenarioSemanticLinterTests+Payoff.swift`
 * 1:1. Every function name below matches its Swift twin exactly — see that
 * file if a name here looks odd.
 *
 * 7 mirrored 1:1 — the message-mapping test included, though its Swift twin
 * lives in `ScenarioSemanticLinterTests+ConfigMessages.swift` rather than in
 * `+Payoff.swift` with the other 6.
 *
 * [configMessagesMapEachRuleIdToItsLintMessageCase] is the deliberate
 * exception to the one-test-per-rule shape, not to the 1:1 mirror: its Swift
 * twin is `ScenarioSemanticLinterTests+ConfigMessages.swift`'s
 * `configMessagesMapEachRuleIDToItsLintMessageCase`, mirroring the pairing
 * `ScenarioSemanticLinterOrderingTests.orderingMessagesMapEachRuleIdToItsLintMessageCase`
 * already has.
 * It lives here rather than in [ScenarioSemanticLinterConfigTests] because it
 * can only cover **all seven** config ruleIds once R20a/R20b exist, and they
 * arrive with this file. It closes the gap that class's KDoc records as row 6:
 * no mirrored config test asserts `finding.message`, so a mis-transcribed
 * `configMessage` arm shipped green until this pin.
 *
 * ## Condition-4 perturbation check
 *
 * ADR-023 §12 condition 4 (perturbation sensitivity), measured at porting time
 * with the whole `:shared:engine:jvmTest` suite (922 tests, this class's 7
 * included) green before the first mutation and after the last revert. Each
 * mutation was applied to `ScenarioSemanticLinter.kt`'s R20 code alone and
 * reverted exactly before the next.
 *
 * | # | Mutation of `ScenarioSemanticLinter.kt` | Reddened |
 * |---|---|---|
 * | 1 | `payoffFinding`: swapped the two severities (R20a -> WARNING, R20b -> ERROR) | [payoffAllRowsOutsideOptionsFiresError], [absentPayoffWithValidChooseFiresError], [payoffSomeRowsDeadFiresWarning] |
 * | 2 | `payoffFinding`: negated both membership checks (`options.contains(...)` -> `!options.contains(...)`) | [payoffAllRowsOutsideOptionsFiresError], [payoffAllRowsSatisfiablePasses], [configMessagesMapEachRuleIdToItsLintMessageCase] (+ 2 in [ScenarioSemanticLinterOrderingTests]) |
 * | 3 | `payoffFinding`: `satisfiable.size < rows.size` -> `<=` | [payoffAllRowsSatisfiablePasses] (+ 2 in [ScenarioSemanticLinterOrderingTests]) |
 * | 4 | `payoffTokenFindings`: dropped the `it.logic == ScoreCalcLogic.PAIRWISE_PAYOFF` conjunct | **nothing here** — 5 in [ScenarioSemanticLinterOrderingTests], whose `prisoners_dilemma` fixtures pair a round-robin `choose` with a payoff-less `score_calc` |
 * | 5 | `configMessage`: R20a arm swapped to `PairwisePayoffDeadRow` | [configMessagesMapEachRuleIdToItsLintMessageCase] |
 *
 * Mutation 5 is the measurement that justifies
 * [configMessagesMapEachRuleIdToItsLintMessageCase]: it reddens that test and
 * nothing else, exactly as row 6 of [ScenarioSemanticLinterConfigTests]'s KDoc
 * predicted for a mis-transcribed `configMessage` arm.
 *
 * **Two candidate mutations measured insensitive and substituted**, recorded
 * rather than hidden (same convention as [ScenarioSemanticLinterConfigTests]'s
 * R9 note):
 *
 * - Dropping just the `options.contains(row.when[0])` side (keeping `[1]`)
 *   reddened **nothing**: every fixture's dead rows are symmetric
 *   (`["yes", "no"]`, `["unclear", "unclear"]` — both tokens off-menu), so the
 *   one-sided and two-sided predicates agree on all of them. Row 2's
 *   double negation is the sensitivity measurement that predicate does have.
 * - Narrowing the producer filter `it.first <= idx` to `< idx` reddened
 *   **nothing**: no fixture puts a round-robin `choose` at the *same* top-level
 *   index as its `score_calc` (which needs both inside one conditional branch),
 *   so the may-run leniency is untested here. Row 4 is the substitute; the
 *   same-index gap is the R20 twin of the Config class's R9 `<=` note.
 */
class ScenarioSemanticLinterPayoffTests {

    private val linter = ScenarioSemanticLinter()

    /**
     * A four-row payoff table over `{cooperate, betray}^2` — fully satisfiable
     * by the `["cooperate", "betray"]` option set.
     */
    private val satisfiablePayoff: List<PayoffRule> = listOf(
        PayoffRule(`when` = listOf("cooperate", "cooperate"), points = listOf(3, 3)),
        PayoffRule(`when` = listOf("cooperate", "betray"), points = listOf(0, 5)),
        PayoffRule(`when` = listOf("betray", "cooperate"), points = listOf(5, 0)),
        PayoffRule(`when` = listOf("betray", "betray"), points = listOf(1, 1)),
    )

    private fun roundRobinChoose(options: List<String> = listOf("cooperate", "betray")): Phase =
        Phase(type = PhaseType.CHOOSE, options = options, pairing = PairingStrategy.ROUND_ROBIN)

    // MARK: - R20a pairwise-payoff-no-scorable-row (error)

    @Test
    fun payoffAllRowsOutsideOptionsFiresError() {
        // Every `when` token is outside the option set -> no pairing ever scores.
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                roundRobinChoose(),
                Phase(
                    type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.PAIRWISE_PAYOFF,
                    payoff = listOf(PayoffRule(`when` = listOf("yes", "no"), points = listOf(1, 1))),
                ),
            ),
        )
        val findings = linter.lint(scenario)
        assertEquals(1, findings.size)
        assertEquals("pairwise-payoff-no-scorable-row", findings.first().ruleId)
        assertEquals(LintSeverity.ERROR, findings.first().severity)
        assertEquals(1, findings.first().phaseIndex)
    }

    @Test
    fun absentPayoffWithValidChooseFiresError() {
        // A properly-wired pairwise_payoff with no `payoff:` table -> guaranteed no-op.
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                roundRobinChoose(),
                Phase(type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.PAIRWISE_PAYOFF),
            ),
        )
        val findings = linter.lint(scenario)
        assertEquals(1, findings.size)
        assertEquals("pairwise-payoff-no-scorable-row", findings.first().ruleId)
        assertEquals(LintSeverity.ERROR, findings.first().severity)
    }

    // MARK: - R20b pairwise-payoff-dead-row (warning)

    @Test
    fun payoffSomeRowsDeadFiresWarning() {
        // One satisfiable row + one dead row (`unclear` isn't an option) -> the phase
        // still scores, so a warning, not an error.
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                roundRobinChoose(),
                Phase(
                    type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.PAIRWISE_PAYOFF,
                    payoff = listOf(
                        PayoffRule(`when` = listOf("cooperate", "cooperate"), points = listOf(3, 3)),
                        PayoffRule(`when` = listOf("unclear", "unclear"), points = listOf(0, 0)),
                    ),
                ),
            ),
        )
        val findings = linter.lint(scenario)
        assertEquals(1, findings.size)
        assertEquals("pairwise-payoff-dead-row", findings.first().ruleId)
        assertEquals(LintSeverity.WARNING, findings.first().severity)
        assertEquals(1, findings.first().phaseIndex)
    }

    // MARK: - Passes

    @Test
    fun payoffAllRowsSatisfiablePasses() {
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                roundRobinChoose(),
                Phase(
                    type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.PAIRWISE_PAYOFF,
                    payoff = satisfiablePayoff,
                ),
            ),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    // MARK: - R20 defers to R19 / R7 (no double-report)

    @Test
    fun payoffWithoutRoundRobinChooseDefersToR19() {
        // Individual (non-round-robin) choose -> R19 owns the empty-pairings case;
        // R20 must not also fire (no closed option set for the pairings).
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(type = PhaseType.CHOOSE, options = listOf("cooperate", "betray")),
                Phase(
                    type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.PAIRWISE_PAYOFF,
                    payoff = satisfiablePayoff,
                ),
            ),
        )
        val findings = linter.lint(scenario)
        assertTrue(findings.any { it.ruleId == "pairwise-payoff-needs-round-robin-choose" })
        assertFalse(findings.any { it.ruleId == "pairwise-payoff-no-scorable-row" })
        assertFalse(findings.any { it.ruleId == "pairwise-payoff-dead-row" })
    }

    @Test
    fun payoffWithOptionlessRoundRobinChooseDefersToR7() {
        // A round-robin choose with no options -> R7 owns the missing-options case;
        // R20 has no set to check against and must not fire.
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(type = PhaseType.CHOOSE, pairing = PairingStrategy.ROUND_ROBIN),
                Phase(
                    type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.PAIRWISE_PAYOFF,
                    payoff = satisfiablePayoff,
                ),
            ),
        )
        val findings = linter.lint(scenario)
        assertTrue(findings.any { it.ruleId == "choose-should-declare-options" })
        assertFalse(findings.any { it.ruleId == "pairwise-payoff-no-scorable-row" })
        assertFalse(findings.any { it.ruleId == "pairwise-payoff-dead-row" })
    }

    // MARK: - configMessage mapping pin (not a Swift mirror)

    @Test
    fun configMessagesMapEachRuleIdToItsLintMessageCase() {
        val cases: List<Triple<String, Scenario, ScenarioLintMessage>> = listOf(
            Triple(
                "choose-should-declare-options",
                makeLinterScenario(agents = 2, rounds = 1, phases = listOf(Phase(type = PhaseType.CHOOSE))),
                ScenarioLintMessage.ChooseShouldDeclareOptions,
            ),
            Triple(
                "assign-source-nonempty",
                makeLinterScenario(
                    agents = 2, rounds = 1,
                    phases = listOf(
                        Phase(type = PhaseType.ASSIGN, source = "events", target = AssignTarget.ALL),
                    ),
                    extraData = mapOf("events" to AnyCodableValue.ArrayValue(emptyList())),
                ),
                ScenarioLintMessage.AssignSourceNonempty,
            ),
            Triple(
                "summarize-pairing-placeholders",
                makeLinterScenario(
                    agents = 2, rounds = 1,
                    phases = listOf(Phase(type = PhaseType.SUMMARIZE, template = "{agent1} chose {action1}")),
                ),
                ScenarioLintMessage.SummarizePairingPlaceholders,
            ),
            Triple(
                "log-window-below-agent-count",
                makeLinterScenario(
                    agents = 3, rounds = 1,
                    phases = listOf(Phase(type = PhaseType.SPEAK_EACH)),
                    logWindow = 2,
                ),
                ScenarioLintMessage.LogWindowBelowAgentCount,
            ),
            Triple(
                "max-sentences-no-op",
                makeLinterScenario(
                    agents = 2, rounds = 1,
                    phases = listOf(
                        Phase(type = PhaseType.SUMMARIZE, template = "Round complete.", maxSentences = 3),
                    ),
                ),
                ScenarioLintMessage.MaxSentencesNoOp,
            ),
            Triple(
                "pairwise-payoff-no-scorable-row",
                makeLinterScenario(
                    agents = 2, rounds = 1,
                    phases = listOf(
                        roundRobinChoose(),
                        Phase(
                            type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.PAIRWISE_PAYOFF,
                            payoff = listOf(PayoffRule(`when` = listOf("yes", "no"), points = listOf(1, 1))),
                        ),
                    ),
                ),
                ScenarioLintMessage.PairwisePayoffNoScorableRow,
            ),
            Triple(
                "pairwise-payoff-dead-row",
                makeLinterScenario(
                    agents = 2, rounds = 1,
                    phases = listOf(
                        roundRobinChoose(),
                        Phase(
                            type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.PAIRWISE_PAYOFF,
                            payoff = listOf(
                                PayoffRule(`when` = listOf("cooperate", "cooperate"), points = listOf(3, 3)),
                                PayoffRule(`when` = listOf("unclear", "unclear"), points = listOf(0, 0)),
                            ),
                        ),
                    ),
                ),
                ScenarioLintMessage.PairwisePayoffDeadRow,
            ),
            Triple(
                "assign-all-source-shorter-than-rounds",
                makeLinterScenario(
                    agents = 2, rounds = 4,
                    phases = listOf(
                        Phase(type = PhaseType.ASSIGN, source = "events", target = AssignTarget.ALL),
                    ),
                    extraData = mapOf("events" to AnyCodableValue.ArrayValue(listOf("one", "two"))),
                ),
                ScenarioLintMessage.AssignAllSourceShorterThanRounds,
            ),
        )
        // Pin, not proof: a new config rule must be added to `cases` by hand.
        assertEquals(8, cases.size)
        for ((ruleId, scenario, expected) in cases) {
            val findings = linter.lint(scenario)
            assertEquals(1, findings.size, ruleId)
            assertEquals(ruleId, findings.single().ruleId, ruleId)
            assertEquals(expected.render(), findings.single().message, ruleId)
        }
    }
}
