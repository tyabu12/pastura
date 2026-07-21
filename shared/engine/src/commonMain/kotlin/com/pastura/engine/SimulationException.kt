package com.pastura.engine

import com.pastura.models.SimulationError

/**
 * A [Throwable] carrier for a [SimulationError] so the KMP Engine port can
 * `throw` a structured error value across its pure-logic call stack.
 *
 * **Why this exists:** Kotlin's [SimulationError] (in `shared/models`) is a
 * `@Serializable sealed class`, deliberately NOT a `Throwable` — it is the wire
 * shape shared with Swift, where `SimulationError` gains `Error` conformance
 * only via a `LocalizedError` extension the Models layer omits. That type's
 * doc-comment sanctions wrapping it "in a Kotlin `Throwable` subclass at [the
 * Engine] layer" when the Engine needs to throw; this is that wrapper.
 *
 * **Provisional scope (#501 Stage 2-pre).** Introduced by the
 * `ConditionEvaluator` port — the first engine logic to throw a
 * [SimulationError]. ADR-023 §6 scopes this PR as a "tooling shakedown", NOT the
 * Stage-2 GO/NO-GO gate, so the shape of this wrapper is **interim**: the durable
 * throw-convention (which cases wrap, whether the 1:1 error→exception mapping
 * holds) is ratified at the Stage-2 gate / Stage 3 once the full engine
 * throw-surface is known. Today only [SimulationError.ScenarioValidationFailed]
 * is thrown through it.
 *
 * The message mapping is a no-`else` exhaustive `when` over the sealed
 * hierarchy on purpose: a new [SimulationError] case compile-breaks here,
 * forcing a deliberate decision rather than silently defaulting.
 *
 * @property error the structured error carried across the throw boundary.
 */
public class SimulationException(
    public val error: SimulationError,
) : RuntimeException(messageFor(error)) {

    private companion object {
        private fun messageFor(error: SimulationError): String =
            when (error) {
                is SimulationError.ScenarioValidationFailed -> error.message
                is SimulationError.LlmGenerationFailed -> error.description
                is SimulationError.JsonParseFailed -> "JSON parse failed: ${error.raw}"
                SimulationError.RetriesExhausted -> "LLM retries exhausted"
                SimulationError.ModelNotLoaded -> "LLM model not loaded"
                SimulationError.Cancelled -> "Simulation cancelled"
                is SimulationError.TurnFailureLimitReached ->
                    "Simulation stopped: ${error.consecutiveCount} consecutive turns " +
                        "failed to get a response from the model"
            }
    }
}
