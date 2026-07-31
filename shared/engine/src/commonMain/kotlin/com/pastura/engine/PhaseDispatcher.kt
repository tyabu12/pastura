package com.pastura.engine

import com.pastura.models.PhaseType
import com.pastura.models.SimulationError
import kotlinx.serialization.serializer

/**
 * Routes [PhaseType] values to their [PhaseHandler] implementations.
 *
 * ## Scope: all 14 phase types are registered
 *
 * Wave B completed with `CONDITIONAL` (#1342), so this map now covers every
 * [PhaseType] case, matching Swift.
 *
 * Unlike Swift's `PhaseDispatcher`, this is **not** exhaustive over [PhaseType] —
 * so an unregistered phase fails at dispatch with a clear error rather than at
 * compile time. That is the same shape Swift has today (a dictionary lookup + a
 * throw), so nothing is lost; the compile-time exhaustiveness that ADR-022's
 * projection contract demands lives on the *Swift* enum switches, which are
 * unaffected by this port.
 *
 * **That throw is not dead code now that the map is complete.** It defends the
 * recurring state this migration keeps producing: a new case lands in
 * `shared/models` (needed for wire parity) *before* its handler is ported, and
 * until it is, dispatch must fail as a legible gap rather than crash. Converting
 * the lookup to an exhaustive `when` would instead hard-compile-break
 * `shared/engine` for the whole of every such window.
 *
 * Swift original: `Pastura/Pastura/Engine/PhaseDispatcher.swift`.
 *
 * @param handlers **Test seam.** Production always uses the default — the two
 *   construction sites are `SimulationEngine`'s `RunLoop` and the tests. Injecting
 *   a partial map is the only way to reach the throw arm below (and, through it,
 *   [serialName]) now that every real [PhaseType] resolves; without it the
 *   negative control for the error contract would be unreachable and its test
 *   would pass vacuously. Registration itself must still be asserted against a
 *   default-constructed dispatcher.
 */
internal class PhaseDispatcher(
    private val handlers: Map<PhaseType, PhaseHandler> = defaultHandlers(),
) {

    /**
     * The handler for [phaseType].
     *
     * @throws SimulationException wrapping [SimulationError.ScenarioValidationFailed]
     *   when no handler is registered. The message names the phase so a registration
     *   gap reads as a gap rather than as a mystery.
     */
    fun handler(phaseType: PhaseType): PhaseHandler =
        handlers[phaseType] ?: throw SimulationException(
            SimulationError.ScenarioValidationFailed(
                message = "No handler registered for phase type: ${phaseType.serialName()}",
            ),
        )
}

/**
 * The full production handler registration — one entry per [PhaseType].
 *
 * A function, not a shared constant, so each dispatcher keeps constructing its own
 * handler instances exactly as it did before the seam was added.
 */
private fun defaultHandlers(): Map<PhaseType, PhaseHandler> = mapOf(
    PhaseType.SPEAK_ALL to SpeakAllHandler(),
    PhaseType.ELIMINATE to EliminateHandler(),
    PhaseType.SUMMARIZE to SummarizeHandler(),
    PhaseType.ASSIGN to AssignHandler(),
    PhaseType.EVENT_INJECT to EventInjectHandler(),
    PhaseType.SCORE_CALC to ScoreCalcHandler(),
    PhaseType.RELATIONSHIP_UPDATE to RelationshipUpdateHandler(),
    PhaseType.REFLECT to ReflectHandler(),
    PhaseType.VOTE to VoteHandler(),
    PhaseType.WHISPER to WhisperHandler(),
    PhaseType.CHOOSE to ChooseHandler(),
    PhaseType.SPEAK_EACH to SpeakEachHandler(),
    PhaseType.NARRATE to NarrateHandler(),
    PhaseType.CONDITIONAL to ConditionalHandler(),
)

/**
 * The phase type's YAML/wire name (`speak_all`), not its Kotlin case name
 * (`SPEAK_ALL`).
 *
 * `internal` rather than file-private so [ConditionalHandler] can build its own
 * branch-rejection message from the same source — both messages interpolate what
 * Swift writes as `phaseType.rawValue`, and deriving them separately is how the two
 * drift.
 *
 * Swift's message interpolates `phaseType.rawValue`, so this keeps the two
 * engines' error text aligned for a reader comparing them.
 *
 * Read from the `@SerialName` descriptor rather than derived via
 * `name.lowercase()`. The lowercase trick happens to produce the right string for
 * every case today, but only because SCREAMING_SNAKE and the wire's snake_case
 * coincide — it would silently diverge for any case whose `@SerialName` is not its
 * lowercased name. ADR-023 §7 makes `PhaseType` a single source of truth across
 * the port boundary; reading the descriptor keeps that literally true instead of
 * re-deriving it from a naming convention.
 */
internal fun PhaseType.serialName(): String =
    PhaseType.serializer().descriptor.getElementName(ordinal)
