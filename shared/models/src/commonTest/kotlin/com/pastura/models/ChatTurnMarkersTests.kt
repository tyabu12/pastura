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
     * A change-detector, not a regression test: what it catches is a
     * `data class` → `class` demotion or a hand-written `equals`.
     *
     * **It is the only thing that catches one** — measured, not assumed.
     * Demoting the type to `class` and running both modules reddens exactly this
     * test; `:shared:engine:jvmTest` passes in full. In particular
     * `JSONResponseParserTurnMarkerTests`' `assertEquals(listOf(chatML),
     * backend.knownTurnMarkers)` is **not** a dependant: both sides name the same
     * companion singleton, so element-wise `List.equals` resolves to
     * `chatML == chatML` on one reference and `Any.equals` identity answers it
     * without any structural `equals`. A hand-written `equals` comparing only
     * `start` would pass it too.
     *
     * So no Kotlin consumer relies on structural equality today — the asymmetry
     * with Swift, where `LlamaCppService.knownTurnMarkers` decides its union
     * with a whole-pair `== .chatML` ternary and the equivalent test therefore
     * guards a live consumer. The Phase 3.0 adapter is where one would appear
     * here.
     */
    @Test
    fun equalityDiscriminatesOnEachField() {
        val base = ChatTurnMarkers(start = "<a>", end = "</a>")
        assertEquals(base, ChatTurnMarkers(start = "<a>", end = "</a>"))
        assertNotEquals(base, ChatTurnMarkers(start = "<b>", end = "</a>"))
        assertNotEquals(base, ChatTurnMarkers(start = "<a>", end = "</b>"))
    }
}
