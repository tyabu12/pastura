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
 * ## Scope: D2a ports base types + the Ordering group
 *
 * The Swift linter folds four rule groups into [lint]: producer–consumer
 * ordering (R1a/R1b/R2/R3/R4/R5/R6/R19, `+Ordering.swift`), silently-inert
 * configuration (R7/R8/R9/R17, `+Config.swift`), placeholder resolution
 * (R10–R12, `+Placeholders.swift`) and condition expressions (R13–R16,
 * `+Conditions.swift`). This D2a port carries the base types ([LintFinding],
 * [LintSeverity]), the Ordering group's traversal helpers ([PhaseRef],
 * [producerIndices], [phaseRefs], [branchPhases]), and the Ordering rules
 * themselves ([orderingFindings]). Config / Placeholders / Conditions come in
 * D2b, so [lint] currently returns only ordering findings, not the full
 * four-group union the Swift `lint(_:)` returns.
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
    public fun lint(scenario: Scenario): List<LintFinding> = orderingFindings(scenario)

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
