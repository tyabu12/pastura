package com.pastura.engine

import com.pastura.models.AnyCodableValue
import com.pastura.models.AssignTarget
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import com.pastura.models.ScenarioLintMessage
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Placeholder-resolution rule tests (R10/R11/R12) for [ScenarioSemanticLinter],
 * mirroring
 * `Pastura/PasturaTests/Engine/ScenarioSemanticLinterTests+Placeholders.swift`
 * 1:1. Every function name below matches its Swift twin exactly — see that
 * file if a name here looks odd.
 *
 * 14 mirrored 1:1 + 1 message-mapping test = 15.
 *
 * [placeholderMessagesMapEachRuleIdToItsLintMessageCase] is the deliberate
 * exception to the 1:1-mirror rule, following
 * `ScenarioSemanticLinterOrderingTests.orderingMessagesMapEachRuleIdToItsLintMessageCase`
 * and `ScenarioSemanticLinterPayoffTests.configMessagesMapEachRuleIdToItsLintMessageCase`.
 * No mirrored test here asserts `finding.message`, so without it all three
 * `placeholderMessage` arms — the fallthrough `else` especially — would ship
 * green however they were transcribed.
 *
 * **No test here pins the relative order of two findings within one phase.**
 * `placeholderTokens`' dedupe container is a seed-randomised `Set` on the Swift
 * side and an insertion-ordered `LinkedHashSet` here (see that function's
 * why-comment in `ScenarioSemanticLinter.kt`), so only the finding *set* is a
 * parity contract. Multi-token fixtures below assert set semantics —
 * `isEmpty()`, or a size + `ruleId` pair on a fixture that fires exactly one
 * finding — never an index into a multi-finding list.
 *
 * ## Condition-4 perturbation check
 *
 * ADR-023 §12 condition 4 (perturbation sensitivity), measured 2026-08-28 with
 * the whole `:shared:engine:jvmTest` suite (937 tests, this class's 15
 * included) green before the first mutation and after the last revert. Each
 * mutation was applied to `ScenarioSemanticLinter.kt`'s `placeholderFindings`
 * section alone and reverted exactly before the next.
 *
 * | # | Mutation of `ScenarioSemanticLinter.kt` | Reddened |
 * |---|---|---|
 * | 1 | `placeholderFinding`: R11 index check `producers.none { it <= index }` -> `it < index` | [sameConditionalProducerBeforeConsumerPassesR11] |
 * | 2 | `placeholderFinding`: R12 branch disabled (its `phase.type == PhaseType.SUMMARIZE` guard swapped to an unreachable `CONDITIONAL`) | [perPersonaTokenInSummarizeFiresR12ExactlyOnce], [placeholderMessagesMapEachRuleIdToItsLintMessageCase] |
 * | 3 | `PLACEHOLDER_REGEX`: body widened to `\{([^}]*)\}` (the JSON-example-brace exclusion removed) | [jsonExampleBracesDoNotFire] |
 * | 4 | `globallyKnownTokens`: dropped `known.addAll(scenario.extraData.keys)` | [declaredExtraDataKeyPassesR10] |
 * | 5 | `scannedField`: swapped `template` / `prompt` | [unknownPlaceholderTypoFiresR10], [candidatesInSpeakAllFiresR10], [producerTokenBeforeItsProducerFiresR11], [perPersonaTokenInSummarizeFiresR12ExactlyOnce], [placeholderMessagesMapEachRuleIdToItsLintMessageCase] |
 * | 6 | `placeholderMessage`: fallthrough `else` arm swapped to `UnresolvablePlaceholder` | [placeholderMessagesMapEachRuleIdToItsLintMessageCase] |
 *
 * Row 6 is the measurement that justifies
 * [placeholderMessagesMapEachRuleIdToItsLintMessageCase]: it reddens that test
 * and nothing else, so without the pin a mis-transcribed fallthrough arm would
 * ship green — the gap row 6 of [ScenarioSemanticLinterConfigTests]'s KDoc
 * recorded for the config group.
 *
 * **Two candidate mutations measured insensitive and substituted or recorded**,
 * rather than dropped silently (same convention as
 * [ScenarioSemanticLinterPayoffTests]'s notes):
 *
 * - `PLACEHOLDER_REGEX`'s *first* char class `[A-Za-z_]` -> `[A-Za-z0-9_]` (the
 *   obvious leading-digit candidate) reddened **nothing**: no fixture on either
 *   side writes a digit-leading `{0token}`, so the two patterns agree on all of
 *   them. Row 3's body widening is the substitute — it measures the property
 *   that char class actually exists for (JSON-example braces must not match).
 * - `globallyKnownTokens`: dropping the `__favors` companion
 *   (`EventInjectHandler.favoredVariableName(name)`) reddened **nothing**. No
 *   fixture here references a `{<event>__favors}` token, and the Swift twin has
 *   none either, so the companion's presence in the known set is untested on
 *   both sides. Recorded as a gap rather than papered over with a Kotlin-only
 *   test, which would break the 1:1 mirror; the fix belongs on the Swift side
 *   first — tracked as #1584.
 */
class ScenarioSemanticLinterPlaceholdersTests {

    private val linter = ScenarioSemanticLinter()

    // MARK: - R10 unresolvable-placeholder (warning)

    @Test
    fun unknownPlaceholderTypoFiresR10() {
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(Phase(type = PhaseType.SPEAK_ALL, prompt = "Scores: {scorebord}")),
        )
        val findings = linter.lint(scenario)
        assertEquals(1, findings.size)
        assertEquals("unresolvable-placeholder", findings.first().ruleId)
        assertEquals(LintSeverity.WARNING, findings.first().severity)
        assertEquals(0, findings.first().phaseIndex)
    }

    @Test
    fun engineSuppliedBaseTokensPassR10() {
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(
                    type = PhaseType.SPEAK_ALL,
                    prompt = "Score {scoreboard}, log {conversation_log}, round {current_round}",
                ),
            ),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    @Test
    fun declaredExtraDataKeyPassesR10() {
        // An `extraData` key referenced in a prompt is a declared variable — known,
        // so it must not trip R10 (ADR-024 R10's resolvable set includes extraData).
        val scenario = makeEventScenario(
            phases = listOf(Phase(type = PhaseType.SPEAK_ALL, prompt = "The events are {events}")),
            events = AnyCodableValue.ArrayValue(listOf("a", "b")),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    @Test
    fun sameConditionalProducerBeforeConsumerPassesR11() {
        // Regression (gallery kasei_sanso_touban): an `event_inject` and its
        // consumer sit in the SAME conditional branch, producer first. Both anchor
        // to the conditional's top-level index, so R11's comparison must accept
        // same-index producers (`<=`, may-run leniency) or this false-positives.
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(type = PhaseType.VOTE, prompt = "Vote"),
                Phase(
                    type = PhaseType.CONDITIONAL, condition = "current_round >= 1",
                    thenPhases = listOf(Phase(type = PhaseType.SUMMARIZE, template = "done")),
                    elsePhases = listOf(
                        Phase(type = PhaseType.EVENT_INJECT),
                        Phase(type = PhaseType.SPEAK_ALL, prompt = "It got worse: {current_event}"),
                    ),
                ),
            ),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    @Test
    fun customEventVariableReferencedDownstreamPassesR10() {
        // A custom `event_inject` `as:` name is resolvable downstream — known (no
        // R10) and, placed before the consumer, ordered correctly (no R11).
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(type = PhaseType.EVENT_INJECT, eventVariable = "storm"),
                Phase(type = PhaseType.SPEAK_ALL, prompt = "A {storm} approaches"),
            ),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    // MARK: - JSON-example braces must NOT trip

    @Test
    fun jsonExampleBracesDoNotFire() {
        // Identifier-only `{token}` shape never matches a JSON-example brace whose
        // first inner char is a quote / space / dot.
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(
                    type = PhaseType.SPEAK_ALL,
                    prompt = "Reply with {\"statement\": \"...\"} or { \"vote\": \"x\" }. Shape: {...}",
                ),
            ),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    // MARK: - R11 placeholder-phase-availability (warning)

    @Test
    fun producerTokenBeforeItsProducerFiresR11() {
        // `{wolf_name}` is a known producer-gated token; referenced before the
        // `assign` that produces it, it resolves empty → R11 (not R10).
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(type = PhaseType.SPEAK_ALL, prompt = "The wolf is {wolf_name}"),
                Phase(type = PhaseType.ASSIGN, target = AssignTarget.RANDOM_ONE),
            ),
        )
        val findings = linter.lint(scenario)
        assertEquals(1, findings.size)
        assertEquals("placeholder-phase-availability", findings.first().ruleId)
        assertEquals(LintSeverity.WARNING, findings.first().severity)
        assertEquals(0, findings.first().phaseIndex)
    }

    @Test
    fun producerTokenAfterItsProducerPasses() {
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(type = PhaseType.ASSIGN, target = AssignTarget.RANDOM_ONE),
                Phase(type = PhaseType.SPEAK_ALL, prompt = "The wolf is {wolf_name}"),
            ),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    @Test
    fun whisperOwnTokenIsSelfSuppliedNoR11() {
        // A whisper's own `{my_whispers}` / `{whisper_partner}` are in its supplied
        // set (self-supplied), so R11 must not gate them on an earlier producer.
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(
                    type = PhaseType.WHISPER,
                    prompt = "Recall {my_whispers} with {whisper_partner}",
                ),
            ),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    // MARK: - candidates: vote-supplied, not a producer token

    @Test
    fun candidatesInVotePasses() {
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(Phase(type = PhaseType.VOTE, prompt = "Choose among {candidates}")),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    @Test
    fun candidatesInSpeakAllFiresR10() {
        // `candidates` is vote-supplied only and has no producer entry, so in a
        // speak_all it is unknown → R10 (classification decision, ADR-024 note).
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(Phase(type = PhaseType.SPEAK_ALL, prompt = "Pick from {candidates}")),
        )
        val findings = linter.lint(scenario)
        assertEquals(1, findings.size)
        assertEquals("unresolvable-placeholder", findings.first().ruleId)
        assertEquals(0, findings.first().phaseIndex)
    }

    // MARK: - R12 per-persona-placeholder-in-summarize (warning)

    @Test
    fun perPersonaTokenInSummarizeFiresR12ExactlyOnce() {
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(Phase(type = PhaseType.SUMMARIZE, template = "Your notes: {my_notes}")),
        )
        val findings = linter.lint(scenario)
        assertEquals(1, findings.size)
        assertEquals("per-persona-placeholder-in-summarize", findings.first().ruleId)
        assertEquals(LintSeverity.WARNING, findings.first().severity)
        assertEquals(0, findings.first().phaseIndex)
    }

    @Test
    fun perPersonaTokenInLLMPhasePassesNotR12() {
        // `{my_notes}` in an LLM phase after a `reflect` is legitimately supplied —
        // not R12 (summarize-only), not R11 (reflect runs earlier).
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(
                Phase(type = PhaseType.REFLECT, prompt = "Note your thoughts"),
                Phase(type = PhaseType.SPEAK_ALL, prompt = "Given {my_notes}, speak"),
            ),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    @Test
    fun summarizeWithKnownNonPerPersonaTokenPasses() {
        val scenario = makeLinterScenario(
            agents = 2, rounds = 1,
            phases = listOf(Phase(type = PhaseType.SUMMARIZE, template = "Scores: {scoreboard}")),
        )
        assertTrue(linter.lint(scenario).isEmpty())
    }

    // MARK: - Message mapping (no Swift twin)

    /**
     * Pins each placeholder `ruleId` to the [ScenarioLintMessage] arm
     * `placeholderMessage` must render for it, token interpolation included.
     *
     * Not a mirror of any Swift test: no mirrored test in this class asserts
     * `finding.message`, so all three arms — the fallthrough `else`, reachable
     * only via `per-persona-placeholder-in-summarize`, especially — would
     * otherwise be unverified on both sides. Same shape and rationale as
     * `ScenarioSemanticLinterPayoffTests.configMessagesMapEachRuleIdToItsLintMessageCase`.
     */
    @Test
    fun placeholderMessagesMapEachRuleIdToItsLintMessageCase() {
        val cases: List<Triple<String, Scenario, ScenarioLintMessage>> = listOf(
            Triple(
                "unresolvable-placeholder",
                makeLinterScenario(
                    agents = 2, rounds = 1,
                    phases = listOf(Phase(type = PhaseType.SPEAK_ALL, prompt = "Scores: {scorebord}")),
                ),
                ScenarioLintMessage.UnresolvablePlaceholder("scorebord"),
            ),
            Triple(
                "placeholder-phase-availability",
                makeLinterScenario(
                    agents = 2, rounds = 1,
                    phases = listOf(
                        Phase(type = PhaseType.SPEAK_ALL, prompt = "The wolf is {wolf_name}"),
                        Phase(type = PhaseType.ASSIGN, target = AssignTarget.RANDOM_ONE),
                    ),
                ),
                ScenarioLintMessage.PlaceholderPhaseAvailability("wolf_name"),
            ),
            Triple(
                "per-persona-placeholder-in-summarize",
                makeLinterScenario(
                    agents = 2, rounds = 1,
                    phases = listOf(
                        Phase(type = PhaseType.SUMMARIZE, template = "Your notes: {my_notes}"),
                    ),
                ),
                ScenarioLintMessage.PerPersonaPlaceholderInSummarize("my_notes"),
            ),
        )
        // Pin, not proof: a new placeholder rule must be added to `cases` by hand.
        assertEquals(3, cases.size)
        for ((ruleId, scenario, expected) in cases) {
            val findings = linter.lint(scenario)
            assertEquals(1, findings.size, ruleId)
            assertEquals(ruleId, findings.single().ruleId, ruleId)
            assertEquals(expected.render(), findings.single().message, ruleId)
        }
    }

    // MARK: - Helpers

    // Internal factory for scenarios needing `extraData` (R10); `makeLinterScenario`
    // takes an `extraData` parameter directly so this just names it the way the
    // Swift twin's `makeEventScenario` does.
    private fun makeEventScenario(phases: List<Phase>, events: AnyCodableValue): Scenario =
        makeLinterScenario(agents = 2, rounds = 1, phases = phases, extraData = mapOf("events" to events))
}
