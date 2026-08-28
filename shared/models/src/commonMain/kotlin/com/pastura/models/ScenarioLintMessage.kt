package com.pastura.models

/**
 * A parameter-carrying description of an ADR-024 semantic-lint finding message.
 *
 * Kotlin port of `Pastura/Pastura/Models/ScenarioLintMessage.swift`, **1:1
 * across all 21 cases** — the Swift enum is the single source of truth for the
 * set, the declaration order, and every literal. Each subtype is a portable
 * structured payload (name + typed args); [render] is the single rendering leaf
 * that turns one into a display string.
 *
 * ## Deliberately separate from [ScenarioValidationMessage]
 *
 * The two model different surfaces, and folding the 21 cases into
 * [ScenarioValidationMessage] was considered and rejected (issue #1562): a lint
 * finding carries a severity and is collected alongside other findings for the
 * same scenario, while a validation message is thrown as the sole reason a load
 * or commit-gate check failed. Conflating them would force a shared shape
 * neither surface actually has. [ScenarioValidationMessage]'s 53-case count pin
 * therefore stays at 53 — these cases never join it.
 *
 * ## Naming
 *
 * A subtype's name is its Swift case name with the first character uppercased,
 * with **no** other rewriting (so `pdNeedsRoundRobinChoose` →
 * [PdNeedsRoundRobinChoose], not `PDNeedsRoundRobinChoose`). That keeps the
 * mapping mechanical, which is what lets the commonTest case-set check compare a
 * hand-transcribed Swift name list against this hierarchy without a translation
 * table. Constructor parameter names likewise reuse the Swift argument labels —
 * every token-bearing case here uses the label `token`.
 *
 * ## Landed as infra
 *
 * Landed ahead of its consumer — `ScenarioSemanticLinter` — as the dependency
 * that had to exist before the linter port (D2a onward) could compile.
 * `ScenarioSemanticLinter` is now ported in full and, since D3 (#1591), wired
 * into `SimulationEngine.run`. Ported for the ADR-023 §6 Stage-3 Engine
 * migration (#501 / #1562).
 */
public sealed class ScenarioLintMessage {

    // ── Ordering (ScenarioSemanticLinter+Ordering.swift, R1–R6/R19) ─────────

    public object EliminateNeedsVote : ScenarioLintMessage()

    public object EliminateAfterVote : ScenarioLintMessage()

    public object PdNeedsRoundRobinChoose : ScenarioLintMessage()

    public object PairwisePayoffNeedsRoundRobinChoose : ScenarioLintMessage()

    public object WordwolfNeedsAssignAndVote : ScenarioLintMessage()

    public object EventReactiveNeedsEventInject : ScenarioLintMessage()

    public object RelationshipUpdatePlacement : ScenarioLintMessage()

    public object VoteTallyNeedsVote : ScenarioLintMessage()

    // ── Config (ScenarioSemanticLinter+Config.swift, R7/R8/R9/R17/R18/R20a/R20b) ──

    public object ChooseShouldDeclareOptions : ScenarioLintMessage()

    public object AssignSourceNonempty : ScenarioLintMessage()

    public object SummarizePairingPlaceholders : ScenarioLintMessage()

    public object MaxSentencesNoOp : ScenarioLintMessage()

    public object PairwisePayoffNoScorableRow : ScenarioLintMessage()

    public object PairwisePayoffDeadRow : ScenarioLintMessage()

    public object LogWindowBelowAgentCount : ScenarioLintMessage()

    // ── Placeholders (ScenarioSemanticLinter+Placeholders.swift, R10/R11/R12) ──

    public data class UnresolvablePlaceholder(public val token: String) : ScenarioLintMessage()

    public data class PlaceholderPhaseAvailability(public val token: String) : ScenarioLintMessage()

    public data class PerPersonaPlaceholderInSummarize(
        public val token: String,
    ) : ScenarioLintMessage()

    // ── Conditions (ScenarioSemanticLinter+Conditions.swift, R13/R14/R15) ───

    public data class SingleQuotedLiteralInCondition(
        public val token: String,
    ) : ScenarioLintMessage()

    public data class BareIdentifierLooksLikeLiteral(
        public val token: String,
    ) : ScenarioLintMessage()

    public data class UnknownConditionIdentifier(public val token: String) : ScenarioLintMessage()

    /**
     * Renders the case to its display string, in **English only**.
     *
     * The literals are byte-identical to the `String(localized:)` base values in
     * Swift's `ScenarioLintMessage.localized`, with each `%@` replaced by the
     * case's `token`. Swift substitutes through `String(format:)` with exactly
     * one argument, which interpolates the token **verbatim** — no quoting, no
     * escaping, and no second format pass over the result — so a plain Kotlin
     * string template is the faithful port, and a token containing a quote or a
     * `%` must survive untouched (the commonTest roster pins exactly that).
     *
     * ## Why en-only, and the Stage-5 debt it creates
     *
     * `commonMain` has no string catalog, and Kotlin/Native has no path to
     * `Localizable.xcstrings`. ADR-023 §5 defines no boundary for this type and
     * nothing consumes it in production until the linter port, so there is no
     * localization contract to satisfy yet, and inventing one here would be
     * guessing at Stage-5's design.
     *
     * Every one of these 21 literals **already has a `ja` translation** in
     * `Pastura/Pastura/Resources/Localizable.xcstrings`. Lint findings are more
     * exposed than validation messages: they surface in the scenario **editor
     * UI**, one row per finding, as ordinary browsing output rather than as a
     * rare failure. If iOS starts consuming the Kotlin engine (Stage 5) while
     * this is still en-only, Japanese users read English lint findings in the
     * editor — a user-visible regression with **no compiler and no test signal**,
     * since the Kotlin side would be internally consistent and the commonTest
     * pins would stay green. A KDoc is only read by someone already in this file,
     * which is the wrong audience for a debt that fires at Stage 5, so it is also
     * recorded on the Stage-5 row of `docs/kmp-migration-status.md`.
     *
     * The Stage-5 fix is to make the rendering an `expect`/`actual` leaf, or to
     * route the Apple side back through the Swift `localized`. Member naming here
     * is chosen so either lands without moving callers: `render()` keeps its name
     * and signature, and only its body delegates to the platform leaf. When
     * budgeting that, count **source sets, not targets** — re-derive from
     * `shared/models/build.gradle.kts`, whose four Apple targets share a parent
     * source set under the default hierarchy template.
     *
     * ## No gate covers the dual landing of these 21 literals
     *
     * These literals are dual-landed with Swift's `ScenarioLintMessage.localized`
     * (that property's own doc comment says the same from the other side).
     * Reword one there and the twin here, plus this module's expected-string
     * pins, stay stale *and agree with each other* — so nothing reddens on either
     * side. `check-prompt-literal-parity.py` does not close it: it only looks at
     * `Engine/` + `LLM/` files containing `pickLanguage`, which never reaches
     * `Models/`. The mitigation is procedural only — the Swift file is the source
     * of truth, and a reword there is a two-file edit by hand.
     */
    public fun render(): String = when (this) {
        // ── Ordering ────────────────────────────────────────────────────────
        is EliminateNeedsVote ->
            "eliminate-needs-vote: an 'eliminate' phase does nothing without a 'vote' phase " +
                "in the same round — add a 'vote' phase before it."
        is EliminateAfterVote ->
            "eliminate-after-vote: this 'eliminate' runs before every 'vote' phase, so it " +
                "acts on the previous round's stale tally — move it after the 'vote' phase."
        is PdNeedsRoundRobinChoose ->
            "pd-needs-round-robin-choose: 'prisoners_dilemma' scoring needs a round-robin " +
                "'choose' phase earlier in the round to populate pairings, or scores never " +
                "change — add one before this 'score_calc'."
        is PairwisePayoffNeedsRoundRobinChoose ->
            "pairwise-payoff-needs-round-robin-choose: 'pairwise_payoff' scoring needs a " +
                "round-robin 'choose' phase earlier in the round to populate pairings, or " +
                "scores never change — add one before this 'score_calc'."
        is WordwolfNeedsAssignAndVote ->
            "wordwolf-needs-assign-and-vote: 'wordwolf_judge' scoring needs both an 'assign' " +
                "phase with target 'random_one' and a 'vote' phase earlier in the round, or it " +
                "judges nothing — add the missing phase(s) before this 'score_calc'."
        is EventReactiveNeedsEventInject ->
            "event-reactive-needs-event-inject: 'event_reactive' scoring needs an earlier " +
                "'event_inject' phase with a dictionary event source and the default " +
                "'as: current_event', or the favored action is never scored — fix the " +
                "'event_inject' before this 'score_calc'."
        is RelationshipUpdatePlacement ->
            "relationship-update-placement: this 'relationship_update' cannot see its " +
                "vote/choose signals — place it after the producing 'vote'/'choose' phase and " +
                "before any 'prisoners_dilemma' 'score_calc', with no 'speak'/'choose' phase " +
                "between the vote and it."
        is VoteTallyNeedsVote ->
            "vote-tally-needs-vote: 'vote_tally' scoring has no 'vote' phase earlier in the " +
                "round, so it scores nothing or re-adds a stale tally — add a 'vote' phase " +
                "before this 'score_calc'."
        // ── Config ──────────────────────────────────────────────────────────
        is ChooseShouldDeclareOptions ->
            "choose-should-declare-options: this 'choose' phase has no 'options' list, so " +
                "the agent's action is unconstrained free text — add an 'options' list to steer " +
                "the choice."
        is AssignSourceNonempty ->
            "assign-source-nonempty: this 'assign' phase's source resolves to an empty list, " +
                "so nothing is assigned (or every agent gets an empty value) — add at least one " +
                "entry to the referenced source data."
        is SummarizePairingPlaceholders ->
            "summarize-pairing-placeholders: this 'summarize' template references " +
                "{agent1}-family placeholders, but no round-robin 'choose' phase runs earlier " +
                "in the round, so the placeholders leak literally into the summary — add a " +
                "round-robin 'choose' phase before this 'summarize', or remove the pairing " +
                "placeholders."
        is MaxSentencesNoOp ->
            "max-sentences-no-op: this phase emits no LLM statement, so its 'max_sentences' " +
                "cap never reaches a prompt and has no effect — remove it, or move it to a " +
                "phase that emits a statement (speak_all / speak_each / whisper)."
        is PairwisePayoffNoScorableRow ->
            "pairwise-payoff-no-scorable-row: no 'payoff' row's 'when' tokens match the " +
                "round-robin 'choose' options, so no pairing is ever scored — add a 'payoff' " +
                "table whose 'when' rows use the 'choose' option tokens."
        is PairwisePayoffDeadRow ->
            "pairwise-payoff-dead-row: one or more 'payoff' rows use 'when' tokens that " +
                "aren't in the round-robin 'choose' options, so those rows never fire — fix the " +
                "tokens to match the 'choose' options, or remove the unused rows."
        is LogWindowBelowAgentCount ->
            "log-window-below-agent-count: 'log_window' is smaller than the agent count " +
                "while a 'speak_each' phase is present, so same-round earlier speakers vanish " +
                "from the addressee pool — raise 'log_window' to at least the agent count."
        // ── Placeholders ────────────────────────────────────────────────────
        is UnresolvablePlaceholder ->
            "unresolvable-placeholder: the placeholder '{$token}' is supplied by no " +
                "phase, so it leaks into the LLM prompt verbatim — check for a typo or remove it."
        is PlaceholderPhaseAvailability ->
            "placeholder-phase-availability: the placeholder '{$token}' is only " +
                "populated by a producing phase, but none runs earlier in the phase list, so it " +
                "resolves to an empty value — move the producing phase before this one."
        is PerPersonaPlaceholderInSummarize ->
            "per-persona-placeholder-in-summarize: the per-persona placeholder " +
                "'{$token}' is never populated in a 'summarize' phase (summaries aren't " +
                "per-agent), so it leaks literally — remove it or move it to an LLM phase."
        // ── Conditions ──────────────────────────────────────────────────────
        is SingleQuotedLiteralInCondition ->
            "single-quoted-literal-in-condition: the operand $token is single-quoted, " +
                "but the condition evaluator treats only double quotes as string literals — it " +
                "is read as an undefined identifier and the comparison is always false. Use " +
                "double quotes instead."
        is BareIdentifierLooksLikeLiteral ->
            "bare-identifier-looks-like-literal: the operand '$token' matches a persona " +
                "name but is unquoted, so the condition evaluator reads it as an undefined " +
                "identifier and the comparison is always false — wrap it in double quotes to " +
                "compare against the name."
        is UnknownConditionIdentifier ->
            "unknown-condition-identifier: '$token' is not a known condition " +
                "variable (a derived variable, score, persona, extraData key, or " +
                "engine-injected name), so it resolves to no value at runtime — check for a typo."
    }

    public companion object {
        /**
         * Every rule ID, in declaration order, one per subtype above — the port
         * of Swift's `ScenarioLintMessage.ruleIDs`, which stands in for
         * `CaseIterable` (unavailable there because six cases carry an
         * associated `token: String`).
         *
         * The order is part of the contract, not incidental: it is what lets the
         * commonTest suite zip this list against the roster and assert that each
         * rendering starts with its own rule ID. Add a subtype and this list, the
         * roster, and the `21` pins all move together.
         */
        public val ruleIDs: List<String> = listOf(
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
    }
}
