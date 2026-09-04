package com.pastura.engine

import kotlin.test.Test
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/**
 * Kotlin-side coverage for [H7CrashProbe]: the exception is ordinary Kotlin
 * control flow here. The K/N process-termination behaviour the probe relies
 * on from Swift is pinned separately by `verifyExportedThrowsAnnotations`
 * in `shared/engine/build.gradle.kts`, which asserts the exported selector
 * carries NO `error:` parameter (ADR-023 §6 S5-3 H7).
 */
class H7CrashProbeTest {
    @Test
    fun crashThrowsIllegalStateExceptionWithReasonInMessage() {
        val exception = assertFailsWith<IllegalStateException> {
            H7CrashProbe.crash("x")
        }
        assertTrue(exception.message?.contains("H7 intentional crash") == true)
        assertTrue(exception.message?.contains("x") == true)
    }
}
