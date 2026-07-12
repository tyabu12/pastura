package com.pastura.models

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Tests for [ScenarioSourceType] — confirms the canonical gallery-source
 * string constant survives Kotlin's `const val` lowering and matches the
 * Swift source-of-truth ("gallery").
 */
class ScenarioSourceTests {

    @Test
    fun galleryConstantMatchesSwiftLiteral() {
        assertEquals("gallery", ScenarioSourceType.GALLERY)
    }
}
