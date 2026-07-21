package com.pastura.engine

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Seam-shape parity spec for [EngineLogger] / [NoopEngineLogger].
 *
 * Behavioral parity is deferred to Wave B: the Swift behavioral tests drive
 * `LLMCaller(logger:)` consumption and the unported `OSLogEngineLogger`, but
 * Kotlin `LLMCaller` does not consume the seam yet (ADR-023 §12 condition-2 seam
 * carve-out, PR0-b precedent). This spec asserts only the seam's shape: the
 * interface records what it is handed, the Noop swallows every combination, and
 * the enum case-sets stay complete.
 */
class EngineLoggerSeamTests {

    private data class Entry(
        val level: EngineLogLevel,
        val category: String,
        val message: String,
        val privacy: EngineLogPrivacy,
    )

    private class SpyEngineLogger : EngineLogger {
        val entries = mutableListOf<Entry>()
        override fun log(level: EngineLogLevel, category: String, message: String, privacy: EngineLogPrivacy) {
            entries.add(Entry(level, category, message, privacy))
        }
    }

    @Test
    fun loggerRecordsWhatItIsHanded() {
        val spy = SpyEngineLogger()
        spy.log(EngineLogLevel.WARNING, "StreamingDiag", "boom", EngineLogPrivacy.PUBLIC)
        assertEquals(
            Entry(EngineLogLevel.WARNING, "StreamingDiag", "boom", EngineLogPrivacy.PUBLIC),
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
