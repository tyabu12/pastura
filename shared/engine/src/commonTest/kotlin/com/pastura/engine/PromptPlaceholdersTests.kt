package com.pastura.engine

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Pins [PromptPlaceholders.engineSupplied] — the coverage-guard set of
 * every `{token}` the Engine can inject at run time (#890). The count pin plus
 * the membership spot-checks make adding or removing an entry go red, keeping
 * the set authoritative against silent drift.
 */
class PromptPlaceholdersTests {

    @Test
    fun engineSuppliedHasExactlyThirteenEntries() {
        assertEquals(13, PromptPlaceholders.engineSupplied.size)
    }

    @Test
    fun engineSuppliedContainsKnownMembers() {
        assertTrue(PromptPlaceholders.engineSupplied.contains("scoreboard"))
        assertTrue(PromptPlaceholders.engineSupplied.contains("relationships"))
        assertTrue(PromptPlaceholders.engineSupplied.contains("my_whispers"))
        assertTrue(PromptPlaceholders.engineSupplied.contains("assigned_word"))
    }
}
