package com.pastura.engine

import com.pastura.models.AnyCodableValue
import com.pastura.models.AssignTarget
import com.pastura.models.PairingStrategy
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import com.pastura.models.ScenarioLintMessage
import com.pastura.models.ScoreCalcLogic

/**
 * Severity tier for a [LintFinding] — the three-tier boundary from ADR-024.
 *
 * - [ERROR]: statically provable no-op or guaranteed-wrong semantics, with no
 *   deliberate-authoring reading -> **blocking** (treated like a
 *   [ScenarioValidator] error at the commit and run gates).
 * - [WARNING]: probably unintended, but a deliberate reading exists -> **never
 *   blocks** (editor findings list + run-start `.summary` channel).
 * - [INFO]: advisory only, editor-surfaced.
 *
 * Declaration order is load-bearing: it is `INFO, WARNING, ERROR` (blocking
 * strength, least to most severe) specifically so Kotlin's enum-declaration-order
 * `Comparable` synthesis matches Swift's explicit `Comparable` conformance
 * (`info < warning < error`) without any custom `compareTo`. Reordering these
 * cases silently flips every ordering comparison.
 *
 * Kotlin port of `Pastura/Pastura/Engine/ScenarioSemanticLinter.swift`'s
 * `LintSeverity`. Ported for the ADR-023 Stage 3 Engine migration (D2a).
 */
public enum class LintSeverity {
    INFO,
    WARNING,
    ERROR,
}

/**
 * A single semantic-lint finding against a [Scenario] (ADR-024).
 *
 * Findings are advisory-to-blocking depending on [severity] (see
 * [LintSeverity] for the three-tier contract). Each carries a stable
 * [ruleId] and a fix-hint [message] so a blocked scenario is actionable.
 *
 * Kotlin port of `Pastura/Pastura/Engine/ScenarioSemanticLinter.swift`'s
 * `LintFinding`. Ported for the ADR-023 Stage 3 Engine migration (D2a).
 *
 * @property ruleId Stable rule identifier (e.g. `"eliminate-needs-vote"`).
 * @property severity Blocking strength of this finding — see [LintSeverity].
 * @property message Human-readable description with a fix hint.
 * @property phaseIndex The phase-list index this finding anchors to (editor UI
 *   anchor); `null` for scenario-level findings.
 */
public data class LintFinding(
    public val ruleId: String,
    public val severity: LintSeverity,
    public val message: String,
    public val phaseIndex: Int?,
)

/**
 * Surfaces silent-no-op / guaranteed-wrong scenario authoring at load time
 * (ADR-024), separate from [ScenarioValidator]'s fail-fast single-error gate.
 *
 * Where [ScenarioValidator] throws on the first hard-limit / shape violation,
 * the linter returns a findings array spanning three severity tiers (see
 * [LintSeverity]): errors block like validation errors, warnings and info
 * never block. It judges *reachability and effect* only — never content
 * quality, thematic fit, or style.
 *
 * Kotlin port of `Pastura/Pastura/Engine/ScenarioSemanticLinter.swift` and its
 * sibling extension `Pastura/Pastura/Engine/ScenarioSemanticLinter+Ordering.swift`
 * (ADR-023 §4, the "Load + validate" row; ADR-024). `LintFinding` /
 * `LintSeverity` live here (in `shared/engine`), not `shared/models`, because
 * their Swift originals live in `Engine/`, not `Models/`.
 *
 * ## Scope: Ordering (D2a) + Config (D2b) + Placeholders (D2c)
 *
 * The Swift linter folds four rule groups into [lint]: producer–consumer
 * ordering (R1a/R1b/R2/R3/R4/R5/R6/R19, `+Ordering.swift`), silently-inert
 * configuration (R7/R8/R9/R17/R18/R20a/R20b, `+Config.swift`), placeholder
 * resolution (R10–R12, `+Placeholders.swift`) and condition expressions
 * (R13–R16, `+Conditions.swift`). D2a ported the base types ([LintFinding],
 * [LintSeverity]), the shared traversal helpers ([PhaseRef],
 * [producerIndices], [phaseRefs], [branchPhases]) and the Ordering rules
 * ([orderingFindings]); D2b added the Config group ([configFindings]); D2c
 * adds the Placeholders group ([placeholderFindings]). Conditions (D2d) is
 * still missing, so [lint] returns the ordering + config + placeholder union,
 * not the full four-group union the Swift `lint(_:)` returns.
 *
 * ## Not wired into the engine
 *
 * Nothing in `shared/engine` calls this yet, deliberately — same reasoning as
 * [ScenarioValidator]'s "Not wired into the engine" section. ADR-023 §4 has
 * the preflight gate on the validator **and** this linter together; wiring
 * either alone into `SimulationEngine` would split one preflight across two
 * languages, which is exactly the shape ADR-023 §4 rejects. D3 wires
 * validator + linter together once both are complete.
 *
 * ## Visibility
 *
 * `public`, matching [ScenarioValidator] and `ScenarioLoader` — this type is
 * the D3 preflight entry point a future Kotlin/Swift consumer calls.
 * Deliberately unlike [PlaceholderAvailability]'s `internal` (D1b): that type
 * had no Kotlin consumer and no future export role of its own, while this one
 * is itself the export surface D3 wires up.
 */
public class ScenarioSemanticLinter {

    /**
     * Lints [scenario], returning every finding across the ported rule
     * groups.
     *
     * @param scenario The scenario to lint.
     * @return All findings; empty when the scenario is semantically clean
     *   (with respect to the currently-ported rule groups — see the class
     *   doc's Scope section).
     */
    public fun lint(scenario: Scenario): List<LintFinding> =
        orderingFindings(scenario) + configFindings(scenario) + placeholderFindings(scenario)

    // MARK: - Ordering rules (R1a/R1b/R2/R3/R4/R5/R6/R19)
    //
    // Ported from `ScenarioSemanticLinter+Ordering.swift`. Each rule compares
    // **phase-list indices**: a consuming phase (`eliminate` / `score_calc`)
    // needs its producer (`vote`, round-robin `choose`, `assign random_one`,
    // dict-shaped `event_inject`) to run earlier in the round, or it silently
    // no-ops / scores on a stale value.
    //
    // Two shared semantics (both deliberate imprecisions recorded in ADR-024):
    //
    // - Producer inside a `conditional` branch counts as present at the
    //   conditional's top-level index (may-run suffices — it avoids
    //   false-positive errors at the cost of missing branch-only producers).
    // - A consumer inside a `conditional` branch anchors its finding to the
    //   conditional's top-level index (`eliminate` / `score_calc` are allowed
    //   inside branches). "Earlier" is therefore `index <= consumerIndex`, so
    //   a producer sharing the consumer's enclosing conditional is treated as
    //   satisfying the dependency rather than flagged.

    /** Producer–consumer ordering findings (R1a/R1b/R2/R3/R5/R6/R19 + R4). */
    internal fun orderingFindings(scenario: Scenario): List<LintFinding> {
        val phases = scenario.phases
        val votes = producerIndices(phases) { it.type == PhaseType.VOTE }
        val roundRobinChoose = producerIndices(phases) {
            it.type == PhaseType.CHOOSE && it.pairing == PairingStrategy.ROUND_ROBIN
        }
        val assignRandomOne = producerIndices(phases) {
            it.type == PhaseType.ASSIGN && (it.target ?: AssignTarget.ALL) == AssignTarget.RANDOM_ONE
        }
        val eventInject = producerIndices(phases) { isQualifyingEventInject(it, scenario) }

        val findings = mutableListOf<LintFinding>()
        for (consumer in phaseRefs(phases, ::isOrderingConsumer)) {
            when (consumer.phase.type) {
                PhaseType.ELIMINATE -> findings += eliminateFindings(consumer, votes)
                PhaseType.SCORE_CALC -> findings += scoreCalcFindings(
                    consumer, votes = votes, roundRobinChoose = roundRobinChoose,
                    assignRandomOne = assignRandomOne, eventInject = eventInject,
                )
                // Only ELIMINATE / SCORE_CALC reach here — `isOrderingConsumer`
                // filters the rest. A new ordering consumer needs an arm added
                // there AND here; this `else` is the Swift `default: break`.
                else -> Unit
            }
        }
        findings += relationshipPlacementFindings(scenario)
        return findings
    }

    // MARK: - R4 relationship-update-placement (warning)

    /**
     * R4 `relationship-update-placement` — a top-level `relationship_update`
     * whose declared update rules can't see the signals they read.
     *
     * `relationship_update` is **top-level only** (the validator bans it
     * inside conditional branches), so this scans top-level phases.
     * Producers, however, may sit inside a `conditional` branch and still
     * count (may-run, `< i` via [producerIndices]).
     *
     * Predicates derive from `RelationshipUpdateHandler`'s actual reads —
     * each declared rule reads a different piece of state, and each is lost
     * by a distinct placement mistake:
     *
     * - `voteAgainst` reads `state.lastOutputs[voter].vote`. Broken when
     *   (a) no `vote` runs before this phase, or (b) a `lastOutputs`-writing
     *   LLM phase overwrites the voter's entry between the last preceding
     *   `vote` and this phase. `speak_all` / `speak_each` / `choose` all
     *   write `lastOutputs` and carry no `vote` field, so they drop the
     *   signal; a *second* `vote` merely rewrites a fresher vote (not a
     *   loss) and is excluded; `reflect` / `whisper` never touch
     *   `lastOutputs` and are safe interleaves.
     * - `actionDeltas` reads `state.pairings`, populated only by a
     *   round-robin `choose`. Broken when (a) no round-robin `choose` runs
     *   before this phase, or (b) a pairings-clearing `score_calc`
     *   (`prisoners_dilemma` or `pairwise_payoff` — both clear
     *   `state.pairings`) sits between the LAST preceding round-robin
     *   `choose` and this phase — a later choose surviving un-cleared
     *   satisfies the rule (no false positive).
     *
     * One finding per phase max. Fires when ANY declared rule's signal is
     * lost: a phase declaring both rules where only one is reachable is
     * still a real (partial) placement bug the author should see. A phase
     * declaring neither rule can't reach here —
     * `ScenarioValidator.validateRelationshipUpdateShape` rejects it
     * upstream.
     */
    private fun relationshipPlacementFindings(scenario: Scenario): List<LintFinding> {
        val phases = scenario.phases
        val votes = producerIndices(phases) { it.type == PhaseType.VOTE }
        val roundRobinChoose = producerIndices(phases) {
            it.type == PhaseType.CHOOSE && it.pairing == PairingStrategy.ROUND_ROBIN
        }
        // Both `prisoners_dilemma` and `pairwise_payoff` clear `state.pairings`
        // after scoring (ADR-027), so both break a later `action_deltas` read.
        // This is an `==` predicate — invisible to ADR-022's compiler gate, so
        // it must be hand-maintained when a pairings-clearing logic is added.
        val pairingsClearingScoreCalc = producerIndices(phases) {
            it.type == PhaseType.SCORE_CALC &&
                (it.logic == ScoreCalcLogic.PRISONERS_DILEMMA || it.logic == ScoreCalcLogic.PAIRWISE_PAYOFF)
        }
        // `lastOutputs`-writers that DROP the vote field. A second `vote`
        // rewrites a fresher vote rather than losing it, so `.vote` is
        // excluded here.
        val voteSignalLosers = producerIndices(phases) {
            it.type == PhaseType.SPEAK_ALL || it.type == PhaseType.SPEAK_EACH || it.type == PhaseType.CHOOSE
        }

        val findings = mutableListOf<LintFinding>()
        // Top-level scan: `relationship_update` is never nested in a branch.
        phases.forEachIndexed { i, phase ->
            if (phase.type == PhaseType.RELATIONSHIP_UPDATE) {
                val voteBroken = phase.voteAgainst != null &&
                    voteSignalUnreachable(before = i, votes = votes, losers = voteSignalLosers)
                val actionBroken = !phase.actionDeltas.isNullOrEmpty() &&
                    actionSignalUnreachable(
                        before = i, choose = roundRobinChoose, clears = pairingsClearingScoreCalc,
                    )
                if (voteBroken || actionBroken) {
                    findings += finding("relationship-update-placement", LintSeverity.WARNING, i)
                }
            }
        }
        return findings
    }

    /**
     * Whether a `vote_against` rule at top-level index [before] can't read a
     * vote: no `vote` precedes it, or a `lastOutputs`-overwriting phase sits
     * between the last preceding `vote` and it.
     */
    private fun voteSignalUnreachable(before: Int, votes: Set<Int>, losers: Set<Int>): Boolean {
        val lastVote = votes.filter { it < before }.maxOrNull() ?: return true
        return losers.any { it > lastVote && it < before }
    }

    /**
     * Whether an `action_deltas` rule at top-level index [before] can't
     * read pairings: no round-robin `choose` precedes it, or a
     * pairings-clearing `prisoners_dilemma` / `pairwise_payoff` `score_calc`
     * sits between the last preceding round-robin `choose` and it (a later
     * un-cleared choose satisfies the rule).
     */
    private fun actionSignalUnreachable(before: Int, choose: Set<Int>, clears: Set<Int>): Boolean {
        val lastChoose = choose.filter { it < before }.maxOrNull() ?: return true
        return clears.any { it > lastChoose && it < before }
    }

    /**
     * Shared R2 (`pd-needs-round-robin-choose`) / R19
     * (`pairwise-payoff-needs-round-robin-choose`) predicate: a
     * pairing-consuming `score_calc` at top-level index [idx] needs a
     * round-robin `choose` at or before it to populate `state.pairings`, or
     * scores never change. `true` ⇒ the finding fires. Extracted so R2 and
     * R19 share one predicate while keeping distinct ruleIds (ADR-024 §
     * Amendment 2026-07-17).
     */
    private fun needsRoundRobinChoose(idx: Int, roundRobinChoose: Set<Int>): Boolean =
        roundRobinChoose.none { it <= idx }

    /**
     * R3 `wordwolf-needs-assign-and-vote` (error): `wordwolf_judge` needs
     * both an `assign target: random_one` (to pick the odd-one-out) and a
     * `vote` at or before it. Extracted from [scoreCalcFindings] — the Swift
     * original does this to keep its cyclomatic complexity within the lint
     * budget; Kotlin carries no such cyclomatic-complexity gate, but the
     * extraction is kept anyway to stay a faithful 1:1 port.
     */
    private fun wordwolfFindings(idx: Int, votes: Set<Int>, assignRandomOne: Set<Int>): List<LintFinding> {
        val hasAssign = assignRandomOne.any { it <= idx }
        val hasVote = votes.any { it <= idx }
        if (hasAssign && hasVote) return emptyList()
        return finding("wordwolf-needs-assign-and-vote", LintSeverity.ERROR, idx)
    }

    // MARK: - Per-consumer rules

    /** R1a `eliminate-needs-vote` (error) + R1b `eliminate-after-vote` (warning). */
    private fun eliminateFindings(consumer: PhaseRef, votes: Set<Int>): List<LintFinding> {
        val idx = consumer.topLevelIndex
        if (votes.isEmpty()) {
            return finding("eliminate-needs-vote", LintSeverity.ERROR, idx)
        }
        if (votes.none { it <= idx }) {
            return finding("eliminate-after-vote", LintSeverity.WARNING, idx)
        }
        return emptyList()
    }

    /** R2/R3/R5/R6/R19 — the `score_calc` logic-specific producer dependencies. */
    private fun scoreCalcFindings(
        consumer: PhaseRef,
        votes: Set<Int>,
        roundRobinChoose: Set<Int>,
        assignRandomOne: Set<Int>,
        eventInject: Set<Int>,
    ): List<LintFinding> {
        val idx = consumer.topLevelIndex
        // ADR-022 no-default convention: every ScoreCalcLogic case gets an
        // explicit arm, plus `null` for a missing `logic` — no `else`.
        return when (consumer.phase.logic) {
            ScoreCalcLogic.PRISONERS_DILEMMA -> {
                if (!needsRoundRobinChoose(idx, roundRobinChoose)) return emptyList()
                finding("pd-needs-round-robin-choose", LintSeverity.ERROR, idx)
            }
            ScoreCalcLogic.PAIRWISE_PAYOFF -> {
                // R19 — semantically identical to R2, but a distinct ruleId
                // (ADR-024 D3 "IDs are stable"): a `pd-needs-…` finding on a
                // scenario with no prisoner's dilemma names the wrong
                // mechanic. Shares R2's predicate.
                if (!needsRoundRobinChoose(idx, roundRobinChoose)) return emptyList()
                finding("pairwise-payoff-needs-round-robin-choose", LintSeverity.ERROR, idx)
            }
            ScoreCalcLogic.WORDWOLF_JUDGE -> wordwolfFindings(idx, votes, assignRandomOne)
            ScoreCalcLogic.EVENT_REACTIVE -> {
                if (eventInject.any { it <= idx }) return emptyList()
                finding("event-reactive-needs-event-inject", LintSeverity.ERROR, idx)
            }
            ScoreCalcLogic.VOTE_TALLY -> {
                if (votes.any { it <= idx }) return emptyList()
                finding("vote-tally-needs-vote", LintSeverity.WARNING, idx)
            }
            null -> {
                // Missing `logic` is a `ScenarioValidator` / handler error, not
                // a lint concern — the linter doesn't second-guess it here.
                emptyList()
            }
        }
    }

    /**
     * Builds the single-element findings list for an ordering [ruleId],
     * resolving its fix-hint message via [orderingMessage].
     */
    private fun finding(ruleId: String, severity: LintSeverity, idx: Int): List<LintFinding> =
        listOf(LintFinding(ruleId = ruleId, severity = severity, message = orderingMessage(ruleId), phaseIndex = idx))

    /**
     * The user-facing fix-hint message for an ordering [ruleId] (one
     * sentence naming the rule + a concrete fix), rendered via
     * [ScenarioLintMessage].
     */
    private fun orderingMessage(ruleId: String): String = when (ruleId) {
        "eliminate-needs-vote" -> ScenarioLintMessage.EliminateNeedsVote.render()
        "eliminate-after-vote" -> ScenarioLintMessage.EliminateAfterVote.render()
        "pd-needs-round-robin-choose" -> ScenarioLintMessage.PdNeedsRoundRobinChoose.render()
        "pairwise-payoff-needs-round-robin-choose" ->
            ScenarioLintMessage.PairwisePayoffNeedsRoundRobinChoose.render()
        "wordwolf-needs-assign-and-vote" -> ScenarioLintMessage.WordwolfNeedsAssignAndVote.render()
        "event-reactive-needs-event-inject" -> ScenarioLintMessage.EventReactiveNeedsEventInject.render()
        "relationship-update-placement" -> ScenarioLintMessage.RelationshipUpdatePlacement.render()
        // Falls to `vote-tally-needs-vote`: the only remaining `score_calc`
        // logic arm (`.voteTally`) that reaches `finding`.
        else -> ScenarioLintMessage.VoteTallyNeedsVote.render()
    }

    private fun isOrderingConsumer(phase: Phase): Boolean =
        phase.type == PhaseType.ELIMINATE || phase.type == PhaseType.SCORE_CALC

    /**
     * Whether an `event_inject` phase writes the `current_event__favors`
     * companion variable `EventReactivePayoffLogic` reads: dict-shaped
     * source (`{text, favors}` -> [AnyCodableValue.ArrayOfDictionariesValue])
     * AND the default `as:` name (`ScoreCalcHandler` hardcodes
     * `favoredVariableName(for: defaultVariableName)`).
     */
    private fun isQualifyingEventInject(phase: Phase, scenario: Scenario): Boolean =
        phase.type == PhaseType.EVENT_INJECT &&
            phase.eventVariable == null &&
            phase.source != null &&
            scenario.extraData[phase.source] is AnyCodableValue.ArrayOfDictionariesValue

    // MARK: - Config rules (R7/R8/R9/R17/R18/R20a/R20b)
    //
    // Ported from `ScenarioSemanticLinter+Config.swift`. Unlike the ordering
    // rules above, these rules don't compare producer/consumer phase indices —
    // each phase (or the scenario as a whole, for R17) is inert on its own
    // terms because of a missing/empty field, an out-of-place field (a
    // `max_sentences` on a code phase, for R18), or because a *different*
    // producer relation (a round-robin `choose` gating pairing-placeholder
    // resolution, for R9) never ran earlier. R9/R18 reuse the same "producer
    // inside a `conditional` branch counts as present at the conditional's
    // index" imprecision documented on the ordering rules.

    /** Silently-inert-configuration findings (R7/R8/R9/R17/R18/R20a/R20b). */
    internal fun configFindings(scenario: Scenario): List<LintFinding> =
        chooseOptionsFindings(scenario.phases) +
            assignSourceFindings(scenario.phases, scenario) +
            summarizePairingFindings(scenario.phases) +
            logWindowFindings(scenario) +
            maxSentencesNoOpFindings(scenario.phases) +
            payoffTokenFindings(scenario.phases)

    // MARK: - R7 choose-should-declare-options (warning)

    /**
     * A `choose` phase with null/empty `options` leaves the action
     * unconstrained — `ChooseHandler.validateAction` returns the raw model
     * output verbatim when `options` is empty, and `PromptBuilder` has no
     * option list to steer the model with. Uniformly [LintSeverity.WARNING]
     * (never escalated) — with `options` absent the prompt wording may still
     * elicit the intended values, so "wrong" is probable, not statically
     * provable (unlike R2's empty `pairings`).
     */
    private fun chooseOptionsFindings(phases: List<Phase>): List<LintFinding> =
        phaseRefs(phases) { it.type == PhaseType.CHOOSE && (it.options ?: emptyList()).isEmpty() }
            .map { configFinding("choose-should-declare-options", LintSeverity.WARNING, it.topLevelIndex) }

    // MARK: - R8 assign-source-nonempty (error)

    /**
     * An `assign` phase whose source resolves to an empty list assigns nothing
     * (`target: random_one`) or `""` to every agent (`target: all` with an
     * empty array) — `AssignHandler`'s per-target branches both no-op on an
     * empty collection. Mirrors `AssignHandler`'s shape branches exactly rather
     * than duplicating [ScenarioValidator]'s assign shape errors (missing key /
     * mismatched shape stay that gate's lane): this rule only adds the
     * emptiness check on top of an already-resolved, correctly-shaped source.
     */
    private fun assignSourceFindings(phases: List<Phase>, scenario: Scenario): List<LintFinding> =
        phaseRefs(phases) { it.type == PhaseType.ASSIGN && isAssignSourceEmpty(it, scenario) }
            .map { configFinding("assign-source-nonempty", LintSeverity.ERROR, it.topLevelIndex) }

    /**
     * Whether an `assign` phase's resolved source is empty for its `target`
     * mode. Returns `false` (no finding) when the source is missing or shaped
     * incompatibly with `target` — those are [ScenarioValidator]'s errors, not
     * this rule's to duplicate.
     *
     * ADR-022 no-default convention: both the [AssignTarget] `when` and the
     * [AnyCodableValue] shape `when`s enumerate every arm explicitly, so a new
     * target mode or a new value shape fails the build here instead of falling
     * into a silent `else`.
     */
    private fun isAssignSourceEmpty(phase: Phase, scenario: Scenario): Boolean {
        val sourceKey = phase.source ?: return false
        val sourceValue = scenario.extraData[sourceKey] ?: return false
        return when (phase.target ?: AssignTarget.ALL) {
            AssignTarget.RANDOM_ONE -> when (sourceValue) {
                is AnyCodableValue.ArrayOfDictionariesValue -> sourceValue.value.isEmpty()
                // Any other shape is a `random_one` shape mismatch — the
                // validator's error, so this rule stays silent.
                is AnyCodableValue.ArrayValue,
                is AnyCodableValue.StringValue,
                is AnyCodableValue.DictionaryValue,
                -> false
            }
            AssignTarget.ALL -> when (sourceValue) {
                is AnyCodableValue.ArrayValue -> sourceValue.value.isEmpty()
                // A single-string source is a legitimate `.all` shape — never
                // empty in the "nothing to iterate" sense `AssignHandler`'s
                // all-mode branch cares about (ADR-024 Rule-precision notes).
                is AnyCodableValue.StringValue -> false
                is AnyCodableValue.ArrayOfDictionariesValue,
                is AnyCodableValue.DictionaryValue,
                -> false
            }
        }
    }

    // MARK: - R9 summarize-pairing-placeholders (warning)

    /**
     * A `summarize` phase whose template references any `{agent1}`-family
     * token without a round-robin `choose` phase earlier in the round: those
     * tokens are only populated in `SummarizeHandler`'s per-pairing branch
     * (gated on `state.pairings` being non-empty, which only a round-robin
     * `choose` populates), so the braces leak literally into the summary text.
     */
    private fun summarizePairingFindings(phases: List<Phase>): List<LintFinding> {
        val roundRobinChoose = producerIndices(phases) {
            it.type == PhaseType.CHOOSE && it.pairing == PairingStrategy.ROUND_ROBIN
        }
        return phaseRefs(phases) {
            it.type == PhaseType.SUMMARIZE && containsPairingPlaceholder(it.template)
        }
            .filter { ref -> roundRobinChoose.none { it <= ref.topLevelIndex } }
            .map { configFinding("summarize-pairing-placeholders", LintSeverity.WARNING, it.topLevelIndex) }
    }

    /**
     * Whether [template] references any pairing-only token
     * ([PlaceholderAvailability.pairingInjected]: `agent1`/`action1`/`agent2`/
     * `action2`/`score1`/`score2`).
     */
    private fun containsPairingPlaceholder(template: String?): Boolean {
        if (template == null) return false
        return PlaceholderAvailability.pairingInjected.any { template.contains("{$it}") }
    }

    // MARK: - R17 log-window-below-agent-count (warning)

    /**
     * `log_window < agentCount` with a `speak_each` phase present truncates
     * same-round earlier speakers out of the addressee pool the accumulating
     * `speak_each` prompt reads (documented in `.claude/rules/engine.md`, not
     * enforced anywhere at load time until this rule). Scenario-level finding
     * (`phaseIndex = null`) — the mismatch is between two scenario-wide
     * fields, not any single phase.
     */
    private fun logWindowFindings(scenario: Scenario): List<LintFinding> {
        val logWindow = scenario.logWindow ?: return emptyList()
        if (logWindow >= scenario.agentCount) return emptyList()
        if (!hasSpeakEach(scenario.phases)) return emptyList()
        return listOf(
            LintFinding(
                ruleId = "log-window-below-agent-count",
                severity = LintSeverity.WARNING,
                message = configMessage("log-window-below-agent-count"),
                phaseIndex = null,
            ),
        )
    }

    /**
     * Whether any `speak_each` phase is present, top-level or nested in a
     * `conditional` branch (may-run counts as present, same as the ordering
     * rules' producer check).
     */
    private fun hasSpeakEach(phases: List<Phase>): Boolean =
        phaseRefs(phases) { it.type == PhaseType.SPEAK_EACH }.isNotEmpty()

    // MARK: - R18 max-sentences-no-op (warning)

    /**
     * A `max_sentences` set on a phase that emits no LLM statement is a silent
     * no-op: it is parsed, round-tripped, and serialized, but never reaches a
     * prompt. The brevity bullet it feeds is emitted only by
     * `PromptBuilder.buildAnswerRules`, which is called from
     * `buildSystemPrompt` — reached solely by the `requiresLLM` handlers. So
     * [PhaseType.requiresLLM] is exactly the "cap reaches the prompt"
     * predicate, and its inverse is the provable no-op set. Reusing that
     * existing no-default exhaustive `when` keeps a single source of truth: a
     * new phase type forces a decision there and R18 follows automatically.
     * `reflect` is **excluded** (it is `requiresLLM`) even though its cap
     * semantics are fuzzy (it emits a `note`, not a `statement`) — the bullet
     * is still emitted, so it is not a *silent* no-op. Uniformly
     * [LintSeverity.WARNING] — never blocks a run.
     */
    private fun maxSentencesNoOpFindings(phases: List<Phase>): List<LintFinding> =
        phaseRefs(phases) { it.maxSentences != null && !it.type.requiresLLM }
            .map { configFinding("max-sentences-no-op", LintSeverity.WARNING, it.topLevelIndex) }

    // MARK: - R20a pairwise-payoff-no-scorable-row (error) / R20b dead-row (warning)

    /**
     * R20a/R20b (ADR-024 § Amendment 2026-07-17): a `pairwise_payoff` `payoff`
     * table whose `when` tokens are checked against the round-robin `choose`
     * options that populate its pairings. `ChooseHandler.validateAction`
     * canonicalizes every action to an **exact** option string (on-menu
     * verbatim, else `options[0]`) — no case/whitespace folding — and
     * `PairwisePayoffLogic` matches rows by exact `==`, so a `when` token
     * outside the option set can never match a real action and its row is dead.
     * The exact [Set.contains] below mirrors that runtime exactly; if a future
     * change (ADR-021 § Amendment, PR2.5) adds folding to `validateAction`,
     * fold both sides here too, or this blocking [LintSeverity.ERROR] rule
     * becomes stricter than the runtime it models.
     *
     * - **R20a** ([LintSeverity.ERROR]): *no* row is satisfiable (incl. an
     *   absent/empty `payoff:`) -> every pairing scores nothing, a guaranteed
     *   no-op.
     * - **R20b** ([LintSeverity.WARNING]): some rows fire but at least one is
     *   dead -> the phase still scores; leaving combinations unlisted is a
     *   legitimate choice.
     *
     * Skipped when no options-bearing round-robin `choose` precedes: R19 owns
     * the "no round-robin choose" case and R7 owns "choose with no options", so
     * R20 has no closed set to check and must not double-report.
     */
    private fun payoffTokenFindings(phases: List<Phase>): List<LintFinding> {
        val chooseOptions = roundRobinChooseOptions(phases)
        return phaseRefs(phases) {
            it.type == PhaseType.SCORE_CALC && it.logic == ScoreCalcLogic.PAIRWISE_PAYOFF
        }
            .mapNotNull { payoffFinding(it, chooseOptions) }
    }

    /**
     * Round-robin `choose` phases carrying a non-empty `options` list, paired
     * with the top-level index their pairings anchor to (a branch choose counts
     * at its conditional's index — the may-run imprecision shared with the
     * ordering rules).
     *
     * Two entries can share one top-level index (a round-robin `choose` in both
     * the `then` and the `else` branch of one conditional). [payoffFinding]'s
     * "last qualifying entry" pick then depends on a tie-break: Swift's
     * `max(by:)` and Kotlin's [maxByOrNull] both return the **first** of equals,
     * so the twins agree — but neither is a documented guarantee and no fixture
     * pins it. Pin one before relying on the choice.
     */
    private fun roundRobinChooseOptions(phases: List<Phase>): List<Pair<Int, Set<String>>> {
        val result = mutableListOf<Pair<Int, Set<String>>>()
        phases.forEachIndexed { index, phase ->
            for (candidate in listOf(phase) + branchPhases(phase)) {
                if (candidate.type != PhaseType.CHOOSE || candidate.pairing != PairingStrategy.ROUND_ROBIN) {
                    continue
                }
                val options = candidate.options ?: emptyList()
                if (options.isNotEmpty()) result.add(index to options.toSet())
            }
        }
        return result
    }

    /**
     * The R20a/R20b finding for one `pairwise_payoff` `score_calc`, or `null`
     * when it has no options-bearing round-robin `choose` producer (R19/R7
     * territory) or every row is satisfiable.
     */
    private fun payoffFinding(
        ref: PhaseRef,
        chooseOptions: List<Pair<Int, Set<String>>>,
    ): LintFinding? {
        val idx = ref.topLevelIndex
        // The LAST qualifying producer by index wins (first-of-equals on ties):
        // Swift's `filter { $0.index <= idx }.max(by: { $0.index < $1.index })`.
        val options = chooseOptions.filter { it.first <= idx }.maxByOrNull { it.first }?.second
            ?: return null
        val rows = ref.phase.payoff ?: emptyList()
        val satisfiable = rows.filter {
            it.`when`.size == 2 && options.contains(it.`when`[0]) && options.contains(it.`when`[1])
        }
        if (satisfiable.isEmpty()) {
            return configFinding("pairwise-payoff-no-scorable-row", LintSeverity.ERROR, idx)
        }
        if (satisfiable.size < rows.size) {
            return configFinding("pairwise-payoff-dead-row", LintSeverity.WARNING, idx)
        }
        return null
    }

    // MARK: - Config shared

    /**
     * Builds the [LintFinding] for a config [ruleId], resolving its fix-hint
     * message via [configMessage].
     */
    private fun configFinding(ruleId: String, severity: LintSeverity, idx: Int): LintFinding =
        LintFinding(ruleId = ruleId, severity = severity, message = configMessage(ruleId), phaseIndex = idx)

    /**
     * The user-facing fix-hint message for a config [ruleId] (one sentence
     * naming the rule + a concrete fix), rendered via [ScenarioLintMessage].
     */
    private fun configMessage(ruleId: String): String = when (ruleId) {
        "choose-should-declare-options" -> ScenarioLintMessage.ChooseShouldDeclareOptions.render()
        "assign-source-nonempty" -> ScenarioLintMessage.AssignSourceNonempty.render()
        "summarize-pairing-placeholders" -> ScenarioLintMessage.SummarizePairingPlaceholders.render()
        "max-sentences-no-op" -> ScenarioLintMessage.MaxSentencesNoOp.render()
        "pairwise-payoff-no-scorable-row" -> ScenarioLintMessage.PairwisePayoffNoScorableRow.render()
        "pairwise-payoff-dead-row" -> ScenarioLintMessage.PairwisePayoffDeadRow.render()
        // Falls to `log-window-below-agent-count`: `logWindowFindings` is the
        // only other caller of `configMessage`, always with this ruleId.
        else -> ScenarioLintMessage.LogWindowBelowAgentCount.render()
    }

    // ── Placeholders (R10/R11/R12) ──
    //
    // Ported from `ScenarioSemanticLinter+Placeholders.swift`, reading the
    // linter-owned [PlaceholderAvailability] map (D1b).
    //
    // A single scan over each LLM phase's `prompt` (and each `summarize` phase's
    // `template`) extracts `{token}` occurrences and classifies each **once**, so
    // the three rules never double-fire on the same occurrence. Precedence per
    // token: R12 (summarize-specific) > R11 (known but ordered wrong) > R10
    // (unknown):
    //
    // - **R12 `per-persona-placeholder-in-summarize`** — a per-persona injected
    //   token (`assigned`/`assigned_word`/`my_notes`/`my_whispers`/`relationships`)
    //   in a `summarize` template. `SummarizeHandler` never calls the `inject*`
    //   helpers, so the braces leak literally. More specific than R10/R11, so it
    //   wins for these tokens in `summarize`.
    // - **R11 `placeholder-phase-availability`** — a *known* but producer-gated
    //   token (per [PlaceholderAvailability.producers], plus a custom
    //   `event_inject` `as:` name / its `__favors` companion) whose producing
    //   phase runs at no earlier top-level index -> resolves empty/stale.
    // - **R10 `unresolvable-placeholder`** — a token supplied by nothing: not in
    //   the phase's supplied set, not an engine-reserved / producer-gated name,
    //   not a per-persona reserved key, not a declared `extraData` key, not a
    //   custom event variable -> leaks verbatim to the LLM (typo or stray token).
    //
    // Token shape is `\{[A-Za-z_][A-Za-z0-9_]*\}` — an identifier-only body. This
    // deliberately never matches a JSON example brace (`{"statement": …}`,
    // `{ "vote": … }`, `{…}`), whose first inner character is a quote / space /
    // dot, so prompt-embedded output-format examples don't false-positive.

    /** Placeholder-resolution findings (R10/R11/R12). */
    internal fun placeholderFindings(scenario: Scenario): List<LintFinding> {
        val known = globallyKnownTokens(scenario)
        val findings = mutableListOf<LintFinding>()
        for (ref in phaseRefs(scenario.phases) { scannedField(it) != null }) {
            val field = scannedField(ref.phase) ?: continue
            for (token in placeholderTokens(field)) {
                val finding = placeholderFinding(
                    token = token, phase = ref.phase, index = ref.topLevelIndex,
                    known = known, scenario = scenario,
                )
                if (finding != null) findings.add(finding)
            }
        }
        return findings
    }

    // MARK: - Classification (single-fire)

    /**
     * Classifies one distinct [token] in a phase into at most one finding,
     * applying the R12 > R11 > R10 precedence (see the section header above).
     */
    private fun placeholderFinding(
        token: String,
        phase: Phase,
        index: Int,
        known: Set<String>,
        scenario: Scenario,
    ): LintFinding? {
        // R12: a per-persona token in a summarize template (most specific).
        if (phase.type == PhaseType.SUMMARIZE && perPersonaTokens.contains(token)) {
            return placeholderLintFinding(
                "per-persona-placeholder-in-summarize", LintSeverity.WARNING, token, index,
            )
        }
        // R10: token supplied by nothing at all — not globally known and not in
        // this phase type's own supplied set.
        val supplied = PlaceholderAvailability.supplied(
            phaseType = phase.type,
            chooseRoundRobin = phase.pairing == PairingStrategy.ROUND_ROBIN,
        )
        if (!known.contains(token) && !supplied.contains(token)) {
            return placeholderLintFinding("unresolvable-placeholder", LintSeverity.WARNING, token, index)
        }
        // R11: known, but producer-gated and no producer runs at an earlier index.
        // Self-supplied tokens (a whisper's `{my_whispers}`, a reflect's
        // `{my_notes}`) are in the phase's own supplied set -> never ordered-wrong.
        // `<=` (not `<`): a producer nested in a `conditional` branch anchors to the
        // conditional's index, so a consumer sub-phase ordered after it in the SAME
        // conditional shares that index (gallery kasei_sanso_touban: event_inject ->
        // speak_all inside one else-branch). Same-index counts as satisfied — the
        // may-run leniency the ordering rules already apply (`<= idx` there).
        val producers = producerIndicesForToken(token, scenario)
        if (producers != null &&
            !producerTypeMatchesPhase(token, phase) &&
            producers.none { it <= index }
        ) {
            return placeholderLintFinding("placeholder-phase-availability", LintSeverity.WARNING, token, index)
        }
        return null
    }

    // MARK: - Token universes

    /**
     * Every token resolvable *anywhere* in the scenario — engine-reserved names
     * ([PlaceholderAvailability.baseInjected] + every producer-gated token),
     * per-persona reserved keys (`assigned_<name>` / `notes_<name>` /
     * `whispers_<name>` / `relationships_<name>`), declared `extraData` keys, and
     * each `event_inject` `as:` name plus its `__favors` companion. Deliberately
     * generous — availability *ordering* is R11's lane, not R10's — so a token
     * produced by any phase counts as "known" here even if it appears before its
     * producer.
     */
    private fun globallyKnownTokens(scenario: Scenario): Set<String> {
        val known = mutableSetOf<String>()
        known.addAll(PlaceholderAvailability.baseInjected)
        known.addAll(PlaceholderAvailability.producerMap.keys)
        for (persona in scenario.personas) {
            known.add("assigned_${persona.name}")
            known.add("notes_${persona.name}")
            known.add("whispers_${persona.name}")
            known.add("relationships_${persona.name}")
        }
        known.addAll(scenario.extraData.keys)
        for (ref in phaseRefs(scenario.phases) { it.type == PhaseType.EVENT_INJECT }) {
            val name = ref.phase.eventVariable ?: EventInjectHandler.defaultVariableName
            known.add(name)
            known.add(EventInjectHandler.favoredVariableName(name))
        }
        return known
    }

    /**
     * The per-persona injected tokens (`inject{Assigned,Notes,Whispers,Relationships}`)
     * that only LLM phases write — absent from `summarize`'s supplied set, so
     * they leak literally there (R12's set).
     */
    private val perPersonaTokens: Set<String>
        get() = PlaceholderAvailability.perPersonaInjected
            .union(PlaceholderAvailability.whisperSelfInjected)

    // MARK: - Producer relation

    /**
     * Top-level indices at which [token]'s producer phase runs, or `null` when
     * [token] is not producer-gated. Covers both the static
     * [PlaceholderAvailability] producer map and a scenario-specific custom
     * `event_inject` `as:` variable (and its `__favors` companion).
     */
    private fun producerIndicesForToken(token: String, scenario: Scenario): Set<Int>? {
        val types = PlaceholderAvailability.producers(token)
        if (types != null) {
            return producerIndices(scenario.phases) { types.contains(it.type) }
        }
        val eventIndices = producerIndices(scenario.phases) { isEventInjectProducing(token, it) }
        return if (eventIndices.isEmpty()) null else eventIndices
    }

    /**
     * Whether [phase]'s own type produces [token] (self-supply): a `whisper`
     * referencing `{my_whispers}` or a `reflect` referencing `{my_notes}` reads
     * its own in-phase value, so R11 must not gate it on an *earlier* producer.
     *
     * Belt-and-suspenders, not load-bearing: the producing phase's own index is
     * already in [producerIndicesForToken], so the `<=` comparison would
     * self-satisfy anyway — this guard only states the intent explicitly.
     */
    private fun producerTypeMatchesPhase(token: String, phase: Phase): Boolean =
        PlaceholderAvailability.producers(token)?.contains(phase.type) ?: false

    /**
     * Whether an `event_inject` [phase] writes [token] — its resolved `as:`
     * variable (`eventVariable ?: "current_event"`) or that variable's
     * `__favors` companion.
     */
    private fun isEventInjectProducing(token: String, phase: Phase): Boolean {
        if (phase.type != PhaseType.EVENT_INJECT) return false
        val name = phase.eventVariable ?: EventInjectHandler.defaultVariableName
        return token == name || token == EventInjectHandler.favoredVariableName(name)
    }

    // MARK: - Field scanning

    /**
     * The template field scanned for placeholders: a `summarize` phase's
     * `template`, or any LLM phase's `prompt`. `null` (skip) for code phases and
     * empty fields.
     */
    private fun scannedField(phase: Phase): String? {
        val field = if (phase.type == PhaseType.SUMMARIZE) phase.template else phase.prompt
        if (field.isNullOrEmpty()) return null
        return field
    }

    /**
     * The distinct identifier bodies of every `{token}` in [field] (deduped so
     * a repeated occurrence yields a single finding).
     */
    private fun placeholderTokens(field: String): Set<String> {
        // No twin for Swift's `guard let regex`: Kotlin's [Regex] is non-null by
        // construction, so the optional-`NSRegularExpression` bail-out has nothing
        // to mirror here.
        //
        // The dedupe container differs in *iteration order* between the twins:
        // Swift's `Set<String>` order is per-process seed-randomised, while
        // Kotlin's `LinkedHashSet` (what `mutableSetOf` / `toSet()` build) is
        // insertion-ordered. So the relative order of MULTIPLE findings within one
        // phase is NOT a parity guarantee and must not be pinned by a test on
        // either side — only the finding *set* is the contract.
        val tokens = mutableSetOf<String>()
        for (match in PLACEHOLDER_REGEX.findAll(field)) {
            tokens.add(match.groupValues[1])
        }
        return tokens
    }

    // MARK: - Findings

    /** Builds a placeholder finding with its token-interpolated fix-hint message. */
    private fun placeholderLintFinding(
        ruleId: String,
        severity: LintSeverity,
        token: String,
        index: Int,
    ): LintFinding =
        LintFinding(
            ruleId = ruleId, severity = severity,
            message = placeholderMessage(ruleId, token), phaseIndex = index,
        )

    /**
     * The user-facing fix-hint message for a placeholder [ruleId], naming the
     * offending `{token}`, rendered via [ScenarioLintMessage].
     */
    private fun placeholderMessage(ruleId: String, token: String): String = when (ruleId) {
        "unresolvable-placeholder" -> ScenarioLintMessage.UnresolvablePlaceholder(token).render()
        "placeholder-phase-availability" ->
            ScenarioLintMessage.PlaceholderPhaseAvailability(token).render()
        // Falls to `per-persona-placeholder-in-summarize`: the only other
        // ruleId `placeholderFinding` builds via this helper.
        else -> ScenarioLintMessage.PerPersonaPlaceholderInSummarize(token).render()
    }

    private companion object {
        /**
         * Matches a `{token}` placeholder whose body is a single identifier. The
         * identifier-only body is what excludes JSON-example braces (see the
         * Placeholders section header). Twin of Swift's
         * `ScenarioSemanticLinter.placeholderRegex`.
         */
        val PLACEHOLDER_REGEX = Regex("""\{([A-Za-z_][A-Za-z0-9_]*)\}""")
    }

    // MARK: - Traversal helpers
    //
    // Ported from `ScenarioSemanticLinter+Ordering.swift`'s "Traversal helpers"
    // section. `internal`, not `private` — shared with the Config group's own
    // Kotlin port (D2b), which reuses this file's traversal semantics rather
    // than duplicating them (mirroring the Swift originals' `internal` visibility
    // for the same reason).

    /**
     * A phase paired with the top-level phase-list index its finding anchors
     * to (the enclosing conditional's index when nested in a branch).
     */
    internal data class PhaseRef(val phase: Phase, val topLevelIndex: Int)

    /**
     * Top-level indices at which [predicate] matches — the phase itself, or
     * any of its `conditional` sub-phases (may-run counts as present).
     *
     * Producer inside a `conditional` branch counts as present at the
     * conditional's top-level index: may-run suffices — it avoids
     * false-positive errors at the cost of missing branch-only producers
     * (a deliberate imprecision recorded in ADR-024).
     */
    internal fun producerIndices(phases: List<Phase>, predicate: (Phase) -> Boolean): Set<Int> {
        val result = mutableSetOf<Int>()
        phases.forEachIndexed { index, phase ->
            if (predicate(phase) || branchPhases(phase).any(predicate)) {
                result.add(index)
            }
        }
        return result
    }

    /**
     * Every phase matching [predicate], top-level or nested in a
     * `conditional` branch, anchored to its top-level index.
     *
     * A consumer inside a `conditional` branch anchors its finding to the
     * conditional's top-level index (`eliminate` / `score_calc` are allowed
     * inside branches).
     */
    internal fun phaseRefs(phases: List<Phase>, predicate: (Phase) -> Boolean): List<PhaseRef> {
        val result = mutableListOf<PhaseRef>()
        phases.forEachIndexed { index, phase ->
            if (predicate(phase)) {
                result.add(PhaseRef(phase = phase, topLevelIndex = index))
            }
            branchPhases(phase).filter(predicate).forEach { sub ->
                result.add(PhaseRef(phase = sub, topLevelIndex = index))
            }
        }
        return result
    }

    /**
     * The `then` + `else` sub-phases of a `conditional` (empty for other
     * types). Depth-1 is enforced upstream, so no recursion is needed.
     */
    internal fun branchPhases(phase: Phase): List<Phase> =
        (phase.thenPhases ?: emptyList()) + (phase.elsePhases ?: emptyList())
}
