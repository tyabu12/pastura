package com.pastura.engine

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Seam-shape parity spec for [EngineLogger] / [NoopEngineLogger].
 *
 * Behavioral parity is deferred to Wave B: the Swift behavioral tests drive the
 * unported `OSLogEngineLogger`. Kotlin `LLMCaller` does consume the seam
 * (`LLMCaller(logger = …)`, B0b), and `SimulationEngine(logger = …)` now threads it
 * through `RunLoop` into every top-level [PhaseContext] (#1603, pinned end-to-end
 * by [SimulationEngineSeamInjectionTests]). This spec asserts only the seam's
 * shape: the interface records what it is handed, the Noop swallows every
 * combination, and the enum case-sets stay complete.
 */
class EngineLoggerSeamTests {

    @Test
    fun loggerRecordsWhatItIsHanded() {
        val spy = SpyEngineLogger()
        spy.log(EngineLogLevel.WARNING, "StreamingDiag", "boom", EngineLogPrivacy.PUBLIC)
        assertEquals(
            SpyEngineLogger.Entry(EngineLogLevel.WARNING, "StreamingDiag", "boom", EngineLogPrivacy.PUBLIC),
            spy.entries.single(),
        )
    }

    @Test
    fun noopHandlesAllLevelPrivacyCombos() {
        // Mirrors Swift's osLogAdapterHandlesAllLevelPrivacyCombos smoke, against
        // NoopEngineLogger: every level×privacy pair is callable without throwing.
        val noop = NoopEngineLogger()
        for (level in EngineLogLevel.entries) {
            for (privacy in EngineLogPrivacy.entries) {
                noop.log(level, "StreamingDiag", "msg", privacy)
            }
        }
    }

    @Test
    fun enumCaseSetsAreComplete() {
        // Perturbation target: an added/removed case flips these counts.
        assertEquals(3, EngineLogLevel.entries.size)
        assertEquals(2, EngineLogPrivacy.entries.size)
    }
}
