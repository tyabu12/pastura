package com.pastura.models

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

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
}
