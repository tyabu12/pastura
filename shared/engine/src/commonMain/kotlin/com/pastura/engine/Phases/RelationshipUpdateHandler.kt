package com.pastura.engine

import com.pastura.models.Persona
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json

/**
 * Handles `relationship_update` phases — a zero-inference code phase that
 * deterministically maintains a per-agent affinity matrix and injects a
 * natural-language summary into each agent's prompt (#910).
 *
 * Signals are read from state the surrounding phases already populated:
 * - **Votes**: `state.lastOutputs[voter].vote` (who voted for whom). Applied
 *   with the `vote_against` delta on the *target's* view of the voter.
 * - **Choose actions**: `state.pairings` (`action1` / `action2`). Applied with
 *   the `action_deltas` map on each partner's view of the other.
 *
 * **Ordering constraints** (documented, not enforced — a violation is a silent
 * no-op, not an error):
 * - Place this phase *after* the vote / choose phase that produces its signals
 *   and *before* `score_calc` — `PrisonersDilemmaLogic` clears `state.pairings`
 *   after scoring, so a relationship_update placed after it sees no actions.
 * - A `lastOutputs`-writing LLM phase (speak / vote / choose) between a vote and
 *   this phase overwrites `lastOutputs[voter].vote`, losing the vote signal;
 *   `reflect` / `whisper` do NOT write `lastOutputs`, so they are safe to
 *   interleave. When neither a vote nor a pairing signal is present the handler
 *   emits a `.debug` diagnostic so a misordered scenario is discoverable.
 *
 * The raw matrix accumulates across rounds in the reserved `relationships_raw_<name>`
 * `state.variables` key (JSON); the prose summary lands in `relationships_<name>`
 * (surfaced to only that agent via `PromptBuilder.injectRelationships`). Eliminated
 * agents are skipped as perceivers — they neither act nor receive an injected summary.
 *
 * **No `state: inout`.** Kotlin [SimulationState] is an immutable `data class`, so
 * [execute] builds the affinity matrix in a LOCAL `MutableMap` (mutating a local is
 * fine — it is not `SimulationState`) and RETURNS `state.copy(variables = ...)`. The
 * two apply-helpers keep Swift's side-effecting design over that local matrix, which
 * is what makes the "evaluate BOTH before combining" ordering below meaningful — see
 * [applyVotes] / [applyActions] and the regression it guards.
 *
 * Swift original: `Pastura/Pastura/Engine/Phases/RelationshipUpdateHandler.swift`.
 * Ported for the ADR-023 Stage-3 Engine migration (#501).
 */
internal class RelationshipUpdateHandler : PhaseHandler {

    override suspend fun execute(context: PhaseContext, state: SimulationState): SimulationState {
        val active = context.scenario.personas.filter { state.eliminated[it.name] != true }
        val activeNames = active.map { it.name }.toSet()

        // Seed from the accumulated matrix so scores persist across rounds. The
        // matrix is a LOCAL mutable map — NOT `SimulationState` — so the apply
        // helpers may mutate it in place; only the final `state.copy` below crosses
        // the immutability boundary.
        val matrix: MutableMap<String, MutableMap<String, Int>> = mutableMapOf()
        for (persona in active) {
            val row = decodeRow(state.variables["relationships_raw_${persona.name}"])
            if (row.isNotEmpty()) matrix[persona.name] = row.toMutableMap()
        }

        // Evaluate BOTH before combining — each mutates `matrix`, so a
        // short-circuiting `||` would drop the action signal whenever a vote signal
        // is also present (a phase may declare both rules; e.g. choose -> vote ->
        // relationship_update leaves pairings AND lastOutputs.vote populated).
        val sawVotes = applyVotes(context, state, activeNames, matrix)
        val sawActions = applyActions(context, state, activeNames, matrix)
        val sawSignal = sawVotes || sawActions

        if (!sawSignal) {
            // Most likely a placement mistake: this phase ran with no fresh vote /
            // pairing signal in state (e.g. after `score_calc` cleared pairings, or
            // with no preceding vote/choose this round). Not user content.
            context.logger.log(
                level = EngineLogLevel.DEBUG,
                category = "RelationshipUpdate",
                message = "relationship_update found no vote/pairing signal — check phase ordering",
                privacy = EngineLogPrivacy.PUBLIC,
            )
        }

        val variables = persist(
            active = active, activeNames = activeNames, matrix = matrix,
            language = context.scenario.engineLanguage, variables = state.variables,
        )
        context.emitter(SimulationEvent.RelationshipUpdate(relationships = matrix))
        return state.copy(variables = variables)
    }

    /**
     * Applies the `vote_against` delta for every voter->target pair readable from
     * `lastOutputs`. Returns `true` if any vote input was present.
     */
    private fun applyVotes(
        context: PhaseContext,
        state: SimulationState,
        activeNames: Set<String>,
        matrix: MutableMap<String, MutableMap<String, Int>>,
    ): Boolean {
        var sawVote = false
        for (voter in activeNames) {
            val target = state.lastOutputs[voter]?.vote
            if (target.isNullOrEmpty()) continue
            sawVote = true
            // Self-votes and hallucinated / eliminated targets carry no affinity.
            if (target == voter || !activeNames.contains(target)) continue
            val delta = context.phase.voteAgainst ?: continue
            // The target grows wary of whoever voted against them.
            val row = matrix.getOrPut(target) { mutableMapOf() }
            row[voter] = (row[voter] ?: 0) + delta
        }
        return sawVote
    }

    /**
     * Applies the `action_deltas` map for every choose pairing. Each partner's
     * view of the other moves by the delta for the other's action. Returns
     * `true` if any pairing input was present.
     */
    private fun applyActions(
        context: PhaseContext,
        state: SimulationState,
        activeNames: Set<String>,
        matrix: MutableMap<String, MutableMap<String, Int>>,
    ): Boolean {
        if (state.pairings.isEmpty()) return false
        val deltas = context.phase.actionDeltas ?: return true
        for (pairing in state.pairings) {
            if (!activeNames.contains(pairing.agent1) || !activeNames.contains(pairing.agent2)) continue
            val delta2 = pairing.action2?.let { deltas[it] }
            if (delta2 != null) {
                val row = matrix.getOrPut(pairing.agent1) { mutableMapOf() }
                row[pairing.agent2] = (row[pairing.agent2] ?: 0) + delta2
            }
            val delta1 = pairing.action1?.let { deltas[it] }
            if (delta1 != null) {
                val row = matrix.getOrPut(pairing.agent2) { mutableMapOf() }
                row[pairing.agent1] = (row[pairing.agent1] ?: 0) + delta1
            }
        }
        return true
    }

    /**
     * Writes each active perceiver's non-empty row back as the accumulated raw
     * matrix plus its prose summary, returning the updated `variables` map.
     *
     * The raw matrix keeps the full history (cross-round accumulation + the event
     * payload / Phase-3 viz), but the injected prose mentions only agents still in
     * play — an eliminated agent should not surface in "you are wary of X".
     */
    private fun persist(
        active: List<Persona>,
        activeNames: Set<String>,
        matrix: Map<String, Map<String, Int>>,
        language: String,
        variables: Map<String, String>,
    ): Map<String, String> {
        val out = variables.toMutableMap()
        for (persona in active) {
            val row = matrix[persona.name]
            if (row.isNullOrEmpty()) continue
            out["relationships_raw_${persona.name}"] = encodeRow(row)
            val visibleRow = row.filterKeys { activeNames.contains(it) }
            out["relationships_${persona.name}"] = RelationshipVerbalizer.summarize(visibleRow, language)
        }
        return out
    }

    private fun encodeRow(row: Map<String, Int>): String {
        // Sorted keys for deterministic output + cross-engine parity with Swift's
        // `JSONEncoder.outputFormatting = .sortedKeys`. `Map.toSortedMap()` is
        // JVM-only (absent from commonMain), so sort the entries by hand; `toMap()`
        // yields a LinkedHashMap preserving that sorted insertion order, which the
        // default compact `Json` then emits as `{"Alice":-1,"Bob":2}`. For the
        // ASCII/BMP agent names in practice this matches Swift's `.sortedKeys`
        // byte-for-byte; the orderings can diverge only for non-BMP keys (Kotlin
        // sorts by UTF-16 code unit, Foundation by Unicode scalar), and cross-engine
        // byte-parity is not exercised yet (Data stays Swift/GRDB, ADR-023).
        val sorted = row.toList().sortedBy { it.first }.toMap()
        return runCatching { json.encodeToString(rowSerializer, sorted) }.getOrDefault("{}")
    }

    private fun decodeRow(raw: String?): Map<String, Int> {
        if (raw.isNullOrEmpty()) return emptyMap()
        return runCatching { json.decodeFromString(rowSerializer, raw) }.getOrDefault(emptyMap())
    }

    private companion object {
        private val json = Json
        private val rowSerializer = MapSerializer(String.serializer(), Int.serializer())
    }
}
