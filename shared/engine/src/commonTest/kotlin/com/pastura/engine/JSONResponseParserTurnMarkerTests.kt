package com.pastura.engine

import com.pastura.models.ChatTurnMarkers
import com.pastura.models.SimulationError
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertTrue

/**
 * Per-model hallucinated-turn truncation (#1422) — the Kotlin half.
 *
 * **Fixtures are deliberately byte-identical to the Swift
 * `JSONResponseParserTests+TurnMarkers.swift` ones** — no gate enforces
 * Swift↔Kotlin parser parity (`check-prompt-literal-parity.py` covers only
 * `pickLanguage`), so a shared fixture set turns a predicate divergence into
 * a failing test instead of silent drift.
 *
 * Every test that asserts the fix also runs the **same input** through the
 * pre-#1422 ChatML-only set as a negative control — otherwise a test passing
 * for an unrelated reason (the balanced-brace scan discards trailing prose)
 * would read as proof truncation fired.
 */
class JSONResponseParserTurnMarkerTests {

    private val parser = JSONResponseParser()

    private val gemma = listOf(ChatTurnMarkers(start = "<|turn>", end = "<turn|>"), ChatTurnMarkers.chatML)
    private val chatMLOnly = listOf(ChatTurnMarkers.chatML)

    /**
     * A fenced fabricated continuation loses the payload: `extractFromCodeBlock`
     * runs before the balanced-brace scan and takes the first match unconditionally.
     */
    private val fencedHallucination = """
        {"statement": "本物", "action": "cooperate"}<turn|>
        <|turn>user
        もう一度
        <turn|>
        <|turn>model
        ```json
        {"statement": "偽物", "action": "betray"}
        ```
    """.trimIndent()

    @Test
    fun endMarkerTruncatesFencedFabricatedContinuation() {
        val output = parser.parse(fencedHallucination, turnMarkers = gemma)
        assertEquals("本物", output.fields["statement"])
        assertEquals("cooperate", output.fields["action"])

        // Negative control — the pre-#1422 behaviour on the identical input.
        assertEquals("偽物", parser.parse(fencedHallucination, turnMarkers = chatMLOnly).fields["statement"])
    }

    /**
     * **The end arm's own header-echo case (#1452).** A *leading* non-ChatML end
     * marker is the model echoing its template's turn boundary with the payload
     * still behind it. Cutting at index 0 destroyed the payload deterministically
     * (the template reproduces on every retry) → an ADR-021 turn skip.
     *
     * Revert the non-ChatML end arm's search origin to `0` and this test fails.
     */
    @Test
    fun endMarkerLeadingHeaderEchoIsNotATurnBoundary() {
        val input = """
            <turn|>
            <|turn>model
            {"statement": "本物", "action": "cooperate"}
        """.trimIndent()

        val output = parser.parse(input, turnMarkers = gemma)
        assertEquals("本物", output.fields["statement"])
        assertEquals("cooperate", output.fields["action"])
    }

    /**
     * The gate is a search *origin*, not a per-text skip: a leading marker is
     * stepped over and the next occurrence after the first structural `{` still
     * cuts, so a fabricated continuation behind a header echo is not accepted.
     */
    @Test
    fun endMarkerLeadingEchoThenFabricatedContinuationCutsAtSecond() {
        val input = """
            <turn|>
            <|turn>model
            {"statement": "本物", "action": "cooperate"}<turn|>
            <|turn>model
            ```json
            {"statement": "偽物", "action": "betray"}
            ```
        """.trimIndent()

        val output = parser.parse(input, turnMarkers = gemma)
        assertEquals("本物", output.fields["statement"])

        // Negative control — without the Gemma pair the fenced continuation wins.
        val unfixed = parser.parse(input, turnMarkers = chatMLOnly)
        assertEquals("偽物", unfixed.fields["statement"])
    }

    /**
     * **Control — byte-identical-for-ChatML criterion.** ChatML's own end marker
     * is *not* gated: a leading `<|im_end|>` still cuts at index 0 under either
     * set, so `<|im_end|>{"fake":1}` keeps failing and retrying rather than
     * becoming an accepted fabricated object (#1422's reason for not gating
     * every marker). A failure here means someone widened the gate to ChatML.
     */
    @Test
    fun endMarkerChatMLLeadingMarkerStillDestroysPayload() {
        val fabricated = assertFailsWith<SimulationException> {
            parser.parse("""<|im_end|>{"fake":1}""", turnMarkers = chatMLOnly)
        }
        assertIs<SimulationError.JsonParseFailed>(fabricated.error)

        // Same marker under Gemma's effective set: the gate keys on the marker
        // literal, not on which model is loaded.
        val underGemma = assertFailsWith<SimulationException> {
            parser.parse("<|im_end|>\n{\"statement\": \"本物\"}", turnMarkers = gemma)
        }
        assertIs<SimulationError.JsonParseFailed>(underGemma.error)
    }

    /**
     * **A pin on the accepted trade, not desired behaviour.** For a non-ChatML
     * marker the fabricated-turn shape — end marker, then an object with nothing
     * before it — is accepted: the object is the only candidate, and failing it
     * deterministically would be the #1452 skip again. Pre-#1422 Gemma had no
     * end arm at all, so this is also the behaviour that shipped before that PR.
     */
    @Test
    fun endMarkerLeadingMarkerThenObjectIsAcceptedAcceptedTrade() {
        val output = parser.parse("""<turn|>{"statement": "偽物"}""", turnMarkers = gemma)
        assertEquals("偽物", output.fields["statement"])
    }

    /**
     * With no structural `{` anywhere the gate has no origin and the arm falls
     * back to the from-0 search; there is nothing to salvage either way.
     */
    @Test
    fun endMarkerNoStructuralBraceStillFails() {
        val error = assertFailsWith<SimulationException> {
            parser.parse("<turn|>\n<|turn>model\nただの文章", turnMarkers = gemma)
        }
        assertIs<SimulationError.JsonParseFailed>(error.error)
    }

    /**
     * A non-ChatML end marker inside a JSON string value is payload content,
     * not a turn boundary. Mirrors Swift's
     * `endMarker_insideStringValue_isNotATurnBoundary`.
     */
    @Test
    fun endMarkerInsideStringValueIsNotATurnBoundary() {
        val input = """{"statement": "テンプレートは <turn|> で終わる", "action": "cooperate"}"""

        val output = parser.parse(input, turnMarkers = gemma)
        assertEquals("テンプレートは <turn|> で終わる", output.fields["statement"])
        assertEquals("cooperate", output.fields["action"])
    }

    /**
     * **Control — byte-identical-for-ChatML criterion.** ChatML's own end marker
     * still cuts string-blind (keyed on `.chatML.end` by literal); this port has
     * no repair pipeline, so the cut just fails the parse.
     */
    @Test
    fun endMarkerChatMLInsideStringValueStillCutsBlind() {
        val input = """{"note": "テンプレートは <|im_end|> で終わる"}"""

        val error = assertFailsWith<SimulationException> {
            parser.parse(input, turnMarkers = chatMLOnly)
        }
        assertIs<SimulationError.JsonParseFailed>(error.error)
    }

    @Test
    fun startMarkerAfterFirstBraceTruncates() {
        val input = """
            {"statement": "本物"}
            <|turn>model
            ```json
            {"statement": "偽物"}
            ```
        """.trimIndent()

        assertEquals("本物", parser.parse(input, turnMarkers = gemma).fields["statement"])
        assertEquals("偽物", parser.parse(input, turnMarkers = chatMLOnly).fields["statement"])
    }

    /**
     * The asymmetry's load-bearing half: a leading start marker is the model
     * echoing its own template header, so cutting there deletes the payload.
     *
     * Change the start-arm search origin from `firstBrace + 1` to `0` and this
     * test fails while every other test here still passes.
     */
    @Test
    fun startMarkerLeadingHeaderEchoIsNotATurnBoundary() {
        val input = """
            <|turn>model
            {"statement": "本物", "action": "cooperate"}
        """.trimIndent()

        val output = parser.parse(input, turnMarkers = gemma)
        assertEquals("本物", output.fields["statement"])
        assertEquals("cooperate", output.fields["action"])
    }

    /**
     * The start arm is string-aware: a marker inside a JSON string value is
     * payload content, not a turn boundary.
     */
    @Test
    fun startMarkerInsideStringValueIsNotATurnBoundary() {
        val input = """{"statement": "テンプレートは <|im_start|> から始まる", "action": "cooperate"}"""

        val output = parser.parse(input, turnMarkers = chatMLOnly)
        assertEquals("テンプレートは <|im_start|> から始まる", output.fields["statement"])
        assertEquals("cooperate", output.fields["action"])
    }

    @Test
    fun markerFreeInputParsesIdenticallyUnderEitherSet() {
        val input = """
            {"statement": "hello", "action": "cooperate"}
            That is my answer for this round.
        """.trimIndent()

        val chatML = parser.parse(input, turnMarkers = chatMLOnly)
        val withGemma = parser.parse(input, turnMarkers = gemma)
        assertEquals(chatML.fields, withGemma.fields)
        assertEquals("hello", chatML.fields["statement"])
    }

    @Test
    fun chatMLHallucinationUnchangedWhenGemmaPairIsAlsoPresent() {
        val input = """
            {"inner_thought": "考え中", "statement": "こんにちは"}<|im_end|>
            <|im_start|>user
            サクラ: 別の発言"}
            <|im_end|>
        """.trimIndent()

        val baseline = parser.parse(input, turnMarkers = chatMLOnly)
        val widened = parser.parse(input, turnMarkers = gemma)
        assertEquals(baseline.fields, widened.fields)
        assertEquals("こんにちは", widened.fields["statement"])
    }

    /**
     * An empty marker string must never match — it would otherwise cut at index
     * 0 and destroy every response.
     */
    @Test
    fun emptyMarkerStringsAreIgnored() {
        val output = parser.parse(
            """{"statement": "hello"}""",
            turnMarkers = listOf(ChatTurnMarkers(start = "", end = "")),
        )
        assertEquals("hello", output.fields["statement"])
    }

    @Test
    fun emptyMarkerSetLeavesTextUntouched() {
        val output = parser.parse("""{"statement": "hello"}<|im_end|>garbage""", turnMarkers = emptyList())
        assertEquals("hello", output.fields["statement"])
    }

    /**
     * The default parameter reproduces the pre-#1422 ChatML-only behaviour for
     * callers with no backend in scope.
     */
    @Test
    fun defaultMarkerSetIsChatMLOnly() {
        val input = """{"statement": "hello"}<|im_end|> trailing"""
        assertEquals(parser.parse(input, turnMarkers = chatMLOnly).fields, parser.parse(input).fields)
    }

    /**
     * The backend seam's default is ChatML-only, matching Swift's
     * `LLMService.knownTurnMarkers` protocol-extension default.
     */
    @Test
    fun backendDefaultKnownTurnMarkersIsChatMLOnly() {
        val backend = object : LLMBackend {
            override fun generateStream(
                request: GenerationRequest,
                callbacks: StreamCallbacks,
            ): StreamHandle = throw UnsupportedOperationException("not used")
        }
        assertEquals(listOf(ChatTurnMarkers.chatML), backend.knownTurnMarkers)
        assertTrue(backend.knownTurnMarkers.none { it.start == "<|turn>" })
        assertFalse(backend.knownTurnMarkers.isEmpty())
    }
}
