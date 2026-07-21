package com.pastura.engine

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Seam-shape parity spec for [LanguageDetector].
 *
 * Behavioral parity is deferred: the Swift behavioral coverage drives
 * `NLLanguageDetector` + `LLMCaller` consumption, but no Kotlin consumer
 * threads the seam yet (unwired-seam precedent, cf. [EngineLogger]). This spec
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
