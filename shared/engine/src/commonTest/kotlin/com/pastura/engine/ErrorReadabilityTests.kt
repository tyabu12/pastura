package com.pastura.engine

import com.pastura.models.SimulationError
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Parity spec for [readableDescription] — mirrors the intent of the Swift
 * `ErrorReadabilityTests` wrap-chain cases against the Kotlin
 * `message ?: toString()` mapping. The message-present cases go red if the
 * `?:` fallback collapses to a `toString()`-always impl (which would leak the
 * class name).
 */
class ErrorReadabilityTests {

    @Test
    fun prefersMessageWhenPresent() {
        val result = readableDescription(RuntimeException("boom"))
        assertEquals("boom", result)
        // Regression guard: a `toString()`-always impl would yield
        // "...RuntimeException: boom", leaking the class name.
        assertTrue(!result.contains("Exception"))
    }

    @Test
    fun fallsBackToToStringWhenMessageIsNull() {
        val e = RuntimeException()
        val result = readableDescription(e)
        // The exact class-name string is platform-specific; assert only that
        // the `?: toString()` branch produced non-empty text equal to toString().
        assertTrue(result.isNotEmpty())
        assertEquals(e.toString(), result)
    }

    @Test
    fun wrapChainCarriesInnerSimulationErrorText() {
        val wrapped = SimulationException(SimulationError.LlmGenerationFailed("connection timeout"))
        val result = readableDescription(wrapped)
        assertTrue(result.contains("connection timeout"))
        // Regression guard: preferring `.message` strips the sealed-subtype
        // wrapper; a raw `toString()` would leak it.
        assertTrue(!result.contains("LlmGenerationFailed("))
    }
}
