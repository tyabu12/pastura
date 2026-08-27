package com.pastura.engine

import com.pastura.models.AnyCodableValue
import com.pastura.models.AssignTarget
import com.pastura.models.PairingStrategy
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Silently-inert configuration-rule tests (R7/R8/R9/R17/R18) for
 * [ScenarioSemanticLinter], mirroring
 * `Pastura/PasturaTests/Engine/ScenarioSemanticLinterTests+Config.swift`
 * 1:1. Every function name below matches its Swift twin exactly — see that
 * file if a name here looks odd.
 *
 * 19 tests mirrored 1:1. R20a/R20b (`pairwise-payoff-no-scorable-row` /
 * `pairwise-payoff-dead-row`) live in [ScenarioSemanticLinterPayoffTests],
 * mirroring the Swift split across `…Tests+Config.swift` / `…Tests+Payoff.swift`.
 *
 * **One deviation from the Swift original**, in
 * [maxSentencesOnLLMPhasesDoesNotFire]: the Swift loop covered 6 phase types
 * and its comment said "All 6", but `PhaseType.requiresLLM` is `true` for
 * **7** — it omitted `narrate`. This Kotlin twin loops all 7, and the Swift
 * original is corrected in the same change so the two stay a genuine mirror.
 *
 * ## Condition-4 perturbation check
 *
 * ADR-023 §12 condition 4 (perturbation sensitivity), measured at porting time
 * with the whole `:shared:engine:jvmTest` suite (915 tests, this class's 19
 * included) green before the first mutation and after the last revert. Each
 * mutation was applied to `ScenarioSemanticLinter.kt`'s Config rules alone and
 * reverted exactly before the next.
 *
 * | # | Mutation of `ScenarioSemanticLinter.kt` | Reddened |
 * |---|---|---|
 * | 1 | `chooseOptionsFindings`: `options.isEmpty()` -> `isNotEmpty()` | [chooseWithoutOptionsFiresWarning], [chooseWithEmptyOptionsListFiresWarning], [chooseWithOptionsPasses], [summarizeWithPairingPlaceholderAfterRoundRobinChoosePasses] (+ 11 in [ScenarioSemanticLinterOrderingTests], whose fixtures set `options` precisely to keep R7 silent) |
 * | 2 | `isAssignSourceEmpty`, `ALL`/`ArrayValue` arm: `isEmpty()` -> `isNotEmpty()` | [assignAllWithEmptyArrayFiresError], [assignAllWithNonEmptyArrayPasses], [assignDefaultTargetIsAllForEmptyArray] |
 * | 3 | `summarizePairingFindings`: round-robin gate `none { it <= … }` -> `any { … }` | [summarizeWithPairingPlaceholderWithoutRoundRobinChooseFiresWarning], [summarizeWithPairingPlaceholderAfterRoundRobinChoosePasses] |
 * | 4 | `logWindowFindings`: `logWindow >= agentCount` -> `logWindow > agentCount` (Swift's `<` -> `<=`) | [logWindowAtOrAboveAgentCountPasses] |
 * | 5 | `maxSentencesNoOpFindings`: dropped the `!` from `!it.type.requiresLLM` | [maxSentencesOnCodePhaseFiresWarning], [maxSentencesOnCodePhaseNestedInConditionalFiresAtConditionalIndex], [maxSentencesOnLLMPhasesDoesNotFire] |
 * | 6 | `configMessage`: fallthrough `else` arm swapped to `MaxSentencesNoOp` | **nothing** — see below |
 *
 * Row 6 was a measured **gap** at the time of this class's port, recorded
 * rather than hidden: no test in *this* class asserts `finding.message`, so any
 * mis-transcribed `configMessage` arm shipped green.
 * [ScenarioSemanticLinterOrderingTests] closes the equivalent gap with its
 * `orderingMessagesMapEachRuleIdToItsLintMessageCase` pin; the Config
 * counterpart is
 * `ScenarioSemanticLinterPayoffTests.configMessagesMapEachRuleIdToItsLintMessageCase`,
 * added with the R20a/R20b port so it could cover all seven arms at once. It
 * lives in that class, not this one, so re-running row 6's mutation today
 * reddens **it** rather than nothing.
 *
 * A mutation of R9's `<=` to `<` (the obvious off-by-one candidate) was
 * **not** recorded: every R9 fixture places its round-robin `choose` at a
 * strictly lower index than the `summarize`, so the two predicates agree on
 * all of them. Row 3's polarity flip is the sensitivity measurement that
 * predicate does have.
 */
class ScenarioSemanticLinterConfigTests {

    private val linter = ScenarioSemanticLinter()

    // MARK: - R7 choose-should-declare-options (warning)

    @Test
    fun chooseWithoutOptionsFiresWarning() {
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1, phases = listOf(Phase(type = PhaseType.CHOOSE)),
        )
        val findings = linter.lint(scenario)
        assertEquals(1, findings.size)
        assertEquals("choose-should-declare-options", findings.first().ruleId)
        assertEquals(LintSeverity.WARNING, findings.first().severity)
        assertEquals(0, findings.first().phaseIndex)
    }

    @Test
    fun chooseWithEmptyOptionsListFiresWarning() {
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(Phase(type = PhaseType.CHOOSE, options = emptyList())),
        )
        assertTrue(linter.lint(scenario).any { it.ruleId == "choose-should-declare-options" })
    }

    @Test
    fun chooseWithOptionsPasses() {
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(Phase(type = PhaseType.CHOOSE, options = listOf("cooperate", "betray"))),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    // MARK: - R8 assign-source-nonempty (error)

    @Test
    fun assignRandomOneWithEmptyArrayOfDictionariesFiresError() {
        val scenario = makeEventScenario(
            phases = listOf(
                Phase(type = PhaseType.ASSIGN, source = "events", target = AssignTarget.RANDOM_ONE),
            ),
            events = AnyCodableValue.ArrayOfDictionariesValue(emptyList()),
        )
        val findings = linter.lint(scenario)
        assertEquals(1, findings.size)
        assertEquals("assign-source-nonempty", findings.first().ruleId)
        assertEquals(LintSeverity.ERROR, findings.first().severity)
        assertEquals(0, findings.first().phaseIndex)
    }

    @Test
    fun assignRandomOneWithNonEmptyArrayOfDictionariesPasses() {
        val scenario = makeEventScenario(
            phases = listOf(
                Phase(type = PhaseType.ASSIGN, source = "events", target = AssignTarget.RANDOM_ONE),
            ),
            events = AnyCodableValue.ArrayOfDictionariesValue(
                listOf(mapOf("majority" to "a", "minority" to "b")),
            ),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    @Test
    fun assignAllWithEmptyArrayFiresError() {
        val scenario = makeEventScenario(
            phases = listOf(
                Phase(type = PhaseType.ASSIGN, source = "events", target = AssignTarget.ALL),
            ),
            events = AnyCodableValue.ArrayValue(emptyList()),
        )
        assertTrue(linter.lint(scenario).any { it.ruleId == "assign-source-nonempty" })
    }

    @Test
    fun assignAllWithNonEmptyArrayPasses() {
        val scenario = makeEventScenario(
            phases = listOf(
                Phase(type = PhaseType.ASSIGN, source = "events", target = AssignTarget.ALL),
            ),
            events = AnyCodableValue.ArrayValue(listOf("one", "two")),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    @Test
    fun assignAllWithStringSourcePasses() {
        // A single-string source is a legitimate `.all` shape (never "empty" in
        // the nothing-to-iterate sense) — must NOT trip, per ADR-024's
        // Rule-precision notes.
        val scenario = makeEventScenario(
            phases = listOf(
                Phase(type = PhaseType.ASSIGN, source = "events", target = AssignTarget.ALL),
            ),
            events = AnyCodableValue.StringValue("the one topic"),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    @Test
    fun assignDefaultTargetIsAllForEmptyArray() {
        // `target` omitted defaults to `.all` (per `Phase`'s doc comment).
        val scenario = makeEventScenario(
            phases = listOf(Phase(type = PhaseType.ASSIGN, source = "events")),
            events = AnyCodableValue.ArrayValue(emptyList()),
        )
        assertTrue(linter.lint(scenario).any { it.ruleId == "assign-source-nonempty" })
    }

    // MARK: - R9 summarize-pairing-placeholders (warning)

    @Test
    fun summarizeWithPairingPlaceholderWithoutRoundRobinChooseFiresWarning() {
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(Phase(type = PhaseType.SUMMARIZE, template = "{agent1} chose {action1}")),
        )
        val findings = linter.lint(scenario)
        assertEquals(1, findings.size)
        assertEquals("summarize-pairing-placeholders", findings.first().ruleId)
        assertEquals(LintSeverity.WARNING, findings.first().severity)
        assertEquals(0, findings.first().phaseIndex)
    }

    @Test
    fun summarizeWithPairingPlaceholderAfterRoundRobinChoosePasses() {
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(
                    type = PhaseType.CHOOSE, options = listOf("cooperate", "betray"),
                    pairing = PairingStrategy.ROUND_ROBIN,
                ),
                Phase(type = PhaseType.SUMMARIZE, template = "{agent1} chose {action1}"),
            ),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    @Test
    fun summarizeWithoutPairingPlaceholdersPasses() {
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(Phase(type = PhaseType.SUMMARIZE, template = "Round complete.")),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    // MARK: - R17 log-window-below-agent-count (warning)

    @Test
    fun logWindowBelowAgentCountWithSpeakEachFiresWarning() {
        val scenario = makeLogWindowScenario(
            agents = 3, logWindow = 2, phases = listOf(Phase(type = PhaseType.SPEAK_EACH)),
        )
        val findings = linter.lint(scenario)
        assertEquals(1, findings.size)
        assertEquals("log-window-below-agent-count", findings.first().ruleId)
        assertEquals(LintSeverity.WARNING, findings.first().severity)
        assertEquals(null, findings.first().phaseIndex)
    }

    @Test
    fun logWindowAtOrAboveAgentCountPasses() {
        val scenario = makeLogWindowScenario(
            agents = 3, logWindow = 3, phases = listOf(Phase(type = PhaseType.SPEAK_EACH)),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    @Test
    fun logWindowBelowAgentCountWithoutSpeakEachPasses() {
        val scenario = makeLogWindowScenario(
            agents = 3, logWindow = 2, phases = listOf(Phase(type = PhaseType.SPEAK_ALL)),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    // MARK: - R18 max-sentences-no-op (warning)

    @Test
    fun maxSentencesOnCodePhaseFiresWarning() {
        // `max_sentences` only reaches the prompt for `requiresLLM` phases (via
        // `PromptBuilder.buildAnswerRules`); on a code phase it is parsed +
        // serialized but never surfaced — a silent no-op.
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(type = PhaseType.SUMMARIZE, template = "Round complete.", maxSentences = 3),
            ),
        )
        val findings = linter.lint(scenario).filter { it.ruleId == "max-sentences-no-op" }
        assertEquals(1, findings.size)
        assertEquals(LintSeverity.WARNING, findings.first().severity)
        assertEquals(0, findings.first().phaseIndex)
    }

    @Test
    fun maxSentencesOnLLMPhasesDoesNotFire() {
        // All 7 `requiresLLM` phases surface the brevity cap in-prompt, so R18 must
        // never fire for them. Guards against a `primaryField == "statement"`
        // over-narrowing that would false-flag vote/choose/reflect (whose brevity
        // bullet IS still emitted).
        //
        // Deviation from the Swift twin as it stood before this port: it looped 6
        // types and omitted `narrate` while claiming "All 6" — corrected on both
        // sides, see this class's KDoc.
        val llmTypes = listOf(
            PhaseType.SPEAK_ALL, PhaseType.SPEAK_EACH, PhaseType.VOTE, PhaseType.CHOOSE,
            PhaseType.REFLECT, PhaseType.WHISPER, PhaseType.NARRATE,
        )
        for (llmType in llmTypes) {
            val scenario = makeLinterScenario(
                agents = 2, rounds = 1,
                phases = listOf(Phase(type = llmType, maxSentences = 2)),
            )
            assertTrue(
                linter.lint(scenario).none { it.ruleId == "max-sentences-no-op" },
                llmType.toString(),
            )
        }
    }

    @Test
    fun maxSentencesNilOnCodePhaseDoesNotFire() {
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(Phase(type = PhaseType.SUMMARIZE, template = "Round complete.")),
        )
        assertTrue(linter.lint(scenario).none { it.ruleId == "max-sentences-no-op" })
    }

    @Test
    fun maxSentencesOnCodePhaseNestedInConditionalFiresAtConditionalIndex() {
        // `phaseRefs` anchors a branch sub-phase to its enclosing conditional's
        // top-level index (matches R7/R9 nesting semantics).
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(type = PhaseType.SPEAK_ALL, prompt = "Go"),
                Phase(
                    type = PhaseType.CONDITIONAL, condition = "current_round >= 1",
                    thenPhases = listOf(
                        Phase(type = PhaseType.SUMMARIZE, template = "Done.", maxSentences = 4),
                    ),
                ),
            ),
        )
        val findings = linter.lint(scenario).filter { it.ruleId == "max-sentences-no-op" }
        assertEquals(1, findings.size)
        assertEquals(1, findings.first().phaseIndex)
    }

    // MARK: - Helpers

    // Internal factory for scenarios needing `extraData` (R8); `makeLinterScenario`
    // takes an `extraData` parameter directly so this just names it the way the
    // Swift twin's `makeEventScenario` does.
    private fun makeEventScenario(phases: List<Phase>, events: AnyCodableValue): Scenario =
        makeLinterScenario(agents = 2, rounds = 1, phases = phases, extraData = mapOf("events" to events))

    // Internal factory for scenarios needing `logWindow` (R17); the Swift twin's
    // `makeLogWindowScenario`, folded onto `makeLinterScenario`'s named parameter.
    private fun makeLogWindowScenario(agents: Int, logWindow: Int, phases: List<Phase>): Scenario =
        makeLinterScenario(agents = agents, rounds = 1, phases = phases, logWindow = logWindow)
}
