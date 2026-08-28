package com.pastura.engine

import com.pastura.models.Persona
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import com.pastura.models.SimulationEvent
import kotlin.concurrent.atomics.AtomicReference
import kotlin.concurrent.atomics.ExperimentalAtomicApi
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Through-runner reach pins for the [LanguageDetector] / [EngineLogger]
 * injection seams: `SimulationEngine(detector = …, logger = …)` → `RunLoop` →
 * the top-level [PhaseContext] → handler → [LLMCaller].
 *
 * ## Why these are distinct from the existing seam suites
 *
 * [EngineLoggerSeamTests] asserts the seam's *shape*, and
 * [LLMCallerLanguageAdherenceTests] drives [LLMCaller] directly with a
 * hand-built argument list. Both stay green against a runner that constructs
 * its contexts with the defaults — which is exactly what `RunLoop` did before
 * this PR. Only a run started from [SimulationEngine] witnesses the wiring.
 *
 * Kotlin twin of Swift's
 * `EngineLoggerSeamTests.runnerInjectedLoggerReachesTheRunPath` and
 * `SimulationRunnerTests+LanguageMismatch.runnerEmitsLanguageMismatchEventWhenDetectorConfigured`
 * (the D2d Swift-pin-then-Kotlin-twin pairing).
 *
 * Real threads, not `runTest` — see [RunBlockingTest][runBlockingTest] and
 * [SimulationEngineTests]' KDoc: [SimulationEngine.run] owns its own
 * `Dispatchers.Default` scope, so a virtual scheduler would measure the
 * scheduler rather than the engine.
 *
 * ## ADR-023 §12 condition-4 perturbation record (measured 2026-08-28, jvmTest)
 *
 * | # | Mutation | Reddens |
 * |---|---|---|
 * | a | drop `detector = detector` from `RunLoop`'s top-level `PhaseContext(…)` | [injectedDetectorReachesTheRunPath] |
 * | b | drop `logger = logger` from the same construction site | [injectedLoggerReachesTheRunPath] |
 * | c | thread `NoopEngineLogger()` into `RunLoop` instead of the ctor's `logger` | [injectedLoggerReachesTheRunPath] |
 *
 * Ported for the ADR-023 §6 Stage-3 Engine migration (#501).
 */
class SimulationEngineSeamInjectionTests {

    private fun scenario(
        agents: List<String> = listOf("Alice", "Bob"),
        language: String = "en",
    ) = Scenario(
        id = "t",
        name = "T",
        description = "d",
        language = language,
        agentCount = agents.size,
        rounds = 1,
        context = "A test.",
        personas = agents.map { Persona(name = it, description = "$it's persona.") },
        phases = listOf(
            Phase(type = PhaseType.SPEAK_ALL, prompt = "Speak.", outputSchema = mapOf("statement" to "string")),
        ),
    )

    private fun says(text: String) =
        ScriptedLLMBackend.Script.completing("""{"statement": "$text"}""")

    /**
     * Thread-safe spy logger.
     *
     * The atomics are load-bearing for the same reason [Collector]'s are: the
     * engine logs from its worker context while the test body reads from
     * `runBlockingTest`'s thread, and on Kotlin/Native an unsynchronized list
     * across that edge is undefined behaviour rather than a stale read.
     */
    @OptIn(ExperimentalAtomicApi::class)
    private class SpyEngineLogger : EngineLogger {
        data class Entry(
            val level: EngineLogLevel,
            val category: String,
            val message: String,
            val privacy: EngineLogPrivacy,
        )

        private val ref = AtomicReference<List<Entry>>(emptyList())

        override fun log(level: EngineLogLevel, category: String, message: String, privacy: EngineLogPrivacy) {
            val entry = Entry(level, category, message, privacy)
            while (true) {
                val current = ref.load()
                if (ref.compareAndSet(current, current + entry)) return
            }
        }

        val entries: List<Entry> get() = ref.load()

        /** Rendered messages emitted on the `StreamingDiag` channel, in order. */
        fun diagLines(): List<String> = entries.filter { it.category == "StreamingDiag" }.map { it.message }
    }

    /**
     * Detector whose verdicts are a queue drained one entry per call, returning
     * `null` once empty. Atomic for the same cross-thread reason as
     * [SpyEngineLogger] — here the calls themselves land on the worker context.
     */
    @OptIn(ExperimentalAtomicApi::class)
    private class SequencedDetector(verdicts: List<String?>) : LanguageDetector {
        private val queue = AtomicReference(verdicts)

        override fun detect(text: String): String? {
            while (true) {
                val current = queue.load()
                if (current.isEmpty()) return null
                if (queue.compareAndSet(current, current.drop(1))) return current.first()
            }
        }
    }

    @Test
    fun injectedLoggerReachesTheRunPath() = runBlockingTest {
        // Alice's attempt 1 is unparseable → exactly one `retryCause … parse_failed`
        // line; attempt 2 and Bob's single attempt succeed. The full rendered line is
        // asserted because scripts/analyze-streaming-diag.sh parses that wire format.
        val backend = ScriptedLLMBackend(
            listOf(
                ScriptedLLMBackend.Script.completing("not json at all"),
                says("a"),
                says("b"),
            ),
        )
        val spy = SpyEngineLogger()
        val c = Collector()

        SimulationEngine(logger = spy).run(scenario(), backend) { c.record(it) }
        awaitTerminal(c)

        assertTrue(
            c.snapshot().any { it is SimulationEvent.SimulationCompleted },
            "the run must complete — a retry, not a failure",
        )
        assertContains(spy.diagLines(), "retryCause agent=Alice attempt=1 cause=parse_failed")
    }

    @Test
    fun injectedDetectorReachesTheRunPath() = runBlockingTest {
        // Alice exhausts the adherence budget (3 "ja" verdicts against an `en`
        // scenario) → LanguageMismatch, and her output is still delivered; Bob's
        // "en" verdict passes on attempt 1, proving one agent's exhaustion does not
        // poison the next. Twin of Swift's
        // runnerEmitsLanguageMismatchEventWhenDetectorConfigured.
        val wrong = "ja-language statement that is long enough to pass the detector gate"
        val right = "en-language statement that is long enough to pass the detector gate"
        val backend = ScriptedLLMBackend(
            listOf(says(wrong), says(wrong), says(wrong), says(right)),
        )
        val c = Collector()

        SimulationEngine(detector = SequencedDetector(listOf("ja", "ja", "ja", "en")))
            .run(scenario(), backend) { c.record(it) }
        awaitTerminal(c)

        val events = c.snapshot()
        val mismatches = events.filterIsInstance<SimulationEvent.LanguageMismatch>()
        assertEquals(1, mismatches.size, "exactly one exhaustion, from Alice")
        assertEquals("Alice", mismatches.single().agent)
        assertEquals("ja", mismatches.single().detected)
        assertEquals("en", mismatches.single().expected)

        assertEquals(
            2,
            events.filterIsInstance<SimulationEvent.AgentOutput>().size,
            "the sim continues — both agents' output is delivered",
        )
        assertEquals(4, backend.callCount, "Alice 3 attempts (exhausted) + Bob 1")
        assertTrue(events.any { it is SimulationEvent.SimulationCompleted })
    }

    @Test
    fun defaultsLeaveBothSeamsOff() {
        // Back-compat pin: the no-argument constructor must keep the pre-wiring
        // behaviour — no detector (no adherence check, hence no retry on
        // wrong-language output) and a silent logger.
        runBlockingTest {
            val wrong = "ja-language statement that is long enough to pass the detector gate"
            val backend = ScriptedLLMBackend(listOf(says(wrong), says(wrong)))
            val c = Collector()

            SimulationEngine().run(scenario(), backend) { c.record(it) }
            awaitTerminal(c)

            assertTrue(
                c.snapshot().none { it is SimulationEvent.LanguageMismatch },
                "no detector → no adherence check → no event",
            )
            assertEquals(2, backend.callCount, "one call per agent, no retry consumed")
        }
    }
}
