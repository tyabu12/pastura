package com.pastura.models

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals

/**
 * Coverage for [ChatTurnMarkers] in the module that **owns** it. `shared/engine`'s
 * `JSONResponseParserTurnMarkerTests` exercises these literals only as fixtures,
 * so a reword there lands as a truncation-behaviour failure, not an edit to the
 * pair itself.
 *
 * Values pinned byte-for-byte against Swift's `ChatTurnMarkers.chatML` — no gate
 * enforces parity, so these literals are the anchor, symmetric with
 * `Pastura/PasturaTests/Models/ChatTurnMarkersTests.swift`.
 */
class ChatTurnMarkersTests {

    @Test
    fun chatMLCarriesTheChatMLPair() {
        assertEquals("<|im_start|>", ChatTurnMarkers.chatML.start)
        assertEquals("<|im_end|>", ChatTurnMarkers.chatML.end)
    }

    /**
     * Guards the **structural** `equals` the `data class` modifier synthesizes —
     * a change-detector for a `data class` → `class` demotion or a hand-written
     * `equals`.
     *
     * **Measured, not assumed: it is the only thing that catches one.** Demoting
     * to `class` reddens exactly this test; `:shared:engine:jvmTest` passes in
     * full, since no Kotlin consumer relies on structural equality today — the
     * asymmetry with Swift, where `LlamaCppService.knownTurnMarkers` decides its
     * union with a whole-pair `== .chatML` ternary and the equivalent test
     * guards a live consumer.
     */
    @Test
    fun equalityDiscriminatesOnEachField() {
        val base = ChatTurnMarkers(start = "<a>", end = "</a>")
        assertEquals(base, ChatTurnMarkers(start = "<a>", end = "</a>"))
        assertNotEquals(base, ChatTurnMarkers(start = "<b>", end = "</a>"))
        assertNotEquals(base, ChatTurnMarkers(start = "<a>", end = "</b>"))
    }
}
