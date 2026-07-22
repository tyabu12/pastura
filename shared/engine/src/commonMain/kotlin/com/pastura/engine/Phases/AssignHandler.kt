package com.pastura.engine

import com.pastura.models.AnyCodableValue
import com.pastura.models.AssignTarget
import com.pastura.models.Persona
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState
import kotlin.random.Random

/**
 * Handles `assign` phases that distribute information to agents.
 *
 * Supports two target modes:
 * - `random_one`: one random agent gets the `minority` value, the rest get
 *   `majority` (word wolf). Per-agent [SimulationEvent.Assignment] — one per
 *   active agent, because each agent receives a different secret.
 * - `all` (default when `target` is null): all agents get the same round-indexed
 *   item from the source array. Exactly ONE [SimulationEvent.SharedAssignment] for
 *   the whole round — never N per-agent [SimulationEvent.Assignment]s (#939).
 *
 * A code phase — it never touches [PhaseContext.turnGate] (no LLM turn), matching
 * Swift, where the code phases ignore it too.
 *
 * **No `state: inout`.** Kotlin [SimulationState] is an immutable `data class`, so
 * [assignRandomOne]/[assignAll] each RETURN the next state and [execute] returns
 * the helper's result. A helper that mutates a local map copy but returns the
 * un-updated `state` compiles cleanly and silently drops every assignment — see
 * [PhaseHandler].
 *
 * Swift original: `Pastura/Pastura/Engine/Phases/AssignHandler.swift`.
 */
internal class AssignHandler : PhaseHandler {

    override suspend fun execute(context: PhaseContext, state: SimulationState): SimulationState {
        val sourceKey = context.phase.source ?: ""
        val sourceData = context.scenario.extraData[sourceKey]

        val active = context.scenario.personas.filter { state.eliminated[it.name] != true }

        // null target → ALL matches the documented default at the type's doc comment.
        return when (context.phase.target ?: AssignTarget.ALL) {
            AssignTarget.RANDOM_ONE ->
                assignRandomOne(active, sourceData, state, context.emitter)
            AssignTarget.ALL ->
                assignAll(active, sourceData, state, context.emitter)
        }
    }

    /**
     * Assigns the minority value to one random agent, majority to the rest.
     *
     * Precondition: `sourceData` is [AnyCodableValue.ArrayOfDictionariesValue].
     * `ScenarioValidator` rejects mismatched shapes upstream — the `!is` /
     * empty fall-through is a no-op safety net for scenarios constructed in tests
     * or future code paths that bypass validation.
     */
    private fun assignRandomOne(
        active: List<Persona>,
        sourceData: AnyCodableValue?,
        state: SimulationState,
        emitter: (SimulationEvent) -> Unit,
    ): SimulationState {
        if (sourceData !is AnyCodableValue.ArrayOfDictionariesValue || sourceData.value.isEmpty()) {
            return state
        }
        val topics = sourceData.value

        val topic = topics.random()
        // Mirrors Swift `Int.random(in: 0..<active.count)`; `nextInt(0)` throws on
        // empty `active`, exactly as Swift's range trap does — no guard Swift lacks.
        val wolfIdx = Random.nextInt(active.size)

        val variables = state.variables.toMutableMap()
        for ((index, persona) in active.withIndex()) {
            if (index == wolfIdx) {
                val value = topic["minority"] ?: ""
                variables["assigned_${persona.name}"] = value
                variables["wolf_name"] = persona.name
                emitter(SimulationEvent.Assignment(agent = persona.name, value = value))
            } else {
                val value = topic["majority"] ?: ""
                variables["assigned_${persona.name}"] = value
                emitter(SimulationEvent.Assignment(agent = persona.name, value = value))
            }
        }
        return state.copy(variables = variables)
    }

    /**
     * Assigns the same round-indexed item to all agents.
     *
     * Precondition: `sourceData` is [AnyCodableValue.ArrayValue] or
     * [AnyCodableValue.StringValue]. `ScenarioValidator` rejects the dictionary
     * shapes upstream — the `else` branch's empty-string fallback is a no-op safety
     * net for scenarios constructed in tests or future code paths that bypass
     * validation.
     */
    private fun assignAll(
        active: List<Persona>,
        sourceData: AnyCodableValue?,
        state: SimulationState,
        emitter: (SimulationEvent) -> Unit,
    ): SimulationState {
        val item: String = when {
            sourceData is AnyCodableValue.ArrayValue && sourceData.value.isNotEmpty() -> {
                val roundIdx = (state.currentRound - 1) % sourceData.value.size
                sourceData.value[roundIdx]
            }
            sourceData is AnyCodableValue.StringValue -> sourceData.value
            else -> ""
        }

        val variables = state.variables.toMutableMap()
        variables["assigned_topic"] = item
        for (persona in active) {
            variables["assigned_${persona.name}"] = item
        }
        // Every agent got the SAME item, so emit one shared-topic event for the
        // whole round — N per-agent Assignment events would misleadingly read as N
        // different assignments (#939). The per-persona `assigned_<name>` variables
        // above are still set so prompt expansion has each agent's copy.
        // `assignRandomOne` keeps per-agent Assignment (each gets a different secret).
        emitter(SimulationEvent.SharedAssignment(value = item))
        return state.copy(variables = variables)
    }
}
