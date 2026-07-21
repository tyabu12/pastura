package com.pastura.engine

import com.pastura.models.PhaseType

/**
 * The engine's capability version — the single authoritative declaration of
 * "what capabilities this build's engine can execute" (ADR-020 D1).
 *
 * This is the Kotlin realization of the ADR's `ENGINE_SCHEMA_VERSION`: the
 * constant is exposed as [current]. It is a plain **monotonic integer**, not
 * semver — the only comparison anyone performs is
 * `appVersion >= scenarioRequirement`, so ordinal semantics are all that is
 * needed.
 *
 * Engine is the correct home because bumping it is coupled to engine feature
 * additions (a new phase handler under `Engine/Phases/`, a new `ScoreCalcLogic`
 * under `Engine/ScoringLogic/`). The App layer reads the constant via
 * [isCompatible] to drive the Browse-tab grey-out gate. No dependency-rule
 * violation: the predicate reads only Models ([PhaseType]).
 *
 * ## Bump policy
 *
 * See ADR-020 §4 for the full bump policy. In short: **bump** when adding a new
 * [PhaseType] case, a new value of any by-name-parsed enum (`ScoreCalcLogic` /
 * `AssignTarget` / `PairingStrategy` / a new `conditional` `if:` token), a new
 * required property, a new top-level scalar key, or any change to the semantics
 * of an existing phase/property such that an old app produces a *different*
 * simulation. **Do not** bump for a truly inert additive-optional string swept
 * harmlessly into `extraData`.
 *
 * Swift original: `Pastura/Pastura/Engine/EngineSchemaVersion.swift`.
 */
internal object EngineSchemaVersion {
    /**
     * The current build's engine capability version. Baseline was `1` (set
     * before the first App Store release, ADR-020 §5).
     *
     * `2` — `event_inject`'s `no_repeat` opt-in (#1006). An old app that ignores
     * the key silently runs with-replacement, a *different* simulation than a
     * no_repeat-honoring app, so §4's semantic-equivalence proviso is not met and
     * the ⚠️ silent-wrong-run rule requires a bump. See ADR-020 §8.
     *
     * `3` — the `narrate` phase (#909), a new [PhaseType] case. §4's first bump
     * trigger fires directly; the D2 phase gate already greys out a `narrate`
     * scenario on an old app, and this bump is the belt-and-suspenders D3 side so
     * a scenario may also declare `min_engine_version: 3`.
     *
     * `4` — `Persona.secret` (#914). `mapPersona` reads a fixed key set and
     * silently drops unknown persona keys (persona-level keys are not swept into
     * `extraData`, which is top-level-only), so an old app runs a secret-bearing
     * scenario with every agent missing its hidden agenda — a *different*
     * simulation, with no throw and no grey-out. D2's phase gate cannot see it
     * (no new phase), so §4's ⚠️ silent-wrong-run rule requires the bump and D3 is
     * the only gate that can fire. Same shape as `2` above.
     *
     * `5` — `ScoreCalcLogic.pairwise_payoff` (ADR-027), a new by-name-parsed
     * `score_calc` logic. §4's second bump trigger fires directly. D2's phase gate
     * does not fire (no new [PhaseType]), so D3 (`min_engine_version`) is the only
     * proactive gate and D5's parse-throw is the backstop when a shared scenario
     * omits the declaration. See ADR-027 § "Blast radius".
     */
    const val current: Int = 5

    /**
     * Whether a gallery scenario described by its index metadata can be executed
     * by this build's engine (ADR-020 D2 + D3).
     *
     * Two gates, combined with AND (a scenario is compatible only if it passes
     * **both**):
     *
     * - **D2 — capability-derived (automatic).** Every phase kind in [phases]
     *   must be known to this build ([PhaseType.entries]). This is drift-proof on
     *   the client side: the entries are the build's real capability set, not a
     *   hand-maintained list. [phases] is expected to be the *fully-flattened*
     *   phase-kind set including `conditional` branch sub-phases (D2a).
     * - **D3 — declared escape hatch.** The scenario's [minEngineVersion] must not
     *   exceed [current]. This covers breaking changes invisible to D2's
     *   phase-name check (a new by-name-parsed enum value, a new required
     *   property, or a semantics-only change on a byte-identical YAML).
     *
     * Both inputs are decoded **leniently** (absent → `null`). A `null` [phases]
     * means "capability cannot be determined from the index" → D2 defers (treated
     * as unconstrained), relying on D3 and the parse-throw backstop (D5). A `null`
     * [minEngineVersion] means "unconstrained" (`0`).
     *
     * @param phases The scenario's flattened phase-kind raw values from the
     *   gallery index (`GalleryScenario.phases`), or `null` when absent.
     * @param minEngineVersion The scenario's declared minimum engine version
     *   (`GalleryScenario.min_engine_version`), or `null` when absent.
     * @return `true` when this build can execute the scenario.
     */
    fun isCompatible(phases: List<String>?, minEngineVersion: Int?): Boolean =
        passesPhaseGate(phases) && passesVersionGate(minEngineVersion)

    /**
     * D2: every listed phase kind is known to this build. `null`/empty → pass
     * (unconstrained — see [isCompatible]).
     */
    private fun passesPhaseGate(phases: List<String>?): Boolean {
        phases ?: return true
        val known = PhaseType.entries.map { it.serialName() }.toSet()
        return phases.all { it in known }
    }

    /**
     * D3: the declared requirement does not exceed the current version.
     * `null` → `0` → pass.
     */
    private fun passesVersionGate(minEngineVersion: Int?): Boolean =
        (minEngineVersion ?: 0) <= current

    /**
     * The wire raw value for this phase type.
     *
     * Read from the `@SerialName` descriptor, mirroring `PhaseDispatcher.kt`'s
     * `serialName()` — a `PhaseType.entries[ordinal].name`-based derivation would
     * silently diverge for any case whose `@SerialName` ≠ its Kotlin name.
     */
    private fun PhaseType.serialName(): String =
        PhaseType.serializer().descriptor.getElementName(ordinal)
}
