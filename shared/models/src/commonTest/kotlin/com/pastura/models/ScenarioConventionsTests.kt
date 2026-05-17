package com.pastura.models

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Tests for [ScenarioConventions.primaryField] covering all 10 [PhaseType] cases.
 *
 * LLM phases (4) return a non-null field name; code phases (6) return null.
 */
class ScenarioConventionsTests {

    @Test
    fun primaryFieldReturnsStatementForSpeakPhases() {
        assertEquals("statement", ScenarioConventions.primaryField(PhaseType.SPEAK_ALL))
        assertEquals("statement", ScenarioConventions.primaryField(PhaseType.SPEAK_EACH))
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
    fun primaryFieldReturnsNullForAllCodePhases() {
        // Code phases emit no LLM output — no primary field.
        assertNull(ScenarioConventions.primaryField(PhaseType.SCORE_CALC))
        assertNull(ScenarioConventions.primaryField(PhaseType.ASSIGN))
        assertNull(ScenarioConventions.primaryField(PhaseType.ELIMINATE))
        assertNull(ScenarioConventions.primaryField(PhaseType.SUMMARIZE))
        assertNull(ScenarioConventions.primaryField(PhaseType.CONDITIONAL))
        assertNull(ScenarioConventions.primaryField(PhaseType.EVENT_INJECT))
    }
}
