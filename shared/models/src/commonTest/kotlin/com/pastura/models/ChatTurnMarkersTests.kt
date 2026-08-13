package com.pastura.models

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals

/**
 * Coverage in the module that **owns** the type. `shared/engine`'s
 * `JSONResponseParserTurnMarkerTests` exercises these literals only as
 * fixtures, so a reword there would land as a truncation-behaviour failure in a
 * sibling module rather than as an edit to the pair itself.
 *
 * Values pinned byte-for-byte against Swift's `ChatTurnMarkers.chatML` — the
 * two engines share no gate on this type (its KDoc explains why it carries no
 * golden entry), so these literals are the parity anchor.
 */
class ChatTurnMarkersTests {

    @Test
    fun chatMLCarriesTheChatMLPair() {
        assertEquals("<|im_start|>", ChatTurnMarkers.chatML.start)
        assertEquals("<|im_end|>", ChatTurnMarkers.chatML.end)
    }

    /**
     * `data class` equality must discriminate on **both** fields: consumers
     * decide set membership with a single `== ChatTurnMarkers.chatML`, so a
     * pair matching ChatML's `start` alone must not collapse into it and lose
     * its distinct `end`.
     */
    @Test
    fun equalityDiscriminatesOnEachField() {
        val base = ChatTurnMarkers(start = "<a>", end = "</a>")
        assertEquals(base, ChatTurnMarkers(start = "<a>", end = "</a>"))
        assertNotEquals(base, ChatTurnMarkers(start = "<b>", end = "</a>"))
        assertNotEquals(base, ChatTurnMarkers(start = "<a>", end = "</b>"))
    }
}
