package com.pastura.models

import kotlinx.serialization.Serializable

/**
 * The complete mutable state of a running simulation.
 *
 * Kotlin port of `Pastura/Pastura/Models/SimulationState.swift`.
 *
 * `SimulationState` is `Serializable` from day one — Swift serialises this
 * to JSON for pause/resume persistence in the `simulations.stateJSON` DB
 * column. Agent state (scores, elimination) lives here rather than in a
 * separate agents table (see ADR-001 §4).
 *
 * **Mutability divergence from Swift:** the Swift original uses `var` on
 * every property so `SimulationRunner` and phase handlers can mutate in
 * place. Per the W2 PR-A plan (item 6 conventions), the Kotlin port uses
 * `val` and the Engine port (W3+) is expected to use `.copy(...)` for
 * state transitions. The mutation strategy itself is W3 scope.
 *
 * **Wire-key convention:** camelCase JSON keys via kotlinx default,
 * matching Swift Codable default. Same convention as [Scenario].
 *
 * @property scores          Current scores indexed by agent name.
 * @property eliminated      Elimination status indexed by agent name.
 *                           `true` means eliminated.
 * @property conversationLog Accumulated conversation log. Engine trims to
 *                           recent entries for prompts; full log preserved
 *                           in DB via `TurnRecord`.
 * @property lastOutputs     Most recent output per agent. Used for
 *                           template variable expansion in subsequent
 *                           phases.
 * @property voteResults     Vote tallies from the most recent vote phase.
 * @property pairings        Current pairings for choose phases with
 *                           round-robin strategy.
 * @property variables       Arbitrary key-value variables for template
 *                           expansion (e.g., `assigned_topic` from assign
 *                           phases).
 * @property currentRound    The current round number (1-based). Updated
 *                           by the simulation runner.
 * @property drawnEvents     Per-event-variable set of already-drawn event
 *                           strings, tracked only for `event_inject` phases
 *                           opted into `no_repeat` (draw-without-replacement,
 *                           #1006). Keyed by the event variable name; the value
 *                           is the set of chosen `text` values drawn so far.
 *                           Empty for every other scenario. The `emptyMap()`
 *                           default is the Kotlin equivalent of Swift's lenient
 *                           `decodeIfPresent(...) ?? [:]` decoder: a pre-#1006
 *                           `stateJSON` blob with no `drawnEvents` key resumes
 *                           to empty rather than failing to decode.
 */
@Serializable
public data class SimulationState(
    public val scores: Map<String, Int> = emptyMap(),
    public val eliminated: Map<String, Boolean> = emptyMap(),
    public val conversationLog: List<ConversationEntry> = emptyList(),
    public val lastOutputs: Map<String, TurnOutput> = emptyMap(),
    public val voteResults: Map<String, Int> = emptyMap(),
    public val pairings: List<Pairing> = emptyList(),
    public val variables: Map<String, String> = emptyMap(),
    public val currentRound: Int = 0,
    public val drawnEvents: Map<String, Set<String>> = emptyMap(),
) {
    public companion object {
        /**
         * Creates an initial state for the given scenario with all agents
         * at score 0 and not eliminated.
         */
        public fun initial(scenario: Scenario): SimulationState {
            val agentNames = scenario.personas.map { it.name }
            return SimulationState(
                scores = agentNames.associateWith { 0 },
                eliminated = agentNames.associateWith { false },
            )
        }
    }
}
