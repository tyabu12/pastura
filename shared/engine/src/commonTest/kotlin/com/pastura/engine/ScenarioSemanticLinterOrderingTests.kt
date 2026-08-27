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
import kotlin.test.assertTrue

/**
 * Producer–consumer ordering-rule tests (R1a/R1b/R2/R3/R4/R5/R6/R19) for
 * [ScenarioSemanticLinter], mirroring
 * `Pastura/PasturaTests/Engine/ScenarioSemanticLinterTests+Ordering.swift`
 * 1:1. Every function name below matches its Swift twin exactly — see that
 * file if a name here looks odd.
 *
 * 27 mirrored 1:1 + 1 message-mapping test = 28.
 *
 * ## Condition-4 perturbation check
 *
 * ADR-023 §12 condition 4 (perturbation sensitivity), measured at porting time
 * against a 34-test baseline (28 here + 6 in [ScenarioSemanticLinterTests])
 * green before the first mutation and after the last revert. Each mutation was
 * applied to `ScenarioSemanticLinter.kt` alone and reverted exactly before the
 * next; no mutation reddened anything in [ScenarioSemanticLinterTests].
 *
 * | # | Mutation of `ScenarioSemanticLinter.kt` | Reddened |
 * |---|---|---|
 * | 1 | dropped the `branchPhases(phase).any(predicate)` disjunct from `producerIndices` | `voteInsideConditionalBranchSatisfiesEliminate`, `sameConditionalVoteBeforeEliminatePassesOrdering`, `roundRobinChooseInsideConditionalSatisfiesPrisonersDilemma` |
 * | 2 | swapped the severities in `eliminateFindings` (`eliminate-needs-vote` -> WARNING, `eliminate-after-vote` -> ERROR) | `eliminateWithoutAnyVoteFiresError`, `eliminateBeforeVoteFiresWarning` |
 * | 3 | dropped the `it.logic == ScoreCalcLogic.PAIRWISE_PAYOFF` disjunct from `pairingsClearingScoreCalc` | `relationshipUpdateWithPairwisePayoffBetweenChooseAndItFiresWarning` |
 * | 4 | dropped the `phase.eventVariable == null &&` guard from `isQualifyingEventInject` | `eventReactiveWithCustomAsFiresError` |
 * | 5 | swapped the `"eliminate-needs-vote"` and `"pd-needs-round-robin-choose"` arms of `orderingMessage` | `orderingMessagesMapEachRuleIdToItsLintMessageCase` |
 *
 * Mutation 5 is the measurement that justifies the 28th test's existence as a
 * deliberate exception to the 1:1-mirror rule: swapping two `orderingMessage`
 * arms reddens [orderingMessagesMapEachRuleIdToItsLintMessageCase] and nothing
 * else — the 27 mirrored tests assert `ruleId` / `severity` / `phaseIndex` but
 * never `message`, so without it a mis-transcribed arm ships green.
 */
class ScenarioSemanticLinterOrderingTests {

    private val linter = ScenarioSemanticLinter()

    // MARK: - R1a eliminate-needs-vote (error)

    @Test
    fun eliminateWithoutAnyVoteFiresError() {
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1, phases = listOf(Phase(type = PhaseType.ELIMINATE)),
        )
        val findings = linter.lint(scenario)
        assertEquals(1, findings.size)
        assertEquals("eliminate-needs-vote", findings.first().ruleId)
        assertEquals(LintSeverity.ERROR, findings.first().severity)
        assertEquals(0, findings.first().phaseIndex)
    }

    @Test
    fun eliminateAfterVotePasses() {
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(Phase(type = PhaseType.VOTE), Phase(type = PhaseType.ELIMINATE)),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    @Test
    fun voteInsideConditionalBranchSatisfiesEliminate() {
        // May-run: a vote nested in a conditional branch counts as present at the
        // conditional's index, so a following eliminate does not fire R1a.
        val conditional = Phase(
            type = PhaseType.CONDITIONAL, condition = "current_round >= 1",
            thenPhases = listOf(Phase(type = PhaseType.VOTE)),
        )
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(conditional, Phase(type = PhaseType.ELIMINATE)),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    @Test
    fun sameConditionalVoteBeforeEliminatePassesOrdering() {
        // Regression for the ordering rules' `<=` may-run leniency: a vote and its
        // eliminate consumer ordered inside ONE conditional branch both anchor to
        // the conditional's top-level index. Reverting `<=` to `<` in
        // eliminateFindings would false-fire R1b here.
        val conditional = Phase(
            type = PhaseType.CONDITIONAL, condition = "current_round >= 1",
            thenPhases = listOf(Phase(type = PhaseType.VOTE), Phase(type = PhaseType.ELIMINATE)),
        )
        val scenario = makeLinterScenario(agents = 2, rounds = 1, phases = listOf(conditional))
        assertTrue(linter.lint(scenario).isEmpty())
    }

    // MARK: - R1b eliminate-after-vote (warning)

    @Test
    fun eliminateBeforeVoteFiresWarning() {
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(Phase(type = PhaseType.ELIMINATE), Phase(type = PhaseType.VOTE)),
        )
        val findings = linter.lint(scenario)
        assertEquals(1, findings.size)
        assertEquals("eliminate-after-vote", findings.first().ruleId)
        assertEquals(LintSeverity.WARNING, findings.first().severity)
        assertEquals(0, findings.first().phaseIndex)
    }

    @Test
    fun eliminateCorrectlyOrderedAfterVoteHasNoWarning() {
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(Phase(type = PhaseType.VOTE), Phase(type = PhaseType.ELIMINATE)),
        )
        assertTrue(linter.lint(scenario).all { it.ruleId != "eliminate-after-vote" })
    }

    // MARK: - R2 pd-needs-round-robin-choose (error)

    @Test
    fun prisonersDilemmaWithoutRoundRobinChooseFiresError() {
        // An individual (non-round-robin) choose does NOT populate pairings.
        // `options` set so this fixture doesn't also trip R7
        // (choose-should-declare-options, ADR-024 D3, orthogonal to ordering).
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(type = PhaseType.CHOOSE, options = listOf("cooperate", "betray")),
                Phase(type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.PRISONERS_DILEMMA),
            ),
        )
        val findings = linter.lint(scenario)
        assertEquals(1, findings.size)
        assertEquals("pd-needs-round-robin-choose", findings.first().ruleId)
        assertEquals(LintSeverity.ERROR, findings.first().severity)
        assertEquals(1, findings.first().phaseIndex)
    }

    @Test
    fun prisonersDilemmaWithRoundRobinChoosePasses() {
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(
                    type = PhaseType.CHOOSE, options = listOf("cooperate", "betray"),
                    pairing = PairingStrategy.ROUND_ROBIN,
                ),
                Phase(type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.PRISONERS_DILEMMA),
            ),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    @Test
    fun roundRobinChooseInsideConditionalSatisfiesPrisonersDilemma() {
        val conditional = Phase(
            type = PhaseType.CONDITIONAL, condition = "current_round >= 1",
            thenPhases = listOf(
                Phase(
                    type = PhaseType.CHOOSE, options = listOf("cooperate", "betray"),
                    pairing = PairingStrategy.ROUND_ROBIN,
                ),
            ),
        )
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                conditional,
                Phase(type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.PRISONERS_DILEMMA),
            ),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    // MARK: - R19 pairwise-payoff-needs-round-robin-choose (error)

    // A four-row payoff table over {cooperate, betray}^2 — satisfiable by the
    // ["cooperate", "betray"] option set, so R20a (item 3) stays silent and
    // these fixtures isolate R19.
    private val pdPayoff: List<PayoffRule> = listOf(
        PayoffRule(`when` = listOf("cooperate", "cooperate"), points = listOf(3, 3)),
        PayoffRule(`when` = listOf("cooperate", "betray"), points = listOf(0, 5)),
        PayoffRule(`when` = listOf("betray", "cooperate"), points = listOf(5, 0)),
        PayoffRule(`when` = listOf("betray", "betray"), points = listOf(1, 1)),
    )

    @Test
    fun pairwisePayoffWithoutRoundRobinChooseFiresError() {
        // R19 mirrors R2 but keeps a distinct ruleID: an individual (non-round-robin)
        // choose does not populate pairings, so a pairwise_payoff score_calc scores
        // nothing. A `pd-`-named finding here would name the wrong mechanic.
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(type = PhaseType.CHOOSE, options = listOf("cooperate", "betray")),
                Phase(
                    type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.PAIRWISE_PAYOFF,
                    payoff = pdPayoff,
                ),
            ),
        )
        val findings = linter.lint(scenario)
        assertEquals(1, findings.size)
        assertEquals("pairwise-payoff-needs-round-robin-choose", findings.first().ruleId)
        assertEquals(LintSeverity.ERROR, findings.first().severity)
        assertEquals(1, findings.first().phaseIndex)
    }

    @Test
    fun pairwisePayoffWithRoundRobinChoosePasses() {
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(
                    type = PhaseType.CHOOSE, options = listOf("cooperate", "betray"),
                    pairing = PairingStrategy.ROUND_ROBIN,
                ),
                Phase(
                    type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.PAIRWISE_PAYOFF,
                    payoff = pdPayoff,
                ),
            ),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    // MARK: - R3 wordwolf-needs-assign-and-vote (error)

    @Test
    fun wordwolfWithoutAssignAndVoteFiresError() {
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(Phase(type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.WORDWOLF_JUDGE)),
        )
        val findings = linter.lint(scenario)
        assertEquals(1, findings.size)
        assertEquals("wordwolf-needs-assign-and-vote", findings.first().ruleId)
        assertEquals(LintSeverity.ERROR, findings.first().severity)
    }

    @Test
    fun wordwolfWithOnlyVoteStillFiresError() {
        // Missing the assign random_one producer of wolf_name -> still an error.
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(type = PhaseType.VOTE),
                Phase(type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.WORDWOLF_JUDGE),
            ),
        )
        assertTrue(linter.lint(scenario).any { it.ruleId == "wordwolf-needs-assign-and-vote" })
    }

    @Test
    fun wordwolfWithAssignRandomOneAndVotePasses() {
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(type = PhaseType.ASSIGN, target = AssignTarget.RANDOM_ONE),
                Phase(type = PhaseType.VOTE),
                Phase(type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.WORDWOLF_JUDGE),
            ),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    // MARK: - R5 event-reactive-needs-event-inject (error)

    @Test
    fun eventReactiveWithCustomAsFiresError() {
        // A custom `as:` writes `<custom>__favors`, but ScoreCalcHandler reads the
        // hardcoded `current_event__favors` -> favored action never scored.
        val scenario = makeEventScenario(
            phases = listOf(
                Phase(type = PhaseType.EVENT_INJECT, source = "events", eventVariable = "my_event"),
                Phase(type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.EVENT_REACTIVE),
            ),
            events = AnyCodableValue.ArrayOfDictionariesValue(
                listOf(mapOf("text" to "storm", "favors" to "cooperate")),
            ),
        )
        val findings = linter.lint(scenario)
        assertEquals(1, findings.size)
        assertEquals("event-reactive-needs-event-inject", findings.first().ruleId)
        assertEquals(LintSeverity.ERROR, findings.first().severity)
    }

    @Test
    fun eventReactiveWithStringListSourceFiresError() {
        // A plain list<String> source never writes the companion favored variable.
        val scenario = makeEventScenario(
            phases = listOf(
                Phase(type = PhaseType.EVENT_INJECT, source = "events"),
                Phase(type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.EVENT_REACTIVE),
            ),
            events = AnyCodableValue.ArrayValue(listOf("storm", "calm")),
        )
        assertTrue(linter.lint(scenario).any { it.ruleId == "event-reactive-needs-event-inject" })
    }

    @Test
    fun eventReactiveWithDictSourceAndDefaultAsPasses() {
        val scenario = makeEventScenario(
            phases = listOf(
                Phase(type = PhaseType.EVENT_INJECT, source = "events"),
                Phase(type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.EVENT_REACTIVE),
            ),
            events = AnyCodableValue.ArrayOfDictionariesValue(
                listOf(mapOf("text" to "storm", "favors" to "cooperate")),
            ),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    // MARK: - R6 vote-tally-needs-vote (warning)

    @Test
    fun voteTallyWithoutVoteFiresWarning() {
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(Phase(type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.VOTE_TALLY)),
        )
        val findings = linter.lint(scenario)
        assertEquals(1, findings.size)
        assertEquals("vote-tally-needs-vote", findings.first().ruleId)
        assertEquals(LintSeverity.WARNING, findings.first().severity)
    }

    @Test
    fun voteTallyWithVotePasses() {
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(type = PhaseType.VOTE),
                Phase(type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.VOTE_TALLY),
            ),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    // MARK: - R4 relationship-update-placement (warning)

    @Test
    fun relationshipUpdateVoteAgainstWithoutVoteFiresWarning() {
        // voteAgainst declared but no `vote` earlier -> the vote signal is never
        // produced, so the delta silently does nothing.
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(Phase(type = PhaseType.RELATIONSHIP_UPDATE, voteAgainst = -1)),
        )
        val findings = linter.lint(scenario)
        assertEquals(1, findings.size)
        assertEquals("relationship-update-placement", findings.first().ruleId)
        assertEquals(LintSeverity.WARNING, findings.first().severity)
        assertEquals(0, findings.first().phaseIndex)
    }

    @Test
    fun relationshipUpdateActionDeltasWithoutRoundRobinChooseFiresWarning() {
        // An individual (non-round-robin) choose does NOT populate pairings, so
        // action_deltas has nothing to read.
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(type = PhaseType.CHOOSE, options = listOf("cooperate", "betray")),
                Phase(type = PhaseType.RELATIONSHIP_UPDATE, actionDeltas = mapOf("cooperate" to 1)),
            ),
        )
        val findings = linter.lint(scenario)
        assertEquals(1, findings.size)
        assertEquals("relationship-update-placement", findings.first().ruleId)
        assertEquals(LintSeverity.WARNING, findings.first().severity)
        assertEquals(1, findings.first().phaseIndex)
    }

    @Test
    fun relationshipUpdateWithPrisonersDilemmaBetweenChooseAndItFiresWarning() {
        // PD score_calc clears pairings between the choose and the relationship_update
        // -> action_deltas reads empty pairings.
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(
                    type = PhaseType.CHOOSE, options = listOf("cooperate", "betray"),
                    pairing = PairingStrategy.ROUND_ROBIN,
                ),
                Phase(type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.PRISONERS_DILEMMA),
                Phase(
                    type = PhaseType.RELATIONSHIP_UPDATE,
                    actionDeltas = mapOf("cooperate" to 1, "betray" to -1),
                ),
            ),
        )
        val findings = linter.lint(scenario)
        assertEquals(1, findings.size)
        assertEquals("relationship-update-placement", findings.first().ruleId)
        assertEquals(2, findings.first().phaseIndex)
    }

    @Test
    fun relationshipUpdateWithPairwisePayoffBetweenChooseAndItFiresWarning() {
        // R4 regression (ADR-027): pairwise_payoff clears state.pairings exactly like
        // prisoners_dilemma, so it must join the pairings-clearing producer set. If
        // the `==` predicate omits it, R4 silently stops firing here (false negative).
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(
                    type = PhaseType.CHOOSE, options = listOf("cooperate", "betray"),
                    pairing = PairingStrategy.ROUND_ROBIN,
                ),
                Phase(
                    type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.PAIRWISE_PAYOFF,
                    payoff = pdPayoff,
                ),
                Phase(
                    type = PhaseType.RELATIONSHIP_UPDATE,
                    actionDeltas = mapOf("cooperate" to 1, "betray" to -1),
                ),
            ),
        )
        val findings = linter.lint(scenario)
        assertEquals(1, findings.size)
        assertEquals("relationship-update-placement", findings.first().ruleId)
        assertEquals(2, findings.first().phaseIndex)
    }

    @Test
    fun relationshipUpdateWithChooseAfterPrisonersDilemmaPasses() {
        // A fresh round-robin choose after the clearing PD repopulates pairings, so
        // the un-cleared choose satisfies the action rule.
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(
                    type = PhaseType.CHOOSE, options = listOf("cooperate", "betray"),
                    pairing = PairingStrategy.ROUND_ROBIN,
                ),
                Phase(type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.PRISONERS_DILEMMA),
                Phase(
                    type = PhaseType.CHOOSE, options = listOf("cooperate", "betray"),
                    pairing = PairingStrategy.ROUND_ROBIN,
                ),
                Phase(type = PhaseType.RELATIONSHIP_UPDATE, actionDeltas = mapOf("cooperate" to 1)),
            ),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    @Test
    fun relationshipUpdateWithSpeakAllBetweenVoteAndItFiresWarning() {
        // speak_all overwrites lastOutputs between the vote and the phase, dropping
        // the `.vote` field the voteAgainst rule reads.
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(type = PhaseType.VOTE),
                Phase(type = PhaseType.SPEAK_ALL),
                Phase(type = PhaseType.RELATIONSHIP_UPDATE, voteAgainst = -1),
            ),
        )
        val findings = linter.lint(scenario)
        assertEquals(1, findings.size)
        assertEquals("relationship-update-placement", findings.first().ruleId)
        assertEquals(LintSeverity.WARNING, findings.first().severity)
        assertEquals(2, findings.first().phaseIndex)
    }

    @Test
    fun relationshipUpdateWithReflectBetweenVoteAndItPasses() {
        // reflect does NOT write lastOutputs, so the vote signal survives.
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(type = PhaseType.VOTE),
                Phase(type = PhaseType.REFLECT),
                Phase(type = PhaseType.RELATIONSHIP_UPDATE, voteAgainst = -1),
            ),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    @Test
    fun relationshipUpdateCorrectlyPlacedPasses() {
        // round-robin choose -> vote -> relationship_update (both rules) -> PD score_calc:
        // both signals are readable, and the pairings-clearing PD runs after the phase.
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(
                    type = PhaseType.CHOOSE, options = listOf("cooperate", "betray"),
                    pairing = PairingStrategy.ROUND_ROBIN,
                ),
                Phase(type = PhaseType.VOTE),
                Phase(
                    type = PhaseType.RELATIONSHIP_UPDATE, voteAgainst = -1,
                    actionDeltas = mapOf("cooperate" to 1, "betray" to -1),
                ),
                Phase(type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.PRISONERS_DILEMMA),
            ),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    // MARK: - Message mapping (deliberate exception to the 1:1 mirror rule)

    /**
     * The one deliberate exception to the 1:1-mirror rule above: neither the
     * Swift suite nor the rest of this Kotlin suite ever asserts on
     * `finding.message`, so a mis-transcribed arm in `orderingMessage` would
     * stay green on both sides with nothing to catch it. This test builds a
     * minimal scenario firing each of the 8 ordering ruleIds and checks its
     * `message` against the matching [ScenarioLintMessage] case's `render()`,
     * pinning `size == 1` and the `ruleId` so a rule that fires first on one
     * of these fixtures after D2b cannot silently change what is measured.
     * The Swift suite is NOT amended in this PR — the Swift-side twin is #1575.
     *
     * Two limits, stated so nobody reads them as proofs: (1) the 8-entry list
     * is a hand-maintained pin — a ninth ordering rule must be added here by
     * hand, nothing reddens otherwise; (2) `vote-tally-needs-vote` has no
     * explicit `orderingMessage` arm on either side (Swift `default:` / Kotlin
     * `else`), so its row cannot tell "arm correct" from "fell through".
     */
    @Test
    fun orderingMessagesMapEachRuleIdToItsLintMessageCase() {
        val cases: List<Triple<String, Scenario, ScenarioLintMessage>> = listOf(
            Triple(
                "eliminate-needs-vote",
                makeLinterScenario(agents = 2, rounds = 1, phases = listOf(Phase(type = PhaseType.ELIMINATE))),
                ScenarioLintMessage.EliminateNeedsVote,
            ),
            Triple(
                "eliminate-after-vote",
                makeLinterScenario(
                    agents = 2, rounds = 1,
                    phases = listOf(Phase(type = PhaseType.ELIMINATE), Phase(type = PhaseType.VOTE)),
                ),
                ScenarioLintMessage.EliminateAfterVote,
            ),
            Triple(
                "pd-needs-round-robin-choose",
                makeLinterScenario(
                    agents = 2, rounds = 1,
                    phases = listOf(
                        Phase(type = PhaseType.CHOOSE, options = listOf("cooperate", "betray")),
                        Phase(type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.PRISONERS_DILEMMA),
                    ),
                ),
                ScenarioLintMessage.PdNeedsRoundRobinChoose,
            ),
            Triple(
                "pairwise-payoff-needs-round-robin-choose",
                makeLinterScenario(
                    agents = 2, rounds = 1,
                    phases = listOf(
                        Phase(type = PhaseType.CHOOSE, options = listOf("cooperate", "betray")),
                        Phase(
                            type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.PAIRWISE_PAYOFF,
                            payoff = pdPayoff,
                        ),
                    ),
                ),
                ScenarioLintMessage.PairwisePayoffNeedsRoundRobinChoose,
            ),
            Triple(
                "wordwolf-needs-assign-and-vote",
                makeLinterScenario(
                    agents = 2, rounds = 1,
                    phases = listOf(Phase(type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.WORDWOLF_JUDGE)),
                ),
                ScenarioLintMessage.WordwolfNeedsAssignAndVote,
            ),
            Triple(
                "event-reactive-needs-event-inject",
                makeEventScenario(
                    phases = listOf(
                        Phase(type = PhaseType.EVENT_INJECT, source = "events"),
                        Phase(type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.EVENT_REACTIVE),
                    ),
                    events = AnyCodableValue.ArrayValue(listOf("storm", "calm")),
                ),
                ScenarioLintMessage.EventReactiveNeedsEventInject,
            ),
            Triple(
                "relationship-update-placement",
                makeLinterScenario(
                    agents = 2, rounds = 1,
                    phases = listOf(Phase(type = PhaseType.RELATIONSHIP_UPDATE, voteAgainst = -1)),
                ),
                ScenarioLintMessage.RelationshipUpdatePlacement,
            ),
            Triple(
                "vote-tally-needs-vote",
                makeLinterScenario(
                    agents = 2, rounds = 1,
                    phases = listOf(Phase(type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.VOTE_TALLY)),
                ),
                ScenarioLintMessage.VoteTallyNeedsVote,
            ),
        )
        // Pin, not proof: a new ordering rule must be added to `cases` by hand.
        assertEquals(8, cases.size)
        for ((ruleId, scenario, expected) in cases) {
            val findings = linter.lint(scenario)
            assertEquals(1, findings.size, ruleId)
            assertEquals(ruleId, findings.single().ruleId, ruleId)
            assertEquals(expected.render(), findings.single().message, ruleId)
        }
    }

    // MARK: - Helper

    // Internal factory for scenarios needing `extraData` (R5); `makeLinterScenario`
    // takes an `extraData` parameter directly so this just names it the way the
    // Swift twin's `makeEventScenario` does.
    private fun makeEventScenario(phases: List<Phase>, events: AnyCodableValue): Scenario =
        makeLinterScenario(agents = 2, rounds = 1, phases = phases, extraData = mapOf("events" to events))
}
