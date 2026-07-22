package com.pastura.engine

/**
 * Returns the most human-readable description of an arbitrary [Throwable].
 *
 * The Swift original prefers `LocalizedError.errorDescription` and falls back
 * to `String(describing:)`. Kotlin has no `LocalizedError`, so the equivalent
 * mapping is **prefer [Throwable.message], else [Throwable.toString]** — the
 * `message` carries the meaningful text (mirroring how
 * [SimulationException.messageFor] renders readable text into `.message`),
 * while `toString()` prepends the class name and is only the last resort for a
 * message-less throwable.
 *
 * Landed as infra: there is **no Kotlin consumer yet**. The Engine
 * error-bridge call sites that wrap foreign errors into [SimulationError]-typed
 * strings — the analogue of the Swift wrap points — are later-Wave freight.
 *
 * Swift original: `Pastura/Pastura/Engine/ErrorReadability.swift`.
 * Ported for the ADR-023 §6 Stage-3 Engine migration (#501).
 */
internal fun readableDescription(error: Throwable): String = error.message ?: error.toString()
