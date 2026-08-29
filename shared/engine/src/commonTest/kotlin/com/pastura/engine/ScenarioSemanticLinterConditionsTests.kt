package com.pastura.engine

import com.pastura.models.AnyCodableValue
import com.pastura.models.AssignTarget
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import com.pastura.models.ScenarioLintMessage
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Condition-expression rule tests (R13/R14/R15, R16 no-op) for
 * [ScenarioSemanticLinter], mirroring
 * `Pastura/PasturaTests/Engine/ScenarioSemanticLinterTests+Conditions.swift`
 * 1:1 (13 tests — the original 11 plus the two gap pins below), plus
 * [conditionMessagesMapEachRuleIdToItsLintMessageCase], which mirrors
 * `ScenarioSemanticLinterTests+ConditionMessages.swift`'s
 * `conditionMessagesMapEachRuleIDToItsLintMessageCase` in its own split file
 * — the same reason [ScenarioSemanticLinterPlaceholdersTests]'s message-mapping
 * test lives apart from `+Placeholders.swift`. Every function name below
 * matches its Swift twin exactly — see that file if a name here looks odd.
 *
 * No test here is a deliberate exception to the mirror any more: before this
 * PR (#1587) the message-mapping test had no Swift twin, on the same grounds
 * [ScenarioSemanticLinterPlaceholdersTests]'s
 * `placeholderMessagesMapEachRuleIdToItsLintMessageCase` recorded before
 * #1586 closed it — no mirrored test asserted `finding.message`, so all three
 * `conditionMessage` arms, the fallthrough `else` especially, would ship
 * green however they were transcribed (Row 6 below is the measurement that
 * says so) — but the Swift twin was added in the same PR as this class's own
 * pin, so the exception no longer applies.
 *
 * Findings are read through the group entry point
 * [ScenarioSemanticLinter.conditionFindings] rather than `lint`, exactly as
 * the Swift twin reads `conditionFindings(in:)`, so the condition rules stay
 * isolated from the ordering / config / placeholder groups.
 *
 * **No test here pins the relative order of two findings within one
 * condition.** `conditionFindings` sorts operands with Kotlin's
 * `String.compareTo` while Swift sorts with `<`; the two agree on ASCII /
 * Latin-1 only (see that function's why-comment in
 * `ScenarioSemanticLinter.kt`), so only the finding *set* is a parity
 * contract. Every fixture below asserts `isEmpty()` or a size-1 list.
 *
 * ## Condition-4 perturbation check
 *
 * ADR-023 §12 condition 4 (perturbation sensitivity). Measured 2026-08-28 with
 * the whole `:shared:engine:jvmTest` suite (952 tests, this class's 12) green
 * before the first mutation and after the last revert — all eight rows below
 * were run in that session, one mutation at a time, applied to
 * `ScenarioSemanticLinter.kt`'s Conditions section alone and reverted exactly
 * before the next. Rows 1 and 3 were then re-measured the same day, same
 * methodology, after [eventFavorsCompanionIsKnownInCondition] and
 * [barePersonaNameOutsideEqualityFiresR15NotR14] closed them (954 tests, this
 * class's 14); the table shows the post-close result.
 *
 * | # | Mutation of `ScenarioSemanticLinter.kt` | Reddened |
 * |---|---|---|
 * | 1 | `knownConditionIdentifiers`: dropped `known.add(EventInjectHandler.favoredVariableName(name))` | [eventFavorsCompanionIsKnownInCondition] |
 * | 2 | `classifyOperand`: `evaluator.isNumericOperand(text)` -> `text.toDoubleOrNull() != null` | **nothing** — uncaught gap, see below |
 * | 3 | `classifyOperand`: dropped the `isEquality &&` guard on the R14 arm | [barePersonaNameOutsideEqualityFiresR15NotR14] |
 * | 4 | `classifyOperand`: swapped the R13 and R14 `ruleId` + severity pairs | [singleQuotedLiteralFiresR13], [barePersonaNameFiresR14], [personaTokenDedupsToSingleR14], [conditionMessagesMapEachRuleIdToItsLintMessageCase] |
 * | 5 | `classifyOperand`: dropped the `head == "scores"` half of the dotted-access check, so `scores.A0` fires R15 | [knownIdentifiersProduceNoFindings] |
 * | 6 | `conditionMessage`: fallthrough `else` arm swapped to `SingleQuotedLiteralInCondition` | [conditionMessagesMapEachRuleIdToItsLintMessageCase] |
 * | 7 | `knownConditionIdentifiers`: dropped `known.addAll(scenario.extraData.keys)` | [knownIdentifiersProduceNoFindings] |
 * | 8 | `knownConditionIdentifiers`: dropped `known.add("wolf_name")` | [knownIdentifiersProduceNoFindings], [wordWolfConditionsProduceZeroFindings] |
 *
 * Row 6 is what justifies
 * [conditionMessagesMapEachRuleIdToItsLintMessageCase]: it reddens that test
 * and nothing else, so without the pin a mis-transcribed fallthrough arm would
 * ship green — the same gap row 6 of [ScenarioSemanticLinterConfigTests]'s
 * KDoc recorded for the config group.
 *
 * **Rows 1 and 3 were closed in this same PR (#1587), Swift-first then the
 * Kotlin twin** — the precedent the placeholder group set for its own
 * `__favors`-companion gap (#1584, D2c, folded into #1586 rather than filed
 * separately). [eventFavorsCompanionIsKnownInCondition] and
 * [barePersonaNameOutsideEqualityFiresR15NotR14] pin them; both mutations were
 * re-applied and re-verified to redden exactly the new test and nothing else,
 * then reverted (`git diff --stat` empty afterward).
 *
 * **Row 2 stays an uncaught, documented divergence — not pinned.** Every
 * numeric operand in these fixtures (`3`, `5`, `999`) parses identically
 * under both predicates. Closing it would mean asserting the divergence the
 * evaluator predicate exists for (`nan` / `inf` / hex-floats) — a **stated
 * non-parity** between the Swift and Kotlin linters already recorded in
 * `classifyOperand`'s own comment, not a bug either side should converge on —
 * so a fixture that pinned it would pin the divergence, not close it.
 */
class ScenarioSemanticLinterConditionsTests {

    private val linter = ScenarioSemanticLinter()

    // MARK: - R13 single-quoted-literal-in-condition (error)

    @Test
    fun singleQuotedLiteralFiresR13() {
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1, phases = listOf(conditionalPhase("vote_winner == 'Alice'")),
        )
        val findings = linter.conditionFindings(scenario)
        assertEquals(1, findings.size)
        assertEquals("single-quoted-literal-in-condition", findings.first().ruleId)
        assertEquals(LintSeverity.ERROR, findings.first().severity)
        assertEquals(0, findings.first().phaseIndex)
    }

    @Test
    fun doubleQuotedLiteralPassesR13() {
        // The evaluator treats `"` as the string delimiter, so this is a legitimate
        // string comparison — must not trip R13.
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1, phases = listOf(conditionalPhase("vote_winner == \"Alice\"")),
        )
        assertTrue(linter.conditionFindings(scenario).isEmpty())
    }

    // MARK: - R14 bare-identifier-looks-like-literal (error)

    @Test
    fun barePersonaNameFiresR14() {
        // `A0` is a declared persona name (makeLinterScenario names personas A0…An).
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1, phases = listOf(conditionalPhase("vote_winner == A0")),
        )
        val findings = linter.conditionFindings(scenario)
        assertEquals(1, findings.size)
        assertEquals("bare-identifier-looks-like-literal", findings.first().ruleId)
        assertEquals(LintSeverity.ERROR, findings.first().severity)
        assertEquals(0, findings.first().phaseIndex)
    }

    @Test
    fun unknownNonPersonaEqualityFiresR15NotR14() {
        // An unknown identifier that is NOT a persona name is R15's lane even in an
        // equality comparison — R14 is the persona-name match only.
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1, phases = listOf(conditionalPhase("vote_winner == foobar")),
        )
        val findings = linter.conditionFindings(scenario)
        assertEquals(1, findings.size)
        assertEquals("unknown-condition-identifier", findings.first().ruleId)
        assertEquals(LintSeverity.WARNING, findings.first().severity)
    }

    // MARK: - R15 unknown-condition-identifier (warning)

    @Test
    fun typoDerivedVarFiresR15() {
        // `max_scores` is a typo of the derived `max_score`; `>` is non-equality so
        // R14 never applies.
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1, phases = listOf(conditionalPhase("max_scores > 5")),
        )
        val findings = linter.conditionFindings(scenario)
        assertEquals(1, findings.size)
        assertEquals("unknown-condition-identifier", findings.first().ruleId)
        assertEquals(LintSeverity.WARNING, findings.first().severity)
        assertEquals(0, findings.first().phaseIndex)
    }

    @Test
    fun scoresNonPersonaFiresR15() {
        // `scores.Nobody` — a dotted score access for a non-declared name resolves
        // absent at runtime, so it is unknown (R15), not a valid `scores.<persona>`.
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1, phases = listOf(conditionalPhase("scores.Nobody > 3")),
        )
        val findings = linter.conditionFindings(scenario)
        assertEquals(1, findings.size)
        assertEquals("unknown-condition-identifier", findings.first().ruleId)
        assertEquals(LintSeverity.WARNING, findings.first().severity)
    }

    @Test
    fun voteWinnerCountIsKnownIdentifier() {
        // `vote_winner_count` is a derived read-only variable (ADR-020 §11) and
        // must not fire R15 unknown-condition-identifier.
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1, phases = listOf(conditionalPhase("vote_winner_count >= 2")),
        )
        assertTrue(linter.conditionFindings(scenario).isEmpty())
    }

    @Test
    fun knownIdentifiersProduceNoFindings() {
        // Derived vars, extraData key (`events`), scores.<persona>, engine-injected
        // reserved names (wolf_name), and a custom `event_inject` `as:` name (storm)
        // are all resolvable → zero findings.
        val scenario = makeEventScenario(
            phases = listOf(
                Phase(type = PhaseType.EVENT_INJECT, source = "events", eventVariable = "storm"),
                conditionalPhase("current_round >= total_rounds"),
                conditionalPhase("eliminated_count > active_count"),
                conditionalPhase("max_score >= min_score"),
                conditionalPhase("vote_winner == wolf_name"),
                conditionalPhase("scores.A0 > 3"),
                conditionalPhase("events != \"\""),
                conditionalPhase("storm != \"\""),
            ),
            events = AnyCodableValue.ArrayValue(listOf("a")),
        )
        assertTrue(linter.conditionFindings(scenario).isEmpty())
    }

    // MARK: - Dedup: one token → one finding

    @Test
    fun repeatedUnknownTokenFiresOnce() {
        // `foobar` appears twice (equality + non-equality) but yields one finding.
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(conditionalPhase("foobar == vote_winner || foobar > 3")),
        )
        val findings = linter.conditionFindings(scenario)
        assertEquals(1, findings.size)
        assertEquals("unknown-condition-identifier", findings.first().ruleId)
    }

    @Test
    fun personaTokenDedupsToSingleR14() {
        // A persona name in two equality comparisons dedups to a single R14 error —
        // never both R14 and R15 on the same token.
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(conditionalPhase("A0 == vote_winner || vote_winner == A0")),
        )
        val findings = linter.conditionFindings(scenario)
        assertEquals(1, findings.size)
        assertEquals("bare-identifier-looks-like-literal", findings.first().ruleId)
    }

    // MARK: - R16 short-circuit-hidden-typo (info, no-op)

    @Test
    fun shortCircuitTypoCaughtByR15WithoutSeparateR16() {
        // R13–R15 statically resolve BOTH sides of `&&`, so a typo in a
        // runtime-short-circuitable sub-expression is already caught by R15; R16
        // emits no separate finding (documented no-op).
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(conditionalPhase("current_round > 999 && max_scores > 5")),
        )
        val findings = linter.conditionFindings(scenario)
        assertEquals(1, findings.size)
        assertEquals("unknown-condition-identifier", findings.first().ruleId)
        assertFalse(findings.any { it.ruleId == "short-circuit-hidden-typo" })
    }

    // MARK: - word_wolf sanity anchor

    @Test
    fun wordWolfConditionsProduceZeroFindings() {
        // The shipped word_wolf conditions (`current_event != ""`,
        // `vote_winner == wolf_name`) against an assign + default event_inject must
        // produce zero condition findings.
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(type = PhaseType.ASSIGN, target = AssignTarget.RANDOM_ONE),
                Phase(type = PhaseType.EVENT_INJECT),
                conditionalPhase("current_event != \"\""),
                conditionalPhase("vote_winner == wolf_name"),
            ),
        )
        assertTrue(linter.conditionFindings(scenario).isEmpty())
    }

    // MARK: - Gap pins (#1587, Swift-first — #1584/D2c precedent)

    @Test
    fun eventFavorsCompanionIsKnownInCondition() {
        // The event_inject `__favors` companion (`EventInjectHandler.favoredVariableName`)
        // must be in the condition known set, not just the placeholder one — no
        // fixture on either side named a `<event>__favors` token in a *condition*
        // before this test (ADR-023 §12 condition-4 perturbation row 1 on D2d).
        // Swift-first close of that gap, same precedent as #1584's placeholder-side
        // companion pins (D2c / #1586).
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(type = PhaseType.EVENT_INJECT),
                conditionalPhase("current_event__favors == \"A0\""),
            ),
        )
        assertTrue(linter.conditionFindings(scenario).isEmpty())
    }

    @Test
    fun barePersonaNameOutsideEqualityFiresR15NotR14() {
        // `A0` is a persona name, but `>` is non-equality — R14 applies only in
        // equality context, so this falls through to R15. Before this test no
        // fixture separated a non-equality bare persona name from an equality one
        // (ADR-023 §12 condition-4 perturbation row 3 on D2d).
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1, phases = listOf(conditionalPhase("A0 > 3")),
        )
        val findings = linter.conditionFindings(scenario)
        assertEquals(1, findings.size)
        assertEquals("unknown-condition-identifier", findings.first().ruleId)
        assertEquals(LintSeverity.WARNING, findings.first().severity)
    }

    // MARK: - Message mapping (deliberate exception to the one-test-per-rule shape)

    /**
     * Pins each condition `ruleId` to the [ScenarioLintMessage] arm
     * `conditionMessage` must render for it, token interpolation included.
     *
     * Twin of `ScenarioSemanticLinterTests+ConditionMessages.swift`'s
     * `conditionMessagesMapEachRuleIDToItsLintMessageCase` (same PR): no
     * rule test in this class asserts `finding.message`, so all three arms —
     * the fallthrough `else`, reachable only via `unknown-condition-identifier`,
     * especially — would otherwise be unverified on both sides. Same shape and rationale as
     * `ScenarioSemanticLinterPlaceholdersTests.placeholderMessagesMapEachRuleIdToItsLintMessageCase`.
     */
    @Test
    fun conditionMessagesMapEachRuleIdToItsLintMessageCase() {
        val cases: List<Triple<String, Scenario, ScenarioLintMessage>> = listOf(
            Triple(
                "single-quoted-literal-in-condition",
                makeLinterScenario(
                    agents = 2, rounds = 1,
                    phases = listOf(conditionalPhase("vote_winner == 'Alice'")),
                ),
                ScenarioLintMessage.SingleQuotedLiteralInCondition("'Alice'"),
            ),
            Triple(
                "bare-identifier-looks-like-literal",
                makeLinterScenario(
                    agents = 2, rounds = 1,
                    phases = listOf(conditionalPhase("vote_winner == A0")),
                ),
                ScenarioLintMessage.BareIdentifierLooksLikeLiteral("A0"),
            ),
            Triple(
                "unknown-condition-identifier",
                makeLinterScenario(
                    agents = 2, rounds = 1,
                    phases = listOf(conditionalPhase("max_scores > 5")),
                ),
                ScenarioLintMessage.UnknownConditionIdentifier("max_scores"),
            ),
        )
        // Pin, not proof: a new condition rule must be added to `cases` by hand.
        assertEquals(3, cases.size)
        for ((ruleId, scenario, expected) in cases) {
            val findings = linter.conditionFindings(scenario)
            assertEquals(1, findings.size, ruleId)
            assertEquals(ruleId, findings.single().ruleId, ruleId)
            assertEquals(expected.render(), findings.single().message, ruleId)
        }
    }

    // MARK: - Helpers

    // Internal factory for scenarios needing `extraData`; `makeLinterScenario`
    // takes an `extraData` parameter directly so this just names it the way the
    // Swift twin's `makeEventScenario` does.
    private fun makeEventScenario(phases: List<Phase>, events: AnyCodableValue): Scenario =
        makeLinterScenario(
            agents = 2, rounds = 1, phases = phases, extraData = mapOf("events" to events),
        )
}

// A depth-1 `conditional` phase carrying `ifExpr`, with a trivial then-branch
// (a `summarize` with a placeholder-free template so no other rule fires).
private fun conditionalPhase(ifExpr: String): Phase = Phase(
    type = PhaseType.CONDITIONAL,
    condition = ifExpr,
    thenPhases = listOf(Phase(type = PhaseType.SUMMARIZE, template = "done")),
)
