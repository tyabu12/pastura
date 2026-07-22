package com.pastura.engine

import com.pastura.models.OutputSchema
import com.pastura.models.SimulationEvent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Parity tests for the ADR-010 Step E language-adherence retry in [LLMCaller],
 * ported from Swift's `LLMCallerLanguageAdherenceTests`. Verifies:
 *
 * - Retry consumption on mismatch within the existing `MAX_RETRIES=2` budget; a
 *   later attempt returning the correct language → success.
 * - Exhaustion path: all attempts mismatched → [SimulationEvent.LanguageMismatch]
 *   emitted AND the parsed [com.pastura.models.TurnOutput] still returned (the sim
 *   continues — structurally distinct from a parse failure, which throws).
 * - Skip paths: detector returns null (low-confidence) → no retry;
 *   `expectedLanguage == null` → no retry; `detector == null` → no retry; joined
 *   natural-language text below the min-length gate → no retry.
 * - Priority pin: an `empty_field` + wrong-language response retries for the empty
 *   field first (the adherence check is gated on a non-empty output).
 * - Schema-aware carve-out: author-defined [OutputSchema.Kind.Choice] fields are
 *   excluded from the detection input.
 *
 * The `SpyEngineLogger` assertions defend the `StreamingDiag` **wire format** the
 * external `scripts/analyze-streaming-diag.sh` parses — the full rendered line, not
 * a substring, so a field-order or `attempt`-index regression fails here.
 *
 * Ported for the ADR-023 §6 Stage-3 Engine migration (#501, B0b).
 */
class LLMCallerLanguageAdherenceTests {

    /**
     * A [LanguageDetector] whose verdict is a queue drained one entry per call;
     * returns null when empty. Mirrors Swift's `StubLanguageDetector`.
     */
    private class StubLanguageDetector(verdicts: List<String?>) : LanguageDetector {
        private val queue = verdicts.toMutableList()
        override fun detect(text: String): String? =
            if (queue.isEmpty()) null else queue.removeAt(0)
    }

    /** Records every rendered log line so tests can assert the wire format exactly. */
    private class SpyEngineLogger : EngineLogger {
        data class Entry(
            val level: EngineLogLevel,
            val category: String,
            val message: String,
            val privacy: EngineLogPrivacy,
        )

        val entries = mutableListOf<Entry>()
        override fun log(level: EngineLogLevel, category: String, message: String, privacy: EngineLogPrivacy) {
            entries += Entry(level, category, message, privacy)
        }

        /** Rendered messages emitted on the `StreamingDiag` channel, in order. */
        fun diagLines(): List<String> = entries.filter { it.category == "StreamingDiag" }.map { it.message }
    }

    private fun speakAllSchema() =
        OutputSchema(listOf(OutputSchema.Field("statement", OutputSchema.Kind.StringKind)))

    /** A `choose`-phase schema whose `action` is a payload-free [OutputSchema.Kind.Choice]. */
    private fun chooseSchemaWithChoiceField() =
        OutputSchema(listOf(OutputSchema.Field("action", OutputSchema.Kind.Choice)))

    private fun says(text: String) = ScriptedLLMBackend.Script.completing(text)

    private suspend fun call(
        backend: LLMBackend,
        detector: LanguageDetector?,
        expectedLanguage: String?,
        schema: OutputSchema? = speakAllSchema(),
        logger: EngineLogger = NoopEngineLogger(),
        events: MutableList<SimulationEvent> = mutableListOf(),
    ) = LLMCaller(logger = logger).call(
        backend = backend,
        system = "sys",
        user = "usr",
        agentName = "Alice",
        schema = schema,
        detector = detector,
        expectedLanguage = expectedLanguage,
        relay = SuspensionRelay(),
        emitter = { events += it },
    )

    // MARK: - Retry consumption (case a)

    @Test
    fun retriesOnLanguageMismatch() = runTest {
        // Attempt 1 wrong language ("ja", expected "en") → retry. Attempt 2 correct
        // → succeed. Long statements so the min-length gate does not fire.
        val backend = ScriptedLLMBackend(
            listOf(
                says("""{"statement": "ja-language statement that is long enough to pass the detector gate"}"""),
                says("""{"statement": "en-language statement that is long enough to pass the detector gate"}"""),
            ),
        )
        val events = mutableListOf<SimulationEvent>()
        val spy = SpyEngineLogger()
        val result = call(
            backend,
            detector = StubLanguageDetector(listOf("ja", "en")),
            expectedLanguage = "en",
            logger = spy,
            events = events,
        )

        assertTrue(result.fields["statement"]?.contains("en-language") ?: false)
        assertEquals(2, backend.callCount)
        assertTrue(
            events.filterIsInstance<SimulationEvent.LanguageMismatch>().isEmpty(),
            "a successful retry must not emit LanguageMismatch",
        )
        // Full-line wire-format assertion (critic W): defends field order +
        // attempt index against scripts/analyze-streaming-diag.sh.
        assertContains(spy.diagLines(), "retryCause agent=Alice attempt=1 cause=language_mismatch")
    }

    // MARK: - Exhaustion path (case b)

    @Test
    fun emitsLanguageMismatchEventOnExhaustion() = runTest {
        // All 3 attempts wrong language. Retry budget exhausts; the event fires; the
        // final parse result is still returned (contra parse failure, which throws).
        val wrong = """{"statement": "ja-language statement that is long enough to pass the gate"}"""
        val backend = ScriptedLLMBackend(listOf(says(wrong), says(wrong), says(wrong)))
        val events = mutableListOf<SimulationEvent>()
        val result = call(
            backend,
            detector = StubLanguageDetector(listOf("ja", "ja", "ja")),
            expectedLanguage = "en",
            events = events,
        )

        assertTrue(result.fields["statement"]?.contains("ja-language") ?: false)
        assertEquals(3, backend.callCount, "exhausted budget = MAX_RETRIES + 1 = 3")
        val mismatches = events.filterIsInstance<SimulationEvent.LanguageMismatch>()
        assertEquals(1, mismatches.size)
        assertEquals("Alice", mismatches.single().agent)
        assertEquals("ja", mismatches.single().detected)
        assertEquals("en", mismatches.single().expected)
    }

    // MARK: - Skip paths

    @Test
    fun noRetryWhenDetectorReturnsNull() = runTest {
        // Detector returns null → low-confidence → adherence check skipped.
        val backend = ScriptedLLMBackend(
            listOf(says("""{"statement": "some ambiguous output that the detector cannot classify"}""")),
        )
        val result = call(backend, detector = StubLanguageDetector(listOf(null)), expectedLanguage = "en")
        assertTrue(result.fields["statement"]?.contains("ambiguous") ?: false)
        assertEquals(1, backend.callCount, "detector null → no retry")
    }

    @Test
    fun noRetryWhenExpectedLanguageIsNull() = runTest {
        // No expected language → check skipped (back-compat path).
        val backend = ScriptedLLMBackend(
            listOf(says("""{"statement": "ja statement that would normally be flagged as wrong"}""")),
        )
        call(backend, detector = StubLanguageDetector(listOf("ja")), expectedLanguage = null)
        assertEquals(1, backend.callCount)
    }

    @Test
    fun noRetryWhenDetectorIsNull() = runTest {
        // No detector configured → check skipped entirely (also back-compat).
        val backend = ScriptedLLMBackend(
            listOf(says("""{"statement": "ja statement that would normally be flagged as wrong"}""")),
        )
        call(backend, detector = null, expectedLanguage = "en")
        assertEquals(1, backend.callCount)
    }

    @Test
    fun noRetryWhenJoinedTextBelowMinLength() = runTest {
        // Short vote target "佐藤" (2 scalars) < min-length gate → skip. The detector
        // would return "ja" if asked, but the gate fires first.
        val voteSchema = OutputSchema(listOf(OutputSchema.Field("vote", OutputSchema.Kind.StringKind)))
        val backend = ScriptedLLMBackend(listOf(says("""{"vote": "佐藤"}""")))
        val spy = SpyEngineLogger()
        val result = call(
            backend,
            detector = StubLanguageDetector(listOf("ja")),
            expectedLanguage = "en",
            schema = voteSchema,
            logger = spy,
        )
        assertEquals("佐藤", result.fields["vote"])
        assertEquals(1, backend.callCount, "short input → adherence check skipped → no retry")
        // Full-line wire-format assertion (critic W).
        assertContains(spy.diagLines(), "langCheckSkipped agent=Alice reason=too_short")
    }

    // MARK: - Priority pin (case f)

    @Test
    fun emptyFieldRetryFiresBeforeLanguageMismatchRetry() = runTest {
        // Attempt 1 has BOTH an empty `statement` ("...") and a wrong-language
        // thought — post-parse ordering pins empty_field BEFORE language_mismatch.
        // Attempt 2 provides correct-language non-empty output → succeed. The
        // detector is consulted only on attempt 2 (empty_field short-circuits
        // before adherence on attempt 1).
        //
        // Both attempts carry BOTH schema keys non-empty: the Kotlin parser's
        // `hasAllExpectedKeys` guard rejects a valid object missing an expected
        // key (stricter than Swift, which accepts it — see the schema-less
        // `emptyFieldTriggersARetry`), so a `statement`-only attempt-2 would be a
        // parse_failed, not the empty→adherence path this test pins.
        val backend = ScriptedLLMBackend(
            listOf(
                says("""{"statement": "...", "inner_thought": "ja thought that is long enough here"}"""),
                says("""{"statement": "en statement that is long enough", "inner_thought": "en thought here too"}"""),
            ),
        )
        val events = mutableListOf<SimulationEvent>()
        val schema = OutputSchema(
            listOf(
                OutputSchema.Field("statement", OutputSchema.Kind.StringKind),
                OutputSchema.Field("inner_thought", OutputSchema.Kind.StringKind),
            ),
        )
        val result = call(
            backend,
            detector = StubLanguageDetector(listOf("en")),
            expectedLanguage = "en",
            schema = schema,
            events = events,
        )

        assertTrue(result.fields["statement"]?.contains("en statement") ?: false)
        assertEquals(2, backend.callCount)
        assertTrue(events.filterIsInstance<SimulationEvent.LanguageMismatch>().isEmpty())
    }

    // MARK: - Schema-aware carve-out (case g)

    @Test
    fun noRetryForChooseSchemaWithChoiceField() = runTest {
        // choose-phase schema with `action: Choice` on a ja scenario. The output is
        // the author-supplied English action token — the schema filter excludes
        // Choice fields, so the joined detection input is empty → check skipped.
        val backend = ScriptedLLMBackend(listOf(says("""{"action": "cooperate"}""")))
        // The detector would return "en" for "cooperate" if asked — an empty verdict
        // queue + callCount==1 proves it is NOT asked.
        val result = call(
            backend,
            detector = StubLanguageDetector(emptyList()),
            expectedLanguage = "ja",
            schema = chooseSchemaWithChoiceField(),
        )
        assertEquals("cooperate", result.fields["action"])
        assertEquals(1, backend.callCount, "choice-only schema → no natural-language input → skip")
    }
}
