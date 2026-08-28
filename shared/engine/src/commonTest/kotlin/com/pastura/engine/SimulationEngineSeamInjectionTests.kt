package com.pastura.engine

import com.pastura.models.Persona
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import com.pastura.models.SimulationEvent
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Through-runner reach pins for the [LanguageDetector] / [EngineLogger]
 * injection seams: `SimulationEngine(detector = …, logger = …)` → `RunLoop` →
 * the top-level [PhaseContext] → handler → [LLMCaller], and on into the nested
 * [PhaseContext] a `conditional` branch builds.
 *
 * ## Why these are distinct from the existing seam suites
 *
 * [EngineLoggerSeamTests] asserts the seam's *shape*, and
 * [LLMCallerLanguageAdherenceTests] drives [LLMCaller] directly with a
 * hand-built argument list. Both stay green against a runner that constructs
 * its contexts with the defaults — which is exactly what `RunLoop` did before
 * this PR. Only a run started from [SimulationEngine] witnesses the wiring.
 * [ConditionalHandlerTests] does pin the nested sub-context, but from a
 * hand-built parent [PhaseContext]; only [injectedDetectorReachesANestedPhase]
 * proves the whole chain from the constructor down.
 *
 * Kotlin twin of Swift's
 * `EngineLoggerSeamTests.runnerInjectedLoggerReachesTheRunPath`,
 * `SimulationRunnerTests+LanguageMismatch.runnerEmitsLanguageMismatchEventWhenDetectorConfigured`
 * and `SimulationRunnerTests+LanguageMismatch.runnerWithoutDetectorSkipsAdherenceCheck`
 * (the D2d Swift-pin-then-Kotlin-twin pairing).
 *
 * Real threads, not `runTest` — see [runBlockingTest] and
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
 * | d | drop `detector = context.detector` from `ConditionalHandler`'s sub-context | [injectedDetectorReachesANestedPhase] |
 * | e | give `SimulationEngine.detector` a non-null always-`"ja"` default | [defaultConstructorSkipsAdherenceCheck] |
 *
 * Row e is what keeps the back-compat pin from being a negative assertion that
 * nothing can falsify: it is the only mutation that turns the default
 * constructor's seams *on*.
 *
 * Ported for the ADR-023 §6 Stage-3 Engine migration (#501).
 */
class SimulationEngineSeamInjectionTests {

    private fun speakAll() = Phase(
        type = PhaseType.SPEAK_ALL,
        prompt = "Speak.",
        outputSchema = mapOf("statement" to "string"),
    )

    private fun scenario(
        agents: List<String> = listOf("Alice", "Bob"),
        language: String = "en",
        phases: List<Phase> = listOf(speakAll()),
    ) = Scenario(
        id = "t",
        name = "T",
        description = "d",
        language = language,
        agentCount = agents.size,
        rounds = 1,
        context = "A test.",
        personas = agents.map { Persona(name = it, description = "$it's persona.") },
        phases = phases,
    )

    private fun says(text: String) =
        ScriptedLLMBackend.Script.completing("""{"statement": "$text"}""")

    @Test
    fun injectedLoggerReachesTheRunPath() = runBlockingTest {
        // Alice's attempt 1 is unparseable → a `retryCause … parse_failed` line;
        // attempt 2 and Bob's single attempt succeed. The full rendered line is
        // asserted because scripts/analyze-streaming-diag.sh parses that wire format
        // (containment, not "exactly one" — the Swift twin is the same shape).
        //
        // One spare script beyond the 3 the run consumes: a retry-budget regression
        // must redden on the assertion below, not on ScriptedLLMBackend exhausting
        // first (kmp-interop.md § "exhaustion is a harness fault").
        val backend = ScriptedLLMBackend(
            listOf(
                ScriptedLLMBackend.Script.completing("not json at all"),
                says("a"),
                says("b"),
                says("spare"),
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
        //
        // 5 scripts for 4 expected calls: the spare keeps the callCount assertion
        // below the detector of a retry-budget regression.
        val wrong = "ja-language statement that is long enough to pass the detector gate"
        val right = "en-language statement that is long enough to pass the detector gate"
        val backend = ScriptedLLMBackend(
            listOf(says(wrong), says(wrong), says(wrong), says(right), says(right)),
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
    fun injectedDetectorReachesANestedPhase() = runBlockingTest {
        // Same exhaustion shape, but the `speak_all` sits inside a `conditional`
        // branch, so the detector must survive the SECOND context construction —
        // ConditionalHandler's sub-context. `detector` is DEFAULTED on PhaseContext,
        // so dropping it there compiles clean and unwires nested phases only; the
        // top-level pins above stay green. One spare script, as above.
        //
        // Two agents, not one: `RunLoop` ends a round early once fewer than two
        // agents are active, so a single-agent scenario never reaches the branch.
        // Alice burns the 3 "ja" verdicts; Bob's call finds the queue empty →
        // `null` → check skipped, so the mismatch count stays 1.
        val wrong = "ja-language statement that is long enough to pass the detector gate"
        val backend = ScriptedLLMBackend(
            listOf(says(wrong), says(wrong), says(wrong), says(wrong), says(wrong)),
        )
        val nested = scenario(
            phases = listOf(
                Phase(
                    type = PhaseType.CONDITIONAL,
                    condition = "1 == 1",
                    thenPhases = listOf(speakAll()),
                ),
            ),
        )
        val c = Collector()

        SimulationEngine(detector = SequencedDetector(listOf("ja", "ja", "ja")))
            .run(nested, backend) { c.record(it) }
        awaitTerminal(c)

        val events = c.snapshot()
        val mismatches = events.filterIsInstance<SimulationEvent.LanguageMismatch>()
        assertEquals(1, mismatches.size, "the nested PhaseContext must carry the detector")
        assertEquals("Alice", mismatches.single().agent)
        // The sub-phase really did run nested: its path is [0, 0], not [0].
        assertTrue(
            events.filterIsInstance<SimulationEvent.PhaseStarted>()
                .any { it.phaseType == PhaseType.SPEAK_ALL && it.phasePath == listOf(0, 0) },
            "the speak_all must have executed as a conditional sub-phase",
        )
        assertTrue(events.any { it is SimulationEvent.SimulationCompleted })
    }

    @Test
    fun defaultConstructorSkipsAdherenceCheck() {
        // Back-compat pin: the no-argument constructor must keep the pre-wiring
        // behaviour — no detector, hence no adherence check and no retry on
        // wrong-language output. The default logger is unobservable by
        // construction (NoopEngineLogger records nothing), so only the detector
        // half is assertable here; perturbation row e is what gives this negative
        // pin something that can falsify it.
        runBlockingTest {
            val wrong = "ja-language statement that is long enough to pass the detector gate"
            val backend = ScriptedLLMBackend(listOf(says(wrong), says(wrong), says(wrong)))
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
