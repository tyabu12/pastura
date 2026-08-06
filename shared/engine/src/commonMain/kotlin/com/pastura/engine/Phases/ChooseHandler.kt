package com.pastura.engine

import com.pastura.models.OutputSchema
import com.pastura.models.Pairing
import com.pastura.models.PairingStrategy
import com.pastura.models.Persona
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState
import com.pastura.models.TurnOutput

/**
 * Handles `choose` phases where agents select from options.
 *
 * Supports two modes: round-robin pairing (adjacent pairs, each agent calls the
 * LLM with opponent context) or individual choice (each agent chooses
 * independently). In round-robin, an action that can't be mapped to the option
 * set drops the whole pairing via [validateAction] (see below).
 *
 * [validateAction] is the **sole** value constraint on round-robin actions: the
 * `action` field is a `.choice` in the grammar (structure-only — no value
 * enumeration; see `OutputSchema.Kind.choice` and ADR-002 §Amendment 2026-06-14,
 * #599), so the runtime check is what keeps the result within the option set. The
 * model is steered toward valid options by [PromptBuilder]'s `chooseOptionsRule`,
 * which lists them in the prompt, so a rejection is rare in practice.
 *
 * It **normalizes then canonicalizes** (ADR-021 § Amendment 2026-07-17 / #1151):
 * a case/whitespace variant like `"Betray"` folds onto the canonical `betray` and
 * scores; a genuinely off-menu action (`裏切る`, `betray!`) maps to `null` and the
 * caller drops the pairing. This replaces the pre-Amendment `options[0]` fallback,
 * which silently **fabricated** a cooperate for any off-menu answer. Individual
 * mode does not canonicalize — it writes the raw action to `lastOutputs` for
 * consumers that normalize on read (`EventReactivePayoffLogic`), inventing nothing.
 *
 * A turn-degradable LLM failure is routed through [PhaseContext.turnGate]
 * (ADR-021 D1/D2). In **round-robin**, a skipped call drops the *whole pairing* —
 * a half-real pairing (one action absent) would fabricate the missing action
 * downstream — while the partner's already-emitted `AgentOutput` and `lastOutputs`
 * still stand (consumed by `EventReactivePayoffLogic`). A **delivered-but-off-menu**
 * action drops the pairing the same way but emits
 * [SimulationEvent.ActionRejected] so the drop is observable, since the call
 * itself succeeded. In **individual** mode a skipped turn writes nothing and clears
 * the agent's stale `lastOutputs`.
 *
 * ## Sole producer of `pairings` and `PairingResult`
 *
 * `pairings` has exactly three writers in the engine, and this is the only one that
 * ever **adds** an entry: `SimulationEngine`'s per-round reset and
 * `PairwisePayoffLogic`'s post-scoring clear both only empty it. This handler is
 * likewise the only emitter of [SimulationEvent.PairingResult].
 * Three already-ported consumers read the former —
 * `PairwisePayoffLogic` (exact `payoff.when` list match), `RelationshipUpdateHandler`
 * (`action_deltas[action]` map lookup), and `SummarizeHandler` (`{agent1}` template
 * expansion) — and all three hand-inject `pairings` in their own tests, so dropping
 * the write here would compile clean and leave every one of them green while the
 * real run path scores nothing. That is why the canonical-token return of
 * [validateAction] and the append below are pinned by `ChooseHandlerTests`.
 *
 * ## State threading (Kotlin immutability)
 *
 * Swift's `callAgent` mutates an `inout state` **and** an `inout succeeded` set
 * while returning the output. Kotlin's [SimulationState] is immutable and Kotlin
 * has no `inout`, so [ChooseTurn] carries all three back and the pair loop threads
 * them off a single `current`. Each success path folds every write —
 * `lastOutputs`, `captureMood`, and (at the pair level) `pairings` — into ONE
 * `copy`; a second copy off the original would drop the first write (the
 * VoteHandler folding discipline, doubled here because a pair is two calls).
 *
 * Swift original: `Pastura/Pastura/Engine/Phases/ChooseHandler.swift`.
 */
internal class ChooseHandler : PhaseHandler {

    private val promptBuilder = PromptBuilder()

    /**
     * One round-robin member's turn outcome.
     *
     * @property state     The next state (carries the success-path writes, or the
     *   stale-`lastOutputs` clear on a skip).
     * @property output    The turn's output, or `null` when the gate skipped it.
     * @property succeeded The updated set of agents that have produced a successful
     *   turn somewhere in this phase. Returned rather than mutated because Kotlin
     *   has no `inout`; the caller must thread it, exactly like [state].
     */
    private data class ChooseTurn(
        val state: SimulationState,
        val output: TurnOutput?,
        val succeeded: Set<String>,
    )

    override suspend fun execute(context: PhaseContext, state: SimulationState): SimulationState {
        val promptTemplate = context.phase.prompt
            ?: pickLanguage(
                context.scenario.engineLanguage,
                ja = "選択してください。",
                en = "Make a choice.",
            )
        val options = context.phase.options ?: emptyList()

        return if (context.phase.pairing == PairingStrategy.ROUND_ROBIN) {
            executeRoundRobin(context, state, promptTemplate, options)
        } else {
            executeIndividual(context, state, promptTemplate)
        }
    }

    // MARK: - Round Robin

    private suspend fun executeRoundRobin(
        context: PhaseContext,
        state: SimulationState,
        promptTemplate: String,
        options: List<String>,
    ): SimulationState {
        val active = context.scenario.personas.filter { state.eliminated[it.name] != true }
        // N adjacent pairs, wrapping — each agent appears in exactly two of them.
        //
        // Two boundaries look like bugs and are neither; both are Swift-faithful and
        // load-bearing for scoring, so do NOT "fix" either into a dedupe or a guard.
        //   - 2 active agents -> (A,B) and (B,A), two MIRRORED pairings, both scored.
        //   - 1 active agent  -> (A,A), a self-pairing that double-scores through
        //     PairwisePayoffLogic. Reachable: the run loop's "fewer than 2 active"
        //     break fires at round START, so an `eliminate` phase earlier in the same
        //     round can drop the roster to 1 before this phase runs.
        // (0 active is inert — the `0 until 0` range is empty, so `% 0` never runs.)
        val pairs = active.indices.map { idx -> active[idx] to active[(idx + 1) % active.size] }

        // Agents that produced a successful turn somewhere in this phase. Each agent
        // participates in two adjacency pairs, so a skip on one call must not clear
        // a valid output the agent produced on its other call (ADR-021 D2).
        var succeeded: Set<String> = emptySet()
        var current = state

        for ((persona1, persona2) in pairs) {
            val turn1 = callAgent(persona1, persona2, context, promptTemplate, current, succeeded)
            // Thread state AND succeeded BEFORE any `continue`: the skip path returns
            // a state with the member's stale `lastOutputs` cleared, so these
            // assignments are load-bearing even when there is no output.
            current = turn1.state
            succeeded = turn1.succeeded

            val turn2 = callAgent(persona2, persona1, context, promptTemplate, current, succeeded)
            current = turn2.state
            succeeded = turn2.succeeded

            // Gate 1 — drop the whole pairing if either member skipped (ADR-021 D2):
            // a half-real pairing would fabricate the missing action downstream.
            val out1 = turn1.output ?: continue
            val out2 = turn2.output ?: continue

            // Gate 2 (ADR-021 § Amendment 2026-07-17) — the call succeeded but the
            // *action* may be off-menu. `validateAction` returns `null` for a
            // genuinely unmappable action; dropping the pairing here is honest
            // omission, where the old `options[0]` fallback fabricated a cooperate.
            // Gate 1 above runs before these calls, so a skipped turn cannot reach
            // this gate — it is required, not redundant.
            val rawAction1 = out1.action ?: ""
            val rawAction2 = out2.action ?: ""
            val action1 = validateAction(rawAction1, options)
            val action2 = validateAction(rawAction2, options)
            if (action1 == null || action2 == null) {
                // Emit which agent(s) were off-menu, carrying the raw value so the run
                // log shows what the model said. `AgentOutput` already rendered for
                // both, so this is a distinct signal, not a `TurnSkipped`.
                if (action1 == null) {
                    context.emitter(
                        SimulationEvent.ActionRejected(
                            agent = persona1.name,
                            phaseType = context.phase.type,
                            raw = rawAction1,
                        ),
                    )
                }
                if (action2 == null) {
                    context.emitter(
                        SimulationEvent.ActionRejected(
                            agent = persona2.name,
                            phaseType = context.phase.type,
                            raw = rawAction2,
                        ),
                    )
                }
                continue
            }

            // APPEND, never replace: the run loop resets `pairings` at the top of each
            // round and `PairwisePayoffLogic` clears it after scoring, so accumulation
            // is already scoped to one round's choose phase. The stored actions are the
            // CANONICAL option strings, not the raw model output — see [validateAction].
            current = current.copy(
                pairings = current.pairings + Pairing(
                    agent1 = persona1.name,
                    agent2 = persona2.name,
                    action1 = action1,
                    action2 = action2,
                ),
            )
            context.emitter(
                SimulationEvent.PairingResult(
                    agent1 = persona1.name,
                    action1 = action1,
                    agent2 = persona2.name,
                    action2 = action2,
                ),
            )
        }
        return current
    }

    /**
     * Runs one member's round-robin call through [PhaseContext.turnGate]. On success,
     * emits `AgentOutput`, records `lastOutputs`, captures mood, and adds the agent to
     * [ChooseTurn.succeeded]. On a skipped turn, emits nothing and clears the agent's
     * stale `lastOutputs` **only if it hasn't already succeeded this phase** (its other
     * pairing may hold a valid output), then returns a `null` output.
     *
     * Unlike `WhisperHandler.whisperTurn` (which reads a frozen phase-start snapshot
     * and writes nothing), this both reads and writes the threaded state: a round-robin
     * member's `lastOutputs` write is visible to the partner's prompt within the same
     * phase, matching Swift's sequential `inout` mutation.
     */
    private suspend fun callAgent(
        persona: Persona,
        opponent: Persona,
        context: PhaseContext,
        promptTemplate: String,
        state: SimulationState,
        succeeded: Set<String>,
    ): ChooseTurn {
        // Constructed per turn, matching Swift — a stateless value, cheap. The logger
        // seam is threaded from the context (Noop by default in the current run path).
        val llmCaller = LLMCaller(logger = context.logger)

        val systemPrompt = promptBuilder.buildSystemPrompt(
            scenario = context.scenario,
            persona = persona,
            phase = context.phase,
            state = state,
        )

        // Local prompt-variable map (thrown away after the prompt is built). The
        // `inject*` family mutates it in place to surface each reserved-namespace
        // `{token}` to only this agent; none of this touches persisted state.
        val variables = state.variables.toMutableMap()
        // `opponent_name` is the choose-only variable — it is what makes a round-robin
        // turn "with opponent context". Dropping it fails SILENTLY: expandTemplate
        // leaves an unknown placeholder unchanged, so the literal `{opponent_name}`
        // would reach the model with no exception and no diagnostic.
        variables["opponent_name"] = opponent.name
        variables["scoreboard"] = promptBuilder.formatScoreboard(state.scores)
        variables["conversation_log"] = promptBuilder.formatConversationLog(
            entries = state.conversationLog,
            language = context.scenario.engineLanguage,
            window = context.scenario.logWindow,
        )
        promptBuilder.injectAssigned(variables, persona.name)
        promptBuilder.injectNotes(variables, persona.name)
        promptBuilder.injectWhispers(variables, persona.name)
        promptBuilder.injectRelationships(variables, persona.name)
        promptBuilder.injectMood(variables, persona.name)
        val userPrompt = promptBuilder.expandTemplate(promptTemplate, variables)

        val output = context.turnGate.attempt(
            agent = persona.name,
            phaseType = context.phase.type,
            emitter = context.emitter,
        ) {
            llmCaller.call(
                backend = context.backend,
                system = systemPrompt,
                user = userPrompt,
                agentName = persona.name,
                phaseType = context.phase.type,
                schema = OutputSchema.from(context.phase),
                detector = context.detector,
                expectedLanguage = context.scenario.engineLanguage,
                relay = context.suspensionRelay,
                emitter = context.emitter,
            )
        } ?: return ChooseTurn(
            // Skipped (ADR-021 D2). Clear the stale prior-round output ONLY if this
            // agent has not already succeeded in this phase: it sits in two adjacency
            // pairs, and an unconditional clear would erase the valid output from its
            // other call, which `EventReactivePayoffLogic` legitimately consumes.
            state = if (succeeded.contains(persona.name)) {
                state
            } else {
                state.copy(lastOutputs = state.lastOutputs - persona.name)
            },
            output = null,
            succeeded = succeeded,
        )

        context.emitter(
            SimulationEvent.AgentOutput(
                agent = persona.name,
                output = output,
                phaseType = context.phase.type,
            ),
        )

        // Fold BOTH success-path writes into ONE `state.copy`: the choice into
        // `lastOutputs`, and captureMood (#913, a no-op unless the phase declares
        // `mood`) into a fresh `variables` copy. A second copy off the original would
        // drop the first write.
        val nextVariables = state.variables.toMutableMap()
        promptBuilder.captureMood(output, nextVariables, persona.name)
        return ChooseTurn(
            state = state.copy(
                variables = nextVariables,
                lastOutputs = state.lastOutputs + (persona.name to output),
            ),
            output = output,
            succeeded = succeeded + persona.name,
        )
    }

    // MARK: - Individual

    private suspend fun executeIndividual(
        context: PhaseContext,
        state: SimulationState,
        promptTemplate: String,
    ): SimulationState {
        var current = state

        for (persona in context.scenario.personas) {
            if (current.eliminated[persona.name] == true) continue

            // Constructed per run with the injected logger (stateless value — cheap).
            val llmCaller = LLMCaller(logger = context.logger)

            val systemPrompt = promptBuilder.buildSystemPrompt(
                scenario = context.scenario,
                persona = persona,
                phase = context.phase,
                state = current,
            )

            val variables = current.variables.toMutableMap()
            variables["scoreboard"] = promptBuilder.formatScoreboard(current.scores)
            variables["conversation_log"] = promptBuilder.formatConversationLog(
                entries = current.conversationLog,
                language = context.scenario.engineLanguage,
                window = context.scenario.logWindow,
            )
            promptBuilder.injectAssigned(variables, persona.name)
            promptBuilder.injectNotes(variables, persona.name)
            promptBuilder.injectRelationships(variables, persona.name)
            // executeIndividual omits injectWhispers (a real handler asymmetry), but
            // mood is symmetric — surfaced in every LLM phase (like injectNotes).
            promptBuilder.injectMood(variables, persona.name)
            val userPrompt = promptBuilder.expandTemplate(promptTemplate, variables)

            val output = context.turnGate.attempt(
                agent = persona.name,
                phaseType = context.phase.type,
                emitter = context.emitter,
            ) {
                llmCaller.call(
                    backend = context.backend,
                    system = systemPrompt,
                    user = userPrompt,
                    agentName = persona.name,
                    phaseType = context.phase.type,
                    schema = OutputSchema.from(context.phase),
                    detector = context.detector,
                    expectedLanguage = context.scenario.engineLanguage,
                    relay = context.suspensionRelay,
                    emitter = context.emitter,
                )
            }
            if (output == null) {
                // Skipped (ADR-021 D2): write nothing, clear any stale prior-round
                // output. Unconditional here, unlike round-robin — an individual agent
                // gets exactly one call, so there is no sibling success to protect.
                current = current.copy(lastOutputs = current.lastOutputs - persona.name)
                continue
            }

            context.emitter(
                SimulationEvent.AgentOutput(
                    agent = persona.name,
                    output = output,
                    phaseType = context.phase.type,
                ),
            )

            // The RAW action is stored, deliberately un-canonicalized: individual mode
            // has no pairing to drop, and its consumer (`EventReactivePayoffLogic`)
            // normalizes on read. Canonicalizing here would diverge from Swift.
            val nextVariables = current.variables.toMutableMap()
            promptBuilder.captureMood(output, nextVariables, persona.name)
            current = current.copy(
                variables = nextVariables,
                lastOutputs = current.lastOutputs + (persona.name to output),
            )
        }
        return current
    }

    // MARK: - Helpers

    /**
     * Maps a raw model action onto the canonical option set, or `null` when it is
     * genuinely off-menu (ADR-021 § Amendment 2026-07-17 / #1151).
     *
     * Normalize-then-canonicalize:
     * 1. Fold both sides — trim + lowercase, matching `EventReactivePayoffLogic`'s
     *    normalization — so `"Betray"` / `" betray"` match `betray` instead of dropping.
     * 2. On a match return the **canonical option string**, not the raw input: the
     *    return is load-bearing as a *token*, not just a verdict —
     *    `RelationshipUpdateHandler` looks up `action_deltas[action]` and
     *    `PairwisePayoffLogic` matches `payoff.when` rows by exact string.
     * 3. `null` only on genuine non-membership; the caller drops the pairing.
     *
     * `options.isEmpty() -> return action` is preserved: an options-less round-robin
     * `choose` has nothing to canonicalize against, and returning `null` there would
     * drop every pairing rather than pass the raw value through unchanged (the
     * pre-Amendment behaviour for that path). Note the asymmetry with
     * `PromptBuilder.chooseOptionsRule`, which gates on `options != null` — documented
     * there, and deliberately Swift-faithful on both sides.
     *
     * `lowercase()` is locale-independent in Kotlin (unlike Java's default-locale
     * `toLowerCase()`), so this does not hit the Turkish dotless-i class of bug.
     */
    private fun validateAction(action: String, options: List<String>): String? {
        if (options.isEmpty()) return action
        val normalized = action.trim().lowercase()
        return options.firstOrNull { it.trim().lowercase() == normalized }
    }
}
