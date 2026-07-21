package com.pastura.models

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Tests for [ScenarioConventions.primaryField] covering all 14 [PhaseType] cases.
 *
 * LLM phases with an author-declared primary field (6: speak_all / speak_each /
 * choose / vote / reflect / whisper) return a non-null field name; the
 * remaining 8 (code phases plus Engine-fixed-schema `narrate`) return null.
 * Mirrors Swift `ScenarioConventions.primaryField(for:)`.
 */
class ScenarioConventionsTests {

    @Test
    fun primaryFieldReturnsStatementForSpeakAndWhisperPhases() {
        assertEquals("statement", ScenarioConventions.primaryField(PhaseType.SPEAK_ALL))
        assertEquals("statement", ScenarioConventions.primaryField(PhaseType.SPEAK_EACH))
        // whisper is a private utterance that reuses the statement field.
        assertEquals("statement", ScenarioConventions.primaryField(PhaseType.WHISPER))
    }

    @Test
    fun primaryFieldReturnsActionForChoose() {
        assertEquals("action", ScenarioConventions.primaryField(PhaseType.CHOOSE))
    }

    @Test
    fun primaryFieldReturnsVoteForVote() {
        assertEquals("vote", ScenarioConventions.primaryField(PhaseType.VOTE))
    }

    @Test
    fun primaryFieldReturnsNoteForReflect() {
        assertEquals("note", ScenarioConventions.primaryField(PhaseType.REFLECT))
    }

    @Test
    fun primaryFieldReturnsNullForAllCodePhasesAndNarrate() {
        // Code phases emit no LLM output — no primary field.
        assertNull(ScenarioConventions.primaryField(PhaseType.SCORE_CALC))
        assertNull(ScenarioConventions.primaryField(PhaseType.ASSIGN))
        assertNull(ScenarioConventions.primaryField(PhaseType.ELIMINATE))
        assertNull(ScenarioConventions.primaryField(PhaseType.SUMMARIZE))
        assertNull(ScenarioConventions.primaryField(PhaseType.CONDITIONAL))
        assertNull(ScenarioConventions.primaryField(PhaseType.EVENT_INJECT))
        assertNull(ScenarioConventions.primaryField(PhaseType.RELATIONSHIP_UPDATE))
        // narrate is an LLM phase but its schema is Engine-fixed, not author-declared.
        assertNull(ScenarioConventions.primaryField(PhaseType.NARRATE))
    }

    // ── thoughtField (PR0-b) ────────────────────────────────────────────

    @Test
    fun thoughtFieldMirrorsSwift() {
        // vote's secondary thought field is `reason`; every other schema-bearing
        // LLM phase uses `inner_thought`.
        assertEquals("reason", ScenarioConventions.thoughtField(PhaseType.VOTE))
        assertEquals("inner_thought", ScenarioConventions.thoughtField(PhaseType.SPEAK_ALL))
        assertEquals("inner_thought", ScenarioConventions.thoughtField(PhaseType.SPEAK_EACH))
        assertEquals("inner_thought", ScenarioConventions.thoughtField(PhaseType.CHOOSE))
        assertEquals("inner_thought", ScenarioConventions.thoughtField(PhaseType.WHISPER))
        // reflect's `note` IS the private reasoning — no separate thought field.
        assertNull(ScenarioConventions.thoughtField(PhaseType.REFLECT))
        // narrate + all code phases have no secondary thought field.
        assertNull(ScenarioConventions.thoughtField(PhaseType.NARRATE))
        assertNull(ScenarioConventions.thoughtField(PhaseType.SCORE_CALC))
        assertNull(ScenarioConventions.thoughtField(PhaseType.ASSIGN))
        assertNull(ScenarioConventions.thoughtField(PhaseType.ELIMINATE))
        assertNull(ScenarioConventions.thoughtField(PhaseType.SUMMARIZE))
        assertNull(ScenarioConventions.thoughtField(PhaseType.CONDITIONAL))
        assertNull(ScenarioConventions.thoughtField(PhaseType.EVENT_INJECT))
        assertNull(ScenarioConventions.thoughtField(PhaseType.RELATIONSHIP_UPDATE))
    }

    // ── decoratePrimary (PR0-b) ─────────────────────────────────────────

    @Test
    fun decoratePrimaryArrowsOnlyVote() {
        assertEquals("→ Bob", ScenarioConventions.decoratePrimary("Bob", PhaseType.VOTE))
        // Every non-vote phase returns the value unchanged.
        assertEquals("cooperate", ScenarioConventions.decoratePrimary("cooperate", PhaseType.CHOOSE))
        assertEquals("Hello.", ScenarioConventions.decoratePrimary("Hello.", PhaseType.SPEAK_ALL))
        assertEquals("note", ScenarioConventions.decoratePrimary("note", PhaseType.REFLECT))
    }

    // ── isValidFieldName (PR0-b) ────────────────────────────────────────

    @Test
    fun isValidFieldNameAcceptsAsciiIdentifiers() {
        assertTrue(ScenarioConventions.isValidFieldName("statement"))
        assertTrue(ScenarioConventions.isValidFieldName("inner_thought"))
        assertTrue(ScenarioConventions.isValidFieldName("field1"))
        assertTrue(ScenarioConventions.isValidFieldName("a_1"))
        assertTrue(ScenarioConventions.isValidFieldName("A"))
    }

    @Test
    fun isValidFieldNameRejectsNonAsciiAndBadStarts() {
        // Empty / leading non-letter.
        assertFalse(ScenarioConventions.isValidFieldName(""))
        assertFalse(ScenarioConventions.isValidFieldName("1field"))
        assertFalse(ScenarioConventions.isValidFieldName("_field"))
        assertFalse(ScenarioConventions.isValidFieldName("-field"))
        // Non-ASCII first char (Kotlin `Char.isLetter()` would accept these).
        assertFalse(ScenarioConventions.isValidFieldName("あ"))
        assertFalse(ScenarioConventions.isValidFieldName("éclair"))
        // Non-ASCII LETTER in the tail.
        assertFalse(ScenarioConventions.isValidFieldName("fiéld"))
        // Non-ASCII DIGIT in the tail — the case that distinguishes an ASCII
        // digit gate from a naive `Char.isDigit()` (Unicode-true): Arabic-Indic
        // and fullwidth digits must be rejected.
        assertFalse(ScenarioConventions.isValidFieldName("a٥"))
        assertFalse(ScenarioConventions.isValidFieldName("a５"))
    }
}
