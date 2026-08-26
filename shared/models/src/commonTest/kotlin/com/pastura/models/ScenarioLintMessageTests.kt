package com.pastura.models

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Locks [ScenarioLintMessage.render] to byte-identical strings against the
 * Swift original (`Pastura/Pastura/Models/ScenarioLintMessage.swift`), the
 * single source of truth for both the case set and every expected literal below
 * — this file never sources an expected string from `ScenarioLintMessage.kt`
 * itself (the file under test), which would blind it to a transcription error.
 *
 * Four parts, per issue #1562 / ADR-023 §12, mirroring
 * [ScenarioValidationMessageTests] — the precedent for this shape:
 *
 * (a) [caseSetMatchesSwiftEnumBidirectionally] — the 21 hand-transcribed Swift
 *     case names vs. the Kotlin subtype names, both directions.
 * (b) [rosterAndSwiftTranscriptionAgreeOn21Cases] — a count pin plus an
 *     else-free `when` roster ([swiftCaseNameOf]).
 * (c) [rendersAllTwentyOneCasesWithTokenInterpolationIntact] and
 *     [ruleIDsMatchRosterOrderAndPrefixEveryRendering] — every one of the 21
 *     cases rendered and asserted by full-string equality, seeded from the
 *     Swift `String(localized:)` base literals; plus the `ruleIDs` order pin.
 * (d) this KDoc's perturbation-record table, below.
 *
 * ## Why the test tokens carry a quote and a `%`
 *
 * Swift renders the six token-bearing cases through
 * `String(format: String(localized: "…%@…"), token)`, which interpolates the
 * token **verbatim** — no quoting, no escaping, and no second format pass. The
 * tokens below therefore contain both a quote character and a `%`, exactly as
 * `ScenarioLintMessageTests.swift` does: a Kotlin `render()` that tried to be
 * clever about either would redden here. They are also mutually distinguishable
 * across cases, so a roster entry pasted onto the wrong case cannot pass.
 *
 * ## En-only pin is Stage-5-scoped
 *
 * [ScenarioLintMessage.render] is a single common-code function today, so
 * pinning its English output here is sound. The day `render()` becomes an
 * `expect`/`actual` leaf (or delegates to the Swift `localized`), these
 * single-locale full-string pins go stale for every target whose `actual`
 * localizes — see `render()`'s own KDoc, "The Stage-5 debt this creates".
 *
 * ## §12 condition-4 perturbation record
 *
 * Baseline before the first mutation: **4 tests, 0 failures** (this class, under
 * `:shared:models:jvmTest`), green. Each mutation's anchor text was confirmed to
 * match **exactly once** in `ScenarioLintMessage.kt` before applying — a
 * replacement that silently no-ops leaves the original behaviour and reads as
 * verified. The unmutated baseline was reconfirmed green after the last revert;
 * that reconfirmation is the evidence the mutations were reverted, and it is the
 * only evidence there is (this file and `ScenarioLintMessage.kt` are both *added*
 * by the PR, so a `git diff` against `main` cannot distinguish "reverted" from
 * "never applied"). Counts are measured, not derived. Measured 2026-08-26, #1562.
 *
 * | # | Mutation applied to `ScenarioLintMessage.kt` | Test that reddened | Other tests reddened |
 * |---|---|---|---|
 * | 1 | swapped the render arms of `EliminateNeedsVote` and `EliminateAfterVote` | [rendersAllTwentyOneCasesWithTokenInterpolationIntact] (eliminateNeedsVote entry) and [ruleIDsMatchRosterOrderAndPrefixEveryRendering] | 0 |
 * | 2 | dropped the token interpolation from `UnknownConditionIdentifier` (rendered the literal word `token` instead) | [rendersAllTwentyOneCasesWithTokenInterpolationIntact] (unknownConditionIdentifier entry) | 0 |
 * | 3 | reordered `ruleIDs` — swapped `"choose-should-declare-options"` and `"assign-source-nonempty"` | [ruleIDsMatchRosterOrderAndPrefixEveryRendering] | 0 |
 *
 * Mutation 1 reddens two tests because the rule-ID prefix is part of every
 * literal, so swapping two arms breaks the prefix contract as well as the
 * literals; that is a property of the design, not a duplicated assertion.
 * Mutation 3 reddens **only** the order/prefix test — the roster and the render
 * pins say nothing about `ruleIDs` order, which is precisely why that test
 * exists. No mutation left the suite green.
 */
class ScenarioLintMessageTests {

    /**
     * Hand-transcribed from `Pastura/Pastura/Models/ScenarioLintMessage.swift`,
     * in file (declaration) order, grouped as the Swift `// MARK`s group them.
     * The Kotlin naming rule is "Swift case name with the first character
     * uppercased, nothing else rewritten" (`ScenarioLintMessage.kt`'s own
     * "Naming" KDoc section), so this list needs no translation table beyond
     * that capitalisation.
     */
    private val swiftCaseNames: List<String> = listOf(
        // Ordering
        "eliminateNeedsVote",
        "eliminateAfterVote",
        "pdNeedsRoundRobinChoose",
        "pairwisePayoffNeedsRoundRobinChoose",
        "wordwolfNeedsAssignAndVote",
        "eventReactiveNeedsEventInject",
        "relationshipUpdatePlacement",
        "voteTallyNeedsVote",
        // Config
        "chooseShouldDeclareOptions",
        "assignSourceNonempty",
        "summarizePairingPlaceholders",
        "maxSentencesNoOp",
        "pairwisePayoffNoScorableRow",
        "pairwisePayoffDeadRow",
        "logWindowBelowAgentCount",
        // Placeholders
        "unresolvablePlaceholder",
        "placeholderPhaseAvailability",
        "perPersonaPlaceholderInSummarize",
        // Conditions
        "singleQuotedLiteralInCondition",
        "bareIdentifierLooksLikeLiteral",
        "unknownConditionIdentifier",
    )

    // ── (a) Case-set completeness ───────────────────────────────────────────

    @Test
    fun caseSetMatchesSwiftEnumBidirectionally() {
        assertEquals(21, swiftCaseNames.size, "swiftCaseNames transcription itself must list 21")
        val expectedKotlinNames = swiftCaseNames.map { it.replaceFirstChar(Char::uppercaseChar) }.toSet()
        val actualKotlinNames = roster().map { it::class.simpleName }.toSet()
        val missingInKotlin = expectedKotlinNames - actualKotlinNames
        val extraInKotlin = actualKotlinNames - expectedKotlinNames
        assertTrue(
            missingInKotlin.isEmpty() && extraInKotlin.isEmpty(),
            "Case-set mismatch. In Swift but not Kotlin: $missingInKotlin. " +
                "In Kotlin but not Swift: $extraInKotlin.",
        )
    }

    // ── (b) Count pin + else-free `when` roster ─────────────────────────────

    /**
     * This is a **pin, not a proof.** `KClass.sealedSubclasses` is JVM-only and
     * ADR-023 Decision 5 requires the `macosArm64` rung, so commonTest cannot
     * enumerate a sealed hierarchy reflectively — see
     * `.claude/rules/kmp-interop.md` Pattern 4. The count pin below, plus the
     * else-free `when` in [swiftCaseNameOf] (which fails to *compile* if a
     * subtype is added without a matching arm), is the strongest available
     * substitute for real reflective completeness.
     *
     * **The residual hole, stated so the name cannot be read as covering it.**
     * [roster] is derived from the hand-written [rosterWithExpectedRenderings],
     * so nothing ties `21` to the number of sealed subtypes. Add a 22nd subtype
     * *and* its [swiftCaseNameOf] arm (which the compiler forces) but forget the
     * roster entry and the [swiftCaseNames] entry, and the case-set and roster
     * tests still pass. (Unlike the validation-message precedent, a 22nd
     * `ruleIDs` entry would then redden
     * [ruleIDsMatchRosterOrderAndPrefixEveryRendering] on the size check — but
     * only if the author remembered `ruleIDs`, so that is a partial backstop,
     * not a guard.) The compile-time `when` is the only real hierarchy guard.
     * The `21`s here and in `ScenarioLintMessage.ruleIDs` are hand-maintained in
     * lockstep — treat them as one edit.
     */
    @Test
    fun rosterAndSwiftTranscriptionAgreeOn21Cases() {
        val entries = roster()
        assertEquals(21, entries.size, "Roster size pin — see kmp-interop.md Pattern 4")
        val caseNames = entries.map(::swiftCaseNameOf)
        assertEquals(
            caseNames.size,
            caseNames.toSet().size,
            "Roster has a duplicate subtype: $caseNames",
        )
        assertEquals(swiftCaseNames.toSet(), caseNames.toSet())
    }

    /**
     * Deliberately has **no `else` branch** — a Kotlin subtype added to
     * [ScenarioLintMessage] without an arm here fails the build, which is the
     * compile-time half of the "pin, not proof" substitute described on
     * [rosterAndSwiftTranscriptionAgreeOn21Cases].
     */
    private fun swiftCaseNameOf(msg: ScenarioLintMessage): String = when (msg) {
        is ScenarioLintMessage.EliminateNeedsVote -> "eliminateNeedsVote"
        is ScenarioLintMessage.EliminateAfterVote -> "eliminateAfterVote"
        is ScenarioLintMessage.PdNeedsRoundRobinChoose -> "pdNeedsRoundRobinChoose"
        is ScenarioLintMessage.PairwisePayoffNeedsRoundRobinChoose -> "pairwisePayoffNeedsRoundRobinChoose"
        is ScenarioLintMessage.WordwolfNeedsAssignAndVote -> "wordwolfNeedsAssignAndVote"
        is ScenarioLintMessage.EventReactiveNeedsEventInject -> "eventReactiveNeedsEventInject"
        is ScenarioLintMessage.RelationshipUpdatePlacement -> "relationshipUpdatePlacement"
        is ScenarioLintMessage.VoteTallyNeedsVote -> "voteTallyNeedsVote"
        is ScenarioLintMessage.ChooseShouldDeclareOptions -> "chooseShouldDeclareOptions"
        is ScenarioLintMessage.AssignSourceNonempty -> "assignSourceNonempty"
        is ScenarioLintMessage.SummarizePairingPlaceholders -> "summarizePairingPlaceholders"
        is ScenarioLintMessage.MaxSentencesNoOp -> "maxSentencesNoOp"
        is ScenarioLintMessage.PairwisePayoffNoScorableRow -> "pairwisePayoffNoScorableRow"
        is ScenarioLintMessage.PairwisePayoffDeadRow -> "pairwisePayoffDeadRow"
        is ScenarioLintMessage.LogWindowBelowAgentCount -> "logWindowBelowAgentCount"
        is ScenarioLintMessage.UnresolvablePlaceholder -> "unresolvablePlaceholder"
        is ScenarioLintMessage.PlaceholderPhaseAvailability -> "placeholderPhaseAvailability"
        is ScenarioLintMessage.PerPersonaPlaceholderInSummarize -> "perPersonaPlaceholderInSummarize"
        is ScenarioLintMessage.SingleQuotedLiteralInCondition -> "singleQuotedLiteralInCondition"
        is ScenarioLintMessage.BareIdentifierLooksLikeLiteral -> "bareIdentifierLooksLikeLiteral"
        is ScenarioLintMessage.UnknownConditionIdentifier -> "unknownConditionIdentifier"
    }

    // ── (c) Rendering assertions ────────────────────────────────────────────

    @Test
    fun rendersAllTwentyOneCasesWithTokenInterpolationIntact() {
        rosterWithExpectedRenderings().forEach { (msg, expected) ->
            assertEquals(expected, msg.render(), "Render mismatch for ${swiftCaseNameOf(msg)}")
        }
    }

    /**
     * `ruleIDs` stands in for `CaseIterable` on the Swift side, so its **order**
     * is load-bearing in a way the render pins cannot see: they assert literals,
     * not the list. This asserts both halves of the contract Swift's
     * `everyMessageStartsWithItsOwnRuleID` asserts — 21 IDs, in the declaration
     * order the roster walks, each one prefixing its own case's rendering.
     */
    @Test
    fun ruleIDsMatchRosterOrderAndPrefixEveryRendering() {
        val ruleIDs = ScenarioLintMessage.ruleIDs
        assertEquals(21, ruleIDs.size, "ruleIDs must carry one entry per case")
        assertEquals(ruleIDs.size, ruleIDs.toSet().size, "ruleIDs has a duplicate: $ruleIDs")
        assertEquals(expectedRuleIDsInSwiftOrder, ruleIDs, "ruleIDs order drifted from Swift")
        val messages = roster()
        assertEquals(ruleIDs.size, messages.size)
        ruleIDs.zip(messages).forEach { (ruleID, msg) ->
            assertTrue(
                msg.render().startsWith("$ruleID: "),
                "Rendering for ${swiftCaseNameOf(msg)} does not start with \"$ruleID: \" — " +
                    "got: ${msg.render()}",
            )
        }
    }

    /**
     * Hand-transcribed from `ScenarioLintMessage.swift`'s `ruleIDs` literal, in
     * declaration order — never copied from `ScenarioLintMessage.kt`.
     */
    private val expectedRuleIDsInSwiftOrder: List<String> = listOf(
        "eliminate-needs-vote",
        "eliminate-after-vote",
        "pd-needs-round-robin-choose",
        "pairwise-payoff-needs-round-robin-choose",
        "wordwolf-needs-assign-and-vote",
        "event-reactive-needs-event-inject",
        "relationship-update-placement",
        "vote-tally-needs-vote",
        "choose-should-declare-options",
        "assign-source-nonempty",
        "summarize-pairing-placeholders",
        "max-sentences-no-op",
        "pairwise-payoff-no-scorable-row",
        "pairwise-payoff-dead-row",
        "log-window-below-agent-count",
        "unresolvable-placeholder",
        "placeholder-phase-availability",
        "per-persona-placeholder-in-summarize",
        "single-quoted-literal-in-condition",
        "bare-identifier-looks-like-literal",
        "unknown-condition-identifier",
    )

    private fun roster(): List<ScenarioLintMessage> =
        rosterWithExpectedRenderings().map { it.first }

    /**
     * Every one of the 21 cases, in Swift declaration order, paired with its
     * expected rendered string transcribed from `ScenarioLintMessage.swift`'s
     * `String(localized:)` base literals with `%@` replaced by the token —
     * never copied from `ScenarioLintMessage.kt`.
     *
     * The six token-bearing cases are constructed **positionally**: each carries
     * exactly one `String`, so there is no argument-order hazard of the kind the
     * validation-message suite guards against, but a positional call still pins
     * that the parameter exists and is the first one.
     */
    private fun rosterWithExpectedRenderings(): List<Pair<ScenarioLintMessage, String>> = listOf(
        // ── Ordering ────────────────────────────────────────────────────────
        ScenarioLintMessage.EliminateNeedsVote to
            "eliminate-needs-vote: an 'eliminate' phase does nothing without a 'vote' phase " +
            "in the same round — add a 'vote' phase before it.",
        ScenarioLintMessage.EliminateAfterVote to
            "eliminate-after-vote: this 'eliminate' runs before every 'vote' phase, so it " +
            "acts on the previous round's stale tally — move it after the 'vote' phase.",
        ScenarioLintMessage.PdNeedsRoundRobinChoose to
            "pd-needs-round-robin-choose: 'prisoners_dilemma' scoring needs a round-robin " +
            "'choose' phase earlier in the round to populate pairings, or scores never " +
            "change — add one before this 'score_calc'.",
        ScenarioLintMessage.PairwisePayoffNeedsRoundRobinChoose to
            "pairwise-payoff-needs-round-robin-choose: 'pairwise_payoff' scoring needs a " +
            "round-robin 'choose' phase earlier in the round to populate pairings, or " +
            "scores never change — add one before this 'score_calc'.",
        ScenarioLintMessage.WordwolfNeedsAssignAndVote to
            "wordwolf-needs-assign-and-vote: 'wordwolf_judge' scoring needs both an 'assign' " +
            "phase with target 'random_one' and a 'vote' phase earlier in the round, or it " +
            "judges nothing — add the missing phase(s) before this 'score_calc'.",
        ScenarioLintMessage.EventReactiveNeedsEventInject to
            "event-reactive-needs-event-inject: 'event_reactive' scoring needs an earlier " +
            "'event_inject' phase with a dictionary event source and the default " +
            "'as: current_event', or the favored action is never scored — fix the " +
            "'event_inject' before this 'score_calc'.",
        ScenarioLintMessage.RelationshipUpdatePlacement to
            "relationship-update-placement: this 'relationship_update' cannot see its " +
            "vote/choose signals — place it after the producing 'vote'/'choose' phase and " +
            "before any 'prisoners_dilemma' 'score_calc', with no 'speak'/'choose' phase " +
            "between the vote and it.",
        ScenarioLintMessage.VoteTallyNeedsVote to
            "vote-tally-needs-vote: 'vote_tally' scoring has no 'vote' phase earlier in the " +
            "round, so it scores nothing or re-adds a stale tally — add a 'vote' phase " +
            "before this 'score_calc'.",
        // ── Config ──────────────────────────────────────────────────────────
        ScenarioLintMessage.ChooseShouldDeclareOptions to
            "choose-should-declare-options: this 'choose' phase has no 'options' list, so " +
            "the agent's action is unconstrained free text — add an 'options' list to steer " +
            "the choice.",
        ScenarioLintMessage.AssignSourceNonempty to
            "assign-source-nonempty: this 'assign' phase's source resolves to an empty list, " +
            "so nothing is assigned (or every agent gets an empty value) — add at least one " +
            "entry to the referenced source data.",
        ScenarioLintMessage.SummarizePairingPlaceholders to
            "summarize-pairing-placeholders: this 'summarize' template references " +
            "{agent1}-family placeholders, but no round-robin 'choose' phase runs earlier " +
            "in the round, so the placeholders leak literally into the summary — add a " +
            "round-robin 'choose' phase before this 'summarize', or remove the pairing " +
            "placeholders.",
        ScenarioLintMessage.MaxSentencesNoOp to
            "max-sentences-no-op: this phase emits no LLM statement, so its 'max_sentences' " +
            "cap never reaches a prompt and has no effect — remove it, or move it to a " +
            "phase that emits a statement (speak_all / speak_each / whisper).",
        ScenarioLintMessage.PairwisePayoffNoScorableRow to
            "pairwise-payoff-no-scorable-row: no 'payoff' row's 'when' tokens match the " +
            "round-robin 'choose' options, so no pairing is ever scored — add a 'payoff' " +
            "table whose 'when' rows use the 'choose' option tokens.",
        ScenarioLintMessage.PairwisePayoffDeadRow to
            "pairwise-payoff-dead-row: one or more 'payoff' rows use 'when' tokens that " +
            "aren't in the round-robin 'choose' options, so those rows never fire — fix the " +
            "tokens to match the 'choose' options, or remove the unused rows.",
        ScenarioLintMessage.LogWindowBelowAgentCount to
            "log-window-below-agent-count: 'log_window' is smaller than the agent count " +
            "while a 'speak_each' phase is present, so same-round earlier speakers vanish " +
            "from the addressee pool — raise 'log_window' to at least the agent count.",
        // ── Placeholders (token-bearing) ────────────────────────────────────
        ScenarioLintMessage.UnresolvablePlaceholder("typo'token%1") to
            "unresolvable-placeholder: the placeholder '{typo'token%1}' is supplied by no " +
            "phase, so it leaks into the LLM prompt verbatim — check for a typo or remove it.",
        ScenarioLintMessage.PlaceholderPhaseAvailability("late'token%2") to
            "placeholder-phase-availability: the placeholder '{late'token%2}' is only " +
            "populated by a producing phase, but none runs earlier in the phase list, so it " +
            "resolves to an empty value — move the producing phase before this one.",
        ScenarioLintMessage.PerPersonaPlaceholderInSummarize("my\"note's%3") to
            "per-persona-placeholder-in-summarize: the per-persona placeholder " +
            "'{my\"note's%3}' is never populated in a 'summarize' phase (summaries aren't " +
            "per-agent), so it leaks literally — remove it or move it to an LLM phase.",
        // ── Conditions (token-bearing) ──────────────────────────────────────
        ScenarioLintMessage.SingleQuotedLiteralInCondition("'Alice's%4'") to
            "single-quoted-literal-in-condition: the operand 'Alice's%4' is single-quoted, " +
            "but the condition evaluator treats only double quotes as string literals — it " +
            "is read as an undefined identifier and the comparison is always false. Use " +
            "double quotes instead.",
        ScenarioLintMessage.BareIdentifierLooksLikeLiteral("Bob's%5") to
            "bare-identifier-looks-like-literal: the operand 'Bob's%5' matches a persona " +
            "name but is unquoted, so the condition evaluator reads it as an undefined " +
            "identifier and the comparison is always false — wrap it in double quotes to " +
            "compare against the name.",
        ScenarioLintMessage.UnknownConditionIdentifier("weird\"na'me%6") to
            "unknown-condition-identifier: 'weird\"na'me%6' is not a known condition " +
            "variable (a derived variable, score, persona, extraData key, or " +
            "engine-injected name), so it resolves to no value at runtime — check for a typo.",
    )
}
