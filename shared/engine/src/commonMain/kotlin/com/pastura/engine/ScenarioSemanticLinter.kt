package com.pastura.engine

import com.pastura.models.Phase
import com.pastura.models.Scenario

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
 * ## Scope: D2a ports base types + the Ordering group only
 *
 * The Swift linter folds four rule groups into [lint]: producer–consumer
 * ordering (R1–R6, `+Ordering.swift`), silently-inert configuration
 * (R7/R8/R9/R17, `+Config.swift`), placeholder resolution (R10–R12,
 * `+Placeholders.swift`) and condition expressions (R13–R16,
 * `+Conditions.swift`). This D2a port carries only the base types
 * ([LintFinding], [LintSeverity]) plus the Ordering group's traversal helpers
 * ([PhaseRef], [producerIndices], [phaseRefs], [branchPhases]) — the Ordering
 * rules themselves land in D2a item 2 ([orderingFindings] is a stub below).
 * Config / Placeholders / Conditions come in D2b, so [lint] currently returns
 * only ordering findings, not the full four-group union the Swift `lint(_:)`
 * returns.
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

    // Producer-consumer phase-ordering rules R1-R6. Stubbed for this item;
    // D2a item 2 fills this in (ported from
    // `ScenarioSemanticLinter+Ordering.swift`'s `orderingFindings(in:)`).
    internal fun orderingFindings(scenario: Scenario): List<LintFinding> = emptyList()
    // D2a item 2 fills this in

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
