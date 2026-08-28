package com.pastura.engine

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Seam-shape parity spec for [LanguageDetector].
 *
 * Behavioral parity is deferred: the Swift behavioral coverage drives
 * `NLLanguageDetector` + `LLMCaller` consumption, and the run path now threads
 * `SimulationEngine(detector = …)` through to every [PhaseContext] (#1603,
 * pinned end-to-end by [SimulationEngineSeamInjectionTests]) — but no Kotlin
 * implementation of the detector exists yet, cf. [EngineLogger]. This spec
 * asserts only the seam's shape via a test-local spy: the interface records the
 * text it is handed and returns whatever the implementation is told to return.
 */
class LanguageDetectorSeamTests {

    private class SpyLanguageDetector(private val canned: String?) : LanguageDetector {
        val recorded = mutableListOf<String>()
        override fun detect(text: String): String? {
            recorded.add(text)
            return canned
        }
    }

    @Test
    fun detectorRecordsTheTextItIsHanded() {
        val spy = SpyLanguageDetector(canned = "ja")
        spy.detect("こんにちは")
        assertEquals("こんにちは", spy.recorded.single())
    }

    @Test
    fun detectorReturnsWhatItIsTold() {
        assertEquals("en", SpyLanguageDetector(canned = "en").detect("hello"))
        assertEquals(null, SpyLanguageDetector(canned = null).detect("x"))
    }
}
