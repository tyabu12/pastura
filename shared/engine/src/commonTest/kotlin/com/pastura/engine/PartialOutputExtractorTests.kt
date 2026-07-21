package com.pastura.engine

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Kotlin siblings of the Swift `PartialOutputExtractorTests` deterministic
 * cases. Feeds progressively-longer buffers through the extractor and asserts
 * the extracted `(primary, thought)` snapshot at each prefix.
 *
 * **Knowingly absent** (parity carve-out, cf. the EngineLogger behavioral
 * carve-out): the three byte-stream fixture-replay tests
 * (`cjkBoundaryFixtureReplaysWithoutContradiction`,
 * `escapedQuoteFixtureReplaysWithoutContradiction`,
 * `normalFixtureReplaysWithoutContradiction`) and their
 * `replayAndCheckMonotonicity` / `longestValidUtf8Prefix` helpers. They depend
 * on Swift `LlamaCppTraceFixtures` + the canonical `JSONResponseParser` replay
 * path, neither of which is in the Kotlin parity scope.
 *
 * ### Kotlin string-literal note
 *
 * Buffer literals use triple-quoted raw strings (`"""..."""`) — like the Swift
 * original's `#"..."#` raw strings, they do NOT process escapes, so a `\n` /
 * `é` / `\\` in the buffer reaches the extractor as LITERAL backslash-escape
 * bytes for it to decode. Regular double-quoted strings are used only for
 * assertion expected-values, where the DECODED characters are wanted (a real
 * newline, a real backslash, `café`).
 *
 * Ported for ADR-023 Stage 3 (#501).
 */
class PartialOutputExtractorTests {

    private val extractor = PartialOutputExtractor()

    // MARK: - Empty / pre-JSON

    @Test
    fun emptyBufferYieldsEmptySnapshot() {
        assertEquals(PartialSnapshot.empty, extractor.extract(""))
    }

    @Test
    fun bufferWithoutOpenBraceYieldsEmpty() {
        assertEquals(PartialSnapshot.empty, extractor.extract("Sure! Here is the JSON:"))
    }

    @Test
    fun bufferStoppedBeforeOpeningQuoteYieldsEmpty() {
        // Colon not yet arrived — extractor must wait.
        assertNull(extractor.extract("""{"statement"""").primary)
        // Colon arrived but no opening quote — still wait.
        assertNull(extractor.extract("""{"statement":""").primary)
    }

    // MARK: - Primary key reveals

    @Test
    fun primaryRevealsAfterOpeningQuote() {
        // Opening quote present but no content — primary is empty string, not null.
        val snap = extractor.extract("""{"statement":"""")
        assertEquals("", snap.primary)
    }

    @Test
    fun primaryRevealsIncrementalText() {
        val snap = extractor.extract("""{"statement":"Let's coope""")
        assertEquals("Let's coope", snap.primary)
        assertNull(snap.thought)
    }

    @Test
    fun primaryRevealsCompleteValue() {
        val snap = extractor.extract("""{"statement":"Let's cooperate."}""")
        assertEquals("Let's cooperate.", snap.primary)
    }

    @Test
    fun allKnownPrimaryKeysResolve() {
        for (key in PartialOutputExtractor.primaryKeys) {
            val snap = extractor.extract("""{"$key":"val"}""")
            assertEquals("val", snap.primary, "primary key $key failed to resolve")
        }
    }

    @Test
    fun reflectNoteStreamsAsPrimary() {
        // reflect's canonical primary field is `note`; a partial reflect JSON must
        // yield a live primary snapshot as it types in.
        val partial = extractor.extract("""{"note":"I should keep quiet abo""")
        assertEquals("I should keep quiet abo", partial.primary)
        val complete = extractor.extract("""{"note":"I should keep quiet."}""")
        assertEquals("I should keep quiet.", complete.primary)
    }

    // MARK: - Thought

    @Test
    fun thoughtResolvesAfterPrimary() {
        val snap = extractor.extract("""{"statement":"hi","inner_thought":"secret"}""")
        assertEquals("hi", snap.primary)
        assertEquals("secret", snap.thought)
    }

    @Test
    fun thoughtIsNilIfNotYetOpened() {
        val snap = extractor.extract("""{"statement":"hi"""")
        assertEquals("hi", snap.primary)
        assertNull(snap.thought)
    }

    // MARK: - Phase-specific thought key (#609)

    // The vote phase's private-thought field is `reason`, not `inner_thought`.
    // The caller passes the schema-derived thought key so the live streaming
    // THINKING section surfaces the vote reason as it types in (parity with
    // speak's `inner_thought`).
    @Test
    fun reasonThoughtKeyExtractsVoteReason() {
        val snap = extractor.extract(
            """{"vote":"Dave","reason":"散歩に行きたい"}""",
            thoughtKey = "reason",
        )
        assertEquals("Dave", snap.primary)
        assertEquals("散歩に行きたい", snap.thought)
    }

    @Test
    fun reasonThoughtStreamsIncrementally() {
        val snap = extractor.extract(
            """{"vote":"Dave","reason":"散""",
            thoughtKey = "reason",
        )
        assertEquals("Dave", snap.primary)
        assertEquals("散", snap.thought)
    }

    // Default thought key stays `inner_thought` (back-compat): a vote buffer read
    // with the default key surfaces no thought.
    @Test
    fun defaultThoughtKeyIgnoresReason() {
        val snap = extractor.extract("""{"vote":"Dave","reason":"散歩"}""")
        assertEquals("Dave", snap.primary)
        assertNull(snap.thought)
    }

    // MARK: - Escape handling

    @Test
    fun escapedQuoteInPrimary() {
        val snap = extractor.extract("""{"statement":"She said \"hi\""}""")
        assertEquals("She said \"hi\"", snap.primary)
    }

    @Test
    fun escapedBackslashInPrimary() {
        val snap = extractor.extract("""{"statement":"a\\b"}""")
        assertEquals("a\\b", snap.primary)
    }

    @Test
    fun escapedNewlineInPrimary() {
        val snap = extractor.extract("""{"statement":"line1\nline2"}""")
        assertEquals("line1\nline2", snap.primary)
    }

    @Test
    fun incompleteEscapeAtEndHoldsBack() {
        // Buffer ends with a lone backslash — the next char might be `"` (end of
        // string) or `\\` (literal backslash). Must not emit the `\` yet.
        val snap = extractor.extract("""{"statement":"x\""")
        assertEquals("x", snap.primary)
    }

    @Test
    fun incompleteUnicodeEscapeHoldsBack() {
        // \uXXXX needs 4 hex digits — fewer is incomplete.
        val snap = extractor.extract("""{"statement":"a\u00""")
        assertEquals("a", snap.primary)
    }

    @Test
    fun completeUnicodeEscapeDecodes() {
        // é is é. The raw-string buffer holds the literal `é` escape
        // sequence (Kotlin raw strings do not process \u escapes) for the extractor
        // to decode; the expected value is the decoded character.
        val snap = extractor.extract("""{"statement":"caf\u00e9"}""")
        assertEquals("café", snap.primary)
    }

    @Test
    fun signedUnicodeEscapeHoldsBack() {
        // Kotlin's toIntOrNull(16) accepts a leading '-'; Swift's UInt32(_:radix:)
        // rejects it. The hex-charset guard makes both hold back the incomplete
        // escape.
        val snap = extractor.extract("""{"statement":"a\u-0ff""")
        assertEquals("a", snap.primary)
    }

    @Test
    fun surrogateUnicodeEscapeHoldsBack() {
        // A lone surrogate code point (0xD800..0xDFFF) has no scalar value: Swift's
        // Unicode.Scalar(code) returns nil there, so the Swift original holds back.
        // GUARD 2 reproduces that — without it, code.toChar() would append a lone
        // surrogate Char and break parity. (Not in the Swift suite; added to pin the
        // ported guard under ADR-023 §12 condition-4 perturbation.)
        val snap = extractor.extract("""{"statement":"a\uD800"}""")
        assertEquals("a", snap.primary)
    }

    // MARK: - Thinking-tag handling

    @Test
    fun unclosedChannelThinkingTagHidesEverything() {
        // While we're inside a thinking tag, no extraction should fire even if `{`
        // appears later in the tag's content.
        val snap = extractor.extract("""<|channel>thought\nI'll say {"statement":"hi"}""")
        assertEquals(PartialSnapshot.empty, snap)
    }

    @Test
    fun closedChannelThinkingTagIsStripped() {
        val buffer = """
            <|channel>thought
            reasoning here
            <channel|>{"statement":"visible"}
        """.trimIndent()
        assertEquals("visible", extractor.extract(buffer).primary)
    }

    @Test
    fun unclosedThinkTagHidesEverything() {
        val snap = extractor.extract("""<think>reasoning {"statement":"hi""")
        assertEquals(PartialSnapshot.empty, snap)
    }

    // MARK: - Leading garbage

    @Test
    fun leadingGarbageSkippedUntilBrace() {
        val snap = extractor.extract("Sure! Here's my response:\n\n{\"statement\":\"OK\"}")
        assertEquals("OK", snap.primary)
    }
}
