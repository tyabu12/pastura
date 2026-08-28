package com.pastura.engine

import com.pastura.models.Scenario
import com.pastura.models.SimulationError
import com.pastura.models.SimulationEvent
import kotlinx.coroutines.CancellationException

/**
 * The run gate: structural validation ([ScenarioValidator]) followed by the
 * semantic lint gate ([semanticLintGate], ADR-024).
 *
 * Runs before any event of the run itself is emitted — see the call site in
 * [SimulationEngine.run], which mirrors Swift's position at the top of
 * `executeSimulation`. `onEvent` is the same emitter the run uses, so a blocked
 * scenario reaches the adapter through the normal channel and the "final event
 * is always `SimulationCompleted` or `ErrorEvent`" contract still holds.
 *
 * **The catch arms are wider than Swift's, deliberately — no Swift twin.** Swift
 * catches around `validator.validate` only, because its `lint(_:)` cannot throw.
 * Kotlin has no checked exceptions, so an unchecked throw out of [lint] or the
 * validator's helpers would escape: [SimulationEngine.run]'s `launch` catches
 * only `CancellationException`, `RunLoop`'s `Throwable` catch-all does not cover
 * code placed *before* it, and the scope has no `CoroutineExceptionHandler` — on
 * Kotlin/Native that TERMINATES THE PROCESS. So the whole gate sits inside
 * `RunLoop.executePhases`' three-arm shape instead of just its validator half.
 *
 * Swift original: `Pastura/Pastura/Engine/SimulationRunner+SemanticLint.swift`.
 * Ported and wired for the ADR-023 §6 Stage-3 Engine migration (#501, D3 /
 * #1591).
 *
 * @param scenario  The scenario about to run.
 * @param validator The engine's run-scoped validator (Swift:
 *   `SimulationRunner.validator`).
 * @param onEvent   The run's event emitter.
 * @return `true` when the run may proceed. On `false` the blocking
 *   [SimulationEvent.ErrorEvent] has already been emitted.
 */
internal fun preflightGate(
    scenario: Scenario,
    validator: ScenarioValidator,
    onEvent: (SimulationEvent) -> Unit,
): Boolean = try {
    val result = validator.validate(scenario)
    for (warning in result.warnings) {
        onEvent(SimulationEvent.Summary(text = "⚠️ $warning"))
    }
    semanticLintGate(scenario, onEvent)
} catch (e: CancellationException) {
    // Must precede the Throwable arm — CancellationException IS a Throwable,
    // and swallowing it would break cancellation.
    throw e
} catch (e: SimulationException) {
    // Swift's `error as? SimulationError` branch: the structured error rides
    // through unchanged.
    onEvent(SimulationEvent.ErrorEvent(error = e.error))
    false
} catch (e: Throwable) {
    // Swift's `?? .scenarioValidationFailed(readableDescription(error))` branch.
    onEvent(
        SimulationEvent.ErrorEvent(
            error = SimulationError.ScenarioValidationFailed(message = readableDescription(e)),
        ),
    )
    false
}

/**
 * Runs the semantic linter (ADR-024) after the structural validator passes.
 *
 * [LintSeverity.ERROR] findings block the run exactly like a validation error —
 * emitted as ONE aggregated [SimulationError.ScenarioValidationFailed] whose
 * message joins their messages with `"\n"`. [LintSeverity.WARNING] findings ride
 * the same `⚠️` [SimulationEvent.Summary] channel as the validator's
 * high-inference-count warning. [LintSeverity.INFO] findings are never surfaced
 * at the run gate (they are editor-only).
 *
 * @param scenario The scenario about to run.
 * @param onEvent  The run's event emitter.
 * @return `true` when the run may proceed, `false` when an error-severity
 *   finding blocked it (the error event has already been emitted).
 */
internal fun semanticLintGate(
    scenario: Scenario,
    onEvent: (SimulationEvent) -> Unit,
): Boolean {
    // The linter is a stateless value, so it is built here rather than plumbed
    // through the engine's parameter list.
    val findings = ScenarioSemanticLinter().lint(scenario)
    val lintErrors = findings.filter { it.severity == LintSeverity.ERROR }
    if (lintErrors.isNotEmpty()) {
        onEvent(
            SimulationEvent.ErrorEvent(
                error = SimulationError.ScenarioValidationFailed(
                    message = lintErrors.joinToString(separator = "\n") { it.message },
                ),
            ),
        )
        return false
    }
    for (finding in findings.filter { it.severity == LintSeverity.WARNING }) {
        onEvent(SimulationEvent.Summary(text = "⚠️ ${finding.message}"))
    }
    return true
}
