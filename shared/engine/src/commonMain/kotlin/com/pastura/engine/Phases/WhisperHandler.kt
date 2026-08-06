package com.pastura.engine

import com.pastura.models.OutputSchema
import com.pastura.models.Persona
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState
import com.pastura.models.TurnOutput

/**
 * Handles `whisper` phases: a secret pairwise exchange between two agents.
 *
 * Active (non-eliminated) agents are paired off in persona declaration order,
 * rotated by round so the pairings vary. Each pair runs `subRounds` exchanges;
 * an exchange is agent1 speaking then agent2 speaking. Every utterance reuses
 * the `AgentOutput` event with a reserved `whisper_to` field naming the partner,
 * so the whisper surfaces in the viewer UI / persistence exactly like any other
 * LLM output.
 *
 * Whisper content is **pair-private**: it is never appended to `conversationLog`
 * or `lastOutputs`, so other agents' prompts can't see it (mirroring
 * [ReflectHandler]'s private note). At the end of the phase each participant's
 * formatted view of their pair's exchange is written to the reserved
 * `whispers_<name>` key (overwrite semantics — latest exchange only, per the #908
 * plan). An active agent who sat out an odd-count round has their stale
 * `whispers_<name>` cleared so a later reader never sees a whisper from a round
 * they didn't participate in; eliminated agents' keys are left untouched (they are
 * simply not participants this round).
 *
 * A turn-degradable LLM failure is routed through [PhaseContext.turnGate]
 * (ADR-021 D1/D2): a skipped utterance **ends that pair's exchange early** — the
 * remaining sub-rounds are not attempted, since a partner replying to a missing
 * utterance would desync the exchange. Turns already exchanged stand and overwrite
 * `whispers_<name>` as usual; but a pair whose *first* turn was skipped produces an
 * empty transcript, and that case leaves the prior round's channels intact rather
 * than overwriting them with a header-only body (private memory persists, mirroring
 * [ReflectHandler]'s non-empty guard).
 *
 * ## State threading (Kotlin immutability)
 *
 * Swift's handler mutates an `inout` `state` in place while [whisperTurn] reads a
 * phase-start snapshot ([Run.state]) for prompt building. Kotlin's [SimulationState]
 * is immutable, so this port splits the two explicitly: `frozen` is the read-only
 * phase-start snapshot every turn's prompt is built from, and `current` threads the
 * channel / mood / sat-out writes. Each pair folds BOTH channel writes AND every
 * `captureMood` into ONE `current.copy` — a second copy off the original would drop
 * the first write (the VoteHandler folding discipline). [whisperTurn] itself writes
 * nothing to persisted state.
 *
 * Swift original: `Pastura/Pastura/Engine/Phases/WhisperHandler.swift`.
 */
internal class WhisperHandler : PhaseHandler {

    private val promptBuilder = PromptBuilder()

    /**
     * A single whisper line: [name] + spoken [statement]. [mood] is carried so
     * [execute] can persist `mood_<name>` after the pair's exchange (#913) —
     * [whisperTurn] reads a frozen snapshot and cannot write it itself. Empty when
     * the phase doesn't opt into a `mood` output field.
     */
    private data class Utterance(
        val name: String,
        val statement: String,
        val mood: String = "",
    )

    override suspend fun execute(context: PhaseContext, state: SimulationState): SimulationState {
        val active = context.scenario.personas.filter { state.eliminated[it.name] != true }
        // Fewer than two active agents → nothing to pair. Return WITHOUT any LLM call
        // or state write; in particular, do NOT clear anyone's channel here.
        if (active.size < 2) return state

        val rotated = rotate(active, state.currentRound)
        val promptTemplate = context.phase.prompt
            ?: pickLanguage(
                context.scenario.engineLanguage,
                ja = "相手にこっそり耳打ちしてください。",
                en = "Whisper privately to your partner.",
            )
        val exchanges = maxOf(1, context.phase.subRounds ?: 1)
        val language = context.scenario.engineLanguage

        // `frozen` is the phase-start snapshot every per-turn prompt reads (Swift's
        // `Run.state`): whisper never mutates the public log / outputs / scores
        // mid-phase, so it stays accurate for every pair. `current` threads the
        // channel / mood / sat-out writes.
        val frozen = state
        var current = state

        var pairIndex = 0
        while (pairIndex + 1 < rotated.size) {
            val first = rotated[pairIndex]
            val second = rotated[pairIndex + 1]
            val transcript = runPair(first, second, exchanges, context, frozen, promptTemplate)
            // Only overwrite the pair's channels when at least one utterance was
            // exchanged (ADR-021 D2): a first-turn skip yields an empty transcript, and
            // writing a header-only channel would erase the prior round's whisper
            // memory. A partial transcript (>=1 utterance) still overwrites as usual.
            // Fold BOTH channel writes AND every captureMood into ONE `current.copy` —
            // a second copy off `current` (or `state`) would drop the first write
            // (the VoteHandler folding discipline). An empty transcript writes nothing
            // (the mood loop is empty too).
            if (transcript.isNotEmpty()) {
                val vars = current.variables.toMutableMap()
                // Both members see the same exchange body, each headed by their own
                // partner-identifying line.
                vars["whispers_${first.name}"] = formatChannel(transcript, second, language)
                vars["whispers_${second.name}"] = formatChannel(transcript, first, language)
                // Persist each speaker's mood from this pair's exchange (#913).
                // Transcript order gives last-write-wins per speaker across sub_rounds;
                // captureMood's non-empty guard skips a mood-less utterance so a prior
                // round's mood isn't erased.
                for (utterance in transcript) {
                    promptBuilder.captureMood(
                        TurnOutput(fields = mapOf("mood" to utterance.mood)),
                        vars,
                        utterance.name,
                    )
                }
                current = current.copy(variables = vars)
            }
            pairIndex += 2
        }

        // Odd active count: the last rotated element sat this round out. Clear its
        // stale channel for "latest only" consistency. An eliminated agent's key is
        // left untouched — it is simply not a participant this round.
        if (rotated.size % 2 == 1) {
            val satOut = rotated.last()
            current = current.copy(variables = current.variables - "whispers_${satOut.name}")
        }
        return current
    }

    // MARK: - Pairing

    /**
     * Rotates the active list by `(round - 1)` positions so consecutive rounds draw
     * different adjacent pairs. The modulo is normalized non-negative to tolerate a
     * `round` of 0.
     */
    private fun rotate(agents: List<Persona>, round: Int): List<Persona> {
        val count = agents.size
        val offset = ((round - 1) % count + count) % count
        return agents.drop(offset) + agents.take(offset)
    }

    /**
     * Runs [exchanges] back-and-forth turns for one pair, accumulating the running
     * transcript so each speaker's prompt can reference what was said so far via
     * `{whisper_exchange}`.
     *
     * A skipped utterance ends the exchange early (ADR-021 D2): the remaining turns
     * for this pair are not attempted, so no partner replies to a missing utterance.
     * Turns already appended stand.
     */
    private suspend fun runPair(
        first: Persona,
        second: Persona,
        exchanges: Int,
        context: PhaseContext,
        frozen: SimulationState,
        promptTemplate: String,
    ): List<Utterance> {
        val transcript = mutableListOf<Utterance>()
        for (exchange in 0 until exchanges) {
            val out1 = whisperTurn(first, second, transcript, context, frozen, promptTemplate)
                ?: break
            transcript.add(
                Utterance(name = first.name, statement = out1.statement ?: "", mood = out1.fields["mood"] ?: ""),
            )
            val out2 = whisperTurn(second, first, transcript, context, frozen, promptTemplate)
                ?: break
            transcript.add(
                Utterance(name = second.name, statement = out2.statement ?: "", mood = out2.fields["mood"] ?: ""),
            )
        }
        return transcript
    }

    // MARK: - Single Turn

    /**
     * Builds one speaker's whisper prompt (from the phase-start [frozen] snapshot),
     * routes the LLM call through [PhaseContext.turnGate] (ADR-021 D1/D2), and on
     * success emits an `AgentOutput` carrying the reserved `whisper_to` field naming
     * the [partner]. Returns the attributed output, or `null` on a skipped turn (the
     * caller ends the pair's exchange early).
     *
     * Deliberately writes NOTHING to persisted state — not `conversationLog`, not
     * `lastOutputs` (a whisper is pair-private, mirroring [ReflectHandler]). The
     * channel / mood writes are folded in [execute], where the threaded `current`
     * lives; this turn reads the frozen snapshot and so cannot (and must not) write.
     */
    private suspend fun whisperTurn(
        speaker: Persona,
        partner: Persona,
        transcript: List<Utterance>,
        context: PhaseContext,
        frozen: SimulationState,
        promptTemplate: String,
    ): TurnOutput? {
        val language = context.scenario.engineLanguage
        // Constructed per turn, matching Swift — a stateless value, cheap. The logger
        // seam is threaded from the context (Noop by default in the current run path).
        val llmCaller = LLMCaller(logger = context.logger)

        val systemPrompt = promptBuilder.buildSystemPrompt(
            scenario = context.scenario,
            persona = speaker,
            phase = context.phase,
            state = frozen,
        )

        // Local prompt-variable map (thrown away after the prompt is built). The
        // `inject*` family mutates it in place to surface each reserved-namespace
        // `{token}` to only this speaker; none of this touches persisted state.
        val variables = frozen.variables.toMutableMap()
        variables["scoreboard"] = promptBuilder.formatScoreboard(frozen.scores)
        // The PUBLIC conversation log — whisper participants still see it.
        variables["conversation_log"] = promptBuilder.formatConversationLog(
            entries = frozen.conversationLog,
            language = language,
            window = context.scenario.logWindow,
        )
        variables["whisper_partner"] = partner.name
        variables["whisper_exchange"] = formatTranscript(transcript)
        promptBuilder.injectAssigned(variables, speaker.name)
        promptBuilder.injectNotes(variables, speaker.name)
        promptBuilder.injectWhispers(variables, speaker.name)
        promptBuilder.injectRelationships(variables, speaker.name)
        promptBuilder.injectMood(variables, speaker.name)
        // ALWAYS append a partner-naming context block after expanding the user
        // template: the default template never names the partner, and a custom author
        // prompt may omit {whisper_partner} / {whisper_exchange}. The template still
        // keeps those placeholders resolvable for authors who DO reference them; this
        // block guarantees the partner + running exchange reach the model regardless
        // of template content.
        val userPrompt = promptBuilder.expandTemplate(promptTemplate, variables) +
            whisperContextBlock(partner, transcript, language)

        val output = context.turnGate.attempt(
            agent = speaker.name,
            phaseType = context.phase.type,
            emitter = context.emitter,
        ) {
            llmCaller.call(
                backend = context.backend,
                system = systemPrompt,
                user = userPrompt,
                agentName = speaker.name,
                phaseType = context.phase.type,
                schema = OutputSchema.from(context.phase),
                detector = context.detector,
                expectedLanguage = context.scenario.engineLanguage,
                relay = context.suspensionRelay,
                emitter = context.emitter,
            )
        }
        // Skipped (ADR-021 D2): emit nothing; the caller ends the pair's exchange.
            ?: return null

        // Attribute the partner via the reserved `whisper_to` field. Kotlin TurnOutput
        // carries only `fields` (no Swift `rawText`), so the merge is a plain copy.
        val attributed = output.copy(fields = output.fields + ("whisper_to" to partner.name))
        context.emitter(
            SimulationEvent.AgentOutput(
                agent = speaker.name,
                output = attributed,
                phaseType = context.phase.type,
            ),
        )
        // NOT appended to `conversationLog` and NOT written to `lastOutputs`: a whisper
        // is pair-private and must never reach another agent's prompt or the public
        // last-output display (mirrors ReflectHandler).
        return attributed
    }

    // MARK: - Formatting

    /**
     * Formats the exchange body one utterance per line, mirroring
     * [PromptBuilder.formatConversationLog]'s `  Name: content` style.
     */
    private fun formatTranscript(transcript: List<Utterance>): String =
        transcript.joinToString(separator = "\n") { "  ${it.name}: ${it.statement}" }

    /**
     * A language-aware block appended to every whisper turn prompt so the model always
     * knows who its partner is — and, once the pair has spoken, what was said so far —
     * no matter what the (possibly partner-agnostic) user template contains. The
     * exchange section is omitted on the opening utterance (empty transcript) to avoid
     * an empty header.
     */
    private fun whisperContextBlock(
        partner: Persona,
        transcript: List<Utterance>,
        language: String,
    ): String {
        val partnerLine = pickLanguage(
            language,
            ja = "\n\n密談相手: ${partner.name}（この相手だけにこっそり話しかけてください）",
            en = "\n\nWhisper partner: ${partner.name} (speak privately to them only).",
        )
        if (transcript.isEmpty()) return partnerLine
        val exchangeHeader = pickLanguage(language, ja = "これまでの密談:", en = "Whisper so far:")
        return "$partnerLine\n$exchangeHeader\n${formatTranscript(transcript)}"
    }

    /**
     * A participant's stored channel view: a partner-identifying header line followed
     * by the full exchange body.
     */
    private fun formatChannel(
        transcript: List<Utterance>,
        partner: Persona,
        language: String,
    ): String {
        val header = pickLanguage(
            language,
            ja = "密談相手: ${partner.name}",
            en = "Whispering with ${partner.name}",
        )
        val body = formatTranscript(transcript)
        return if (body.isEmpty()) header else "$header\n$body"
    }
}
