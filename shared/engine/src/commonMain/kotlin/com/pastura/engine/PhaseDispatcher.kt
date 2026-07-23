package com.pastura.engine

import com.pastura.models.PhaseType
import com.pastura.models.SimulationError
import kotlinx.serialization.serializer

/**
 * Routes [PhaseType] values to their [PhaseHandler] implementations.
 *
 * ## Scope: the ADR-023 Stage-3 port, in progress
 *
 * **`SPEAK_ALL`, `ELIMINATE`, `SUMMARIZE`, `ASSIGN` and `EVENT_INJECT` are
 * registered.** Swift registers all 14; the remaining 9 are the mechanical bulk
 * of Stage 3 ("mechanical after the Stage-2 slice", §4), ported
 * handler-by-handler.
 *
 * Unlike Swift's `PhaseDispatcher`, this is **not** exhaustive over [PhaseType] —
 * so an unregistered phase fails at dispatch with a clear error rather than at
 * compile time. That is the same shape Swift has today (a dictionary lookup + a
 * throw), so nothing is lost; the compile-time exhaustiveness that ADR-022's
 * projection contract demands lives on the *Swift* enum switches, which are
 * unaffected by this port.
 *
 * Swift original: `Pastura/Pastura/Engine/PhaseDispatcher.swift`.
 */
internal class PhaseDispatcher {

    private val handlers: Map<PhaseType, PhaseHandler> = mapOf(
        PhaseType.SPEAK_ALL to SpeakAllHandler(),
        PhaseType.ELIMINATE to EliminateHandler(),
        PhaseType.SUMMARIZE to SummarizeHandler(),
        PhaseType.ASSIGN to AssignHandler(),
        PhaseType.EVENT_INJECT to EventInjectHandler(),
    )

    /**
     * The handler for [phaseType].
     *
     * @throws SimulationException wrapping [SimulationError.ScenarioValidationFailed]
     *   when no handler is registered — including for a phase Swift *does* support
     *   but this slice has not ported yet. The message names the phase so a
     *   Stage-3 gap reads as a gap rather than as a mystery.
     */
    fun handler(phaseType: PhaseType): PhaseHandler =
        handlers[phaseType] ?: throw SimulationException(
            SimulationError.ScenarioValidationFailed(
                message = "No handler registered for phase type: ${phaseType.serialName()}",
            ),
        )
}

/**
 * The phase type's YAML/wire name (`speak_all`), not its Kotlin case name
 * (`SPEAK_ALL`).
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
private fun PhaseType.serialName(): String =
    PhaseType.serializer().descriptor.getElementName(ordinal)
