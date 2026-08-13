package com.pastura.models

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals

/**
 * Coverage for [ChatTurnMarkers] in the module that **owns** it. `shared/engine`'s
 * `JSONResponseParserTurnMarkerTests` exercises these literals only as
 * fixtures, so a reword there would land as a truncation-behaviour failure in a
 * sibling module rather than as an edit to the pair itself.
 *
 * Values pinned byte-for-byte against Swift's `ChatTurnMarkers.chatML` — the
 * two engines share no gate on this type (its KDoc explains why it carries no
 * golden entry), so these literals are the parity anchor, symmetric with
 * `Pastura/PasturaTests/Models/ChatTurnMarkersTests.swift`.
 */
class ChatTurnMarkersTests {

    @Test
    fun chatMLCarriesTheChatMLPair() {
        assertEquals("<|im_start|>", ChatTurnMarkers.chatML.start)
        assertEquals("<|im_end|>", ChatTurnMarkers.chatML.end)
    }

    /**
     * Guards the **structural** `equals` the `data class` modifier synthesizes.
     * Nothing here reverts to redden it, so read it as a change-detector, not a
     * regression test: what it catches is a `data class` → `class` demotion or a
     * hand-written `equals`, either of which would silently break
     * `JSONResponseParserTurnMarkerTests`' `assertEquals(listOf(chatML),
     * backend.knownTurnMarkers)` in the sibling module.
     *
     * Note the asymmetry with Swift, where the equivalent test guards a live
     * consumer: `LlamaCppService.knownTurnMarkers` decides its union with a
     * whole-pair `== .chatML` ternary. This module has no such consumer yet —
     * the Phase 3.0 adapter is where one would appear.
     */
    @Test
    fun equalityDiscriminatesOnEachField() {
        val base = ChatTurnMarkers(start = "<a>", end = "</a>")
        assertEquals(base, ChatTurnMarkers(start = "<a>", end = "</a>"))
        assertNotEquals(base, ChatTurnMarkers(start = "<b>", end = "</a>"))
        assertNotEquals(base, ChatTurnMarkers(start = "<a>", end = "</b>"))
    }
}
