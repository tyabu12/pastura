package com.pastura.models

import kotlinx.serialization.Serializable

/**
 * A single row of a `pairwise_payoff` scoring table (ADR-027).
 *
 * [`when`] is matched **positionally** against `Pairing.action1` / `action2`;
 * [points] awards `[agent1, agent2]`. Both are two-element lists — the
 * `ScenarioLoader` rejects any other arity at parse time, and
 * `PairwisePayoffLogic` additionally guards defensively. A pairing matching
 * no row scores nothing (the engine never invents a verdict).
 *
 * The payoff table is authored in scenario YAML rather than compiled into
 * code, so chicken / stag-hunt variants and localized option tokens
 * (`[協力, 裏切り]`) become writable without an engine change. See ADR-027.
 *
 * Kotlin port of `Pastura/Pastura/Models/PayoffRule.swift`.
 *
 * **Wire-key convention:** `when` is a Kotlin hard keyword, so the property is
 * backtick-escaped; its serial name is still `"when"`, matching Swift `Codable`'s
 * default key. Same camelCase-default convention as [Phase] / [SimulationState].
 */
@Serializable
public data class PayoffRule(
    /**
     * The pair of actions this row matches, positional against
     * `Pairing.action1` / `action2` (e.g. `["cooperate", "betray"]`).
     */
    public val `when`: List<String>,
    /**
     * The points awarded, positional against `Pairing.agent1` / `agent2`
     * (e.g. `[0, 5]` — agent1 gets 0, agent2 gets 5).
     */
    public val points: List<Int>,
)
