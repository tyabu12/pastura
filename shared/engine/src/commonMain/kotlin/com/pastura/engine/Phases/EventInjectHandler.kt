package com.pastura.engine

import com.pastura.models.AnyCodableValue
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState
import kotlin.random.Random

/**
 * Handles `event_inject` phases — probabilistically injects a random
 * string from [com.pastura.models.Scenario.extraData] into
 * [SimulationState.variables].
 *
 * Behavior:
 * - Resolves `Phase.source` against `Scenario.extraData`. The expected
 *   shape is [AnyCodableValue.ArrayValue] of `String`, or
 *   [AnyCodableValue.ArrayOfDictionariesValue] of `{ text, favors }` mappings
 *   (#931) — dict entries additionally write a companion "favored action"
 *   variable (`<as>__favors`) read by `EventReactivePayoffLogic`. Other shapes
 *   are surfaced as a [SimulationEvent.Summary] warning so curators can fix the
 *   YAML; the variable is still written as the empty string so subsequent prompt
 *   expansion never hits a missing key.
 * - Rolls `Random.nextDouble() < probability`. Strict `<` against the half-open
 *   range gives the boundary semantics curators expect: `probability = 0.0`
 *   never fires, `probability = 1.0` always fires (since `nextDouble()` can
 *   return 0.0 but never 1.0).
 * - On miss (roll failed, source missing, or source empty), writes the empty
 *   string to `state.variables[as]` and emits [SimulationEvent.EventInjected]
 *   with `event = null`. The empty-string write — rather than leaving the key
 *   absent — prevents a previous round's value from "ghosting" into the next
 *   prompt and keeps `PromptBuilder`'s substitution well-defined.
 * - On hit, picks a random element and writes it to `state.variables[as]`,
 *   emitting [SimulationEvent.EventInjected] with the chosen text.
 * - `no_repeat: true` (#1006) draws **without replacement** across the run:
 *   already-drawn events are tracked per variable in [SimulationState.drawnEvents]
 *   and the pick is taken from the remainder, resetting to the full pool once
 *   every entry has been drawn. Default is with-replacement. A miss never
 *   consumes the pool. Identical-text entries collapse in the drawn `Set`, so a
 *   curator relying on strict no-repeat should keep event texts distinct.
 *
 * RNG is not injected. The probability boundaries (0.0 / 1.0) make the fire/miss
 * decision deterministically testable, and a single-element `source` makes the
 * `random()` pick deterministic too — matching the project's pattern in
 * `AssignHandler` (which also uses `random()` / `Random.nextInt` directly without
 * injection).
 *
 * A code phase — it never touches [PhaseContext.turnGate] (no LLM turn), matching
 * Swift, where the code phases ignore it too.
 *
 * **No `state: inout`.** Kotlin [SimulationState] is an immutable `data class`, so
 * this RETURNS the next state via `state.copy(...)` rather than mutating in place.
 * A handler that builds a `.copy` but returns the original `state` compiles
 * cleanly and silently drops the change — every path below returns the state it
 * actually mutated.
 *
 * Swift original: `Pastura/Pastura/Engine/Phases/EventInjectHandler.swift`.
 */
internal class EventInjectHandler : PhaseHandler {

    companion object {
        /**
         * Default variable name written when `Phase.eventVariable` is `null`.
         *
         * Referenced by `ScoreCalcHandler`/`EventReactivePayoffLogic` and tests so
         * producer and consumer share the same canonical name.
         */
        const val defaultVariableName: String = "current_event"

        /**
         * Suffix convention for the companion "favored action" variable written
         * alongside a dict-shaped event (`{ text, favors }`).
         * `EventReactivePayoffLogic` reads it back via the same convention so the
         * producer and consumer never drift. See #931.
         */
        fun favoredVariableName(eventVariable: String): String = "${eventVariable}__favors"
    }

    /** A normalized event entry: display `text` and an optional `favors` tag. */
    private data class ChosenEntry(val text: String, val favors: String?)

    override suspend fun execute(context: PhaseContext, state: SimulationState): SimulationState {
        val variableName = context.phase.eventVariable ?: defaultVariableName
        val favoredName = favoredVariableName(variableName)
        val probability = context.phase.probability ?: 1.0
        val sourceKey = context.phase.source ?: ""

        // Normalize the source into (text, favors?) entries. A plain [String]
        // source yields null favors (unchanged #256 behavior, no companion var);
        // a [[String: String]] source carries the optional `favors` tag (#931).
        // `carriesFavors` gates every companion-var write so a plain-string
        // scenario never grows a new variable — existing scenarios unaffected.
        val events: List<ChosenEntry>
        val carriesFavors: Boolean
        when (val source = context.scenario.extraData[sourceKey]) {
            is AnyCodableValue.ArrayValue -> {
                events = source.value.map { ChosenEntry(text = it, favors = null) }
                carriesFavors = false
            }
            is AnyCodableValue.ArrayOfDictionariesValue -> {
                events = source.value.map { ChosenEntry(text = it["text"] ?: "", favors = it["favors"]) }
                carriesFavors = true
            }
            else -> {
                // Missing-key / wrong-shape (StringValue / DictionaryValue / null)
                // is curator-fixable so we surface a Summary warning rather than
                // throwing — the simulation continues with the variable set to ""
                // so downstream prompts don't break.
                if (sourceKey.isNotEmpty()) {
                    context.emitter(
                        SimulationEvent.Summary(
                            text = "⚠️ event_inject: source '$sourceKey' " +
                                "not found or not a list of events — no event injected this round.",
                        ),
                    )
                }
                context.emitter(SimulationEvent.EventInjected(event = null))
                return state.copy(variables = state.variables + (variableName to ""))
            }
        }

        // Empty list: same observable shape as a probability miss. Curator may
        // intend to disable injection by clearing the list mid-development.
        if (events.isEmpty()) {
            return miss(context, state, variableName, favoredName, carriesFavors)
        }

        // Strict `<` with `[0.0, 1.0)` gives the documented boundary semantics:
        //   probability = 0.0 → roll < 0.0 is always false → never fires
        //   probability = 1.0 → roll < 1.0 is always true  → always fires
        // (`<=` would allow `probability = 0.0` to occasionally fire when
        // RNG returns exactly 0.0.)
        val roll = Random.nextDouble()
        if (roll >= probability) {
            return miss(context, state, variableName, favoredName, carriesFavors)
        }

        // `no_repeat` (#1006) draws from the not-yet-drawn remainder and records
        // the pick; the default path keeps plain with-replacement selection.
        // `List.random()` on a non-empty list always returns an element — the
        // guard above guarantees `events.isNotEmpty()`. Both branches funnel the
        // chosen entry through the SAME variable / favored-var writes below, so
        // dict-shaped `{text,favors}` scoring (#931) is preserved regardless of
        // draw mode.
        val (chosen, afterPick) =
            if (context.phase.noRepeat == true) {
                pickWithoutRepeat(events, variableName, state)
            } else {
                events.random() to state
            }

        var variables = afterPick.variables + (variableName to chosen.text)
        // Write "" (not absent) for a dict entry with no `favors` tag, so an
        // earlier round's favored action never ghosts into `event_reactive`.
        if (carriesFavors) {
            variables = variables + (favoredName to (chosen.favors ?: ""))
        }
        context.emitter(SimulationEvent.EventInjected(event = chosen.text))
        return afterPick.copy(variables = variables)
    }

    /**
     * A miss writes "" to BOTH the event var and (for dict sources) the favored
     * var, so neither a prior round's event nor its favored action ghosts into
     * this round's prompt or `event_reactive` scoring, and emits
     * [SimulationEvent.EventInjected] with `event = null`.
     */
    private fun miss(
        context: PhaseContext,
        state: SimulationState,
        variableName: String,
        favoredName: String,
        carriesFavors: Boolean,
    ): SimulationState {
        var variables = state.variables + (variableName to "")
        if (carriesFavors) {
            variables = variables + (favoredName to "")
        }
        context.emitter(SimulationEvent.EventInjected(event = null))
        return state.copy(variables = variables)
    }

    /**
     * Draws an event not yet chosen this run (`no_repeat`), recording the pick in
     * `state.drawnEvents[variableName]`. When every entry has already been drawn
     * the pool is reset and a fresh full draw is taken — a late repeat is
     * preferable to blanking the variable mid-scenario (#1006). `events` is
     * guaranteed non-empty by the caller.
     *
     * Because [SimulationState] is immutable, this returns BOTH the chosen entry
     * and the state carrying the updated `drawnEvents` — a caller that keeps the
     * chosen entry but drops the returned state silently fails to record the
     * pick, so no_repeat would repeat.
     */
    private fun pickWithoutRepeat(
        events: List<ChosenEntry>,
        variableName: String,
        state: SimulationState,
    ): Pair<ChosenEntry, SimulationState> {
        var drawn = state.drawnEvents[variableName] ?: emptySet()
        var remaining = events.filter { it.text !in drawn }
        if (remaining.isEmpty()) {
            // Pool exhausted — reset so the next draw sees the full list again.
            drawn = emptySet()
            remaining = events
        }
        val chosen = remaining.random()
        val updatedDrawn = state.drawnEvents + (variableName to (drawn + chosen.text))
        return chosen to state.copy(drawnEvents = updatedDrawn)
    }
}
