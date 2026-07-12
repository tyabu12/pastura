package com.pastura.engine

import com.pastura.models.SimulationError
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/**
 * Contract for [SimulationException], the KMP Engine's `Throwable` carrier for
 * the (non-`Throwable`) sealed [SimulationError]. See the type doc-comment for
 * why the wrapper exists (#501 Stage 2-pre).
 */
class SimulationExceptionTests {

    @Test
    fun carriesTheWrappedError() {
        val error = SimulationError.ScenarioValidationFailed("bad expr")
        val exception = SimulationException(error)
        assertEquals(error, exception.error)
    }

    @Test
    fun exposesScenarioValidationTextAsThrowableMessage() {
        val exception = SimulationException(SimulationError.ScenarioValidationFailed("bad expr"))
        assertEquals("bad expr", exception.message)
    }

    @Test
    fun isThrowableAndCatchableByType() {
        val caught = assertFailsWith<SimulationException> {
            throw SimulationException(SimulationError.ScenarioValidationFailed("x"))
        }
        assertTrue(caught.error is SimulationError.ScenarioValidationFailed)
    }
}
