package com.pastura.engine

/**
 * A [StreamFailureKind.SYSTEMIC] backend failure, thrown out of [LLMCaller] to abort the run
 * (ADR-021 D3).
 *
 * **The Kotlin counterpart of Swift throwing a typed `LLMError`.** `streamFailureError` in
 * `Pastura/Pastura/Engine/LLMCaller+StreamFailure.swift` returns `LLMError.notLoaded` /
 * `.invalidGrammar` *unwrapped* so the Swift turn gate cannot classify them as degradable; Kotlin
 * has no such shared error type at this layer, so it throws this instead.
 *
 * **Why not a `SimulationException`.** `TurnFailureGate.isTurnDegradable` degrades exactly
 * `SimulationException` carrying `RetriesExhausted` or `LlmGenerationFailed` — a systemic failure
 * wearing either shape would be turned into a `TurnSkipped` and the run would grind on against a
 * backend that cannot recover. Escaping as a plain [RuntimeException] is what makes the gate let it
 * through. Nothing is lost downstream: `SimulationEngine.executePhases`' existing
 * `catch (e: Throwable)` arm re-wraps it into
 * `SimulationEvent.ErrorEvent(SimulationError.LlmGenerationFailed(description = e.message ?: …))` —
 * the same event shape Swift's `SimulationRunner` catch-all produces for a typed `LLMError`.
 *
 * **Why the message carries no `"code: "` prefix.** That message is what the engine catch-all
 * copies into `LlmGenerationFailed(description)`, which reaches the user's `errorMessage`. Swift's
 * path shows only `readableDescription(error)` — no internal code — so this one must not
 * reintroduce one. [errorCode] stays available as a field for diagnostics.
 *
 * **Why `internal`.** It never crosses Kotlin/Native: it is thrown and caught entirely within
 * `commonMain`'s run loop, so no exported entry point needs a `@Throws` pin
 * (`.claude/rules/kmp-interop.md` Pattern 5).
 *
 * ⚠️ **A widened `catch` must keep letting this through.** Any handler or caller that grows a
 * `catch (e: Throwable)` / `runCatching` around an `LLMCaller.call` would swallow this and silently
 * downgrade a systemic failure back to a degraded turn — the exact defect this type exists to fix.
 * `TurnFailureGate.attempt` catches `Throwable` and rethrows on `isTurnDegradable`, which is the
 * shape to copy.
 *
 * @property errorCode The backend's diagnostic identifier (`TerminalStatus.Failed.errorCode`).
 *   Never displayed verbatim.
 * @property detail The backend's human-readable message, when it had one.
 */
internal class SystemicLLMFailure(
    val errorCode: String,
    val detail: String?,
) : RuntimeException(detail ?: errorCode)
