package com.pastura.engine

import com.pastura.models.AnyCodableValue
import com.pastura.models.AssignTarget
import com.pastura.models.Persona
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import com.pastura.models.SimulationEvent
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Pins the ADR-023 S3b RNG seam's *reach*: a [RandomSource] injected at the
 * [SimulationEngine] / [PhaseContext] boundary must actually drive every draw the
 * Engine makes, so a cross-language parity fixture handing both engines the same
 * seed gets the same `assign random_one` / `event_inject` outcomes.
 * [RandomSourceTests] pins the generator itself; this suite pins the wiring
 * around it.
 *
 * **Swift twin: `Pastura/PasturaTests/Engine/RandomSourceSeamTests.swift`.** Same
 * scenarios, same seeds, SAME expected picks — that identity is the point, and it
 * is the first cross-language evidence for the seam, ahead of the Stage-4 seeded
 * parity fixtures. A literal that diverges between the two files is a parity
 * break even when both suites are green in isolation.
 *
 * Every expected index below is derived by hand from the SplitMix64 known-answer
 * vectors in [RandomSourceTests] — the seam's reductions are
 * `index(below = n) == nextUInt64() % n` and `unit() == (bits ushr 11) * 2^-53`,
 * so the literals here are checkable without running the code.
 *
 * Real threads, not `runTest` — see [runBlockingTest]: [SimulationEngine.run]
 * owns its own `Dispatchers.Default` scope, so a virtual scheduler would measure
 * the scheduler rather than the engine.
 */
class RandomSourceSeamTests {

    /**
     * `assign random_one` draws the topic first, then the wolf — so with
     * `SplitMix64RandomSource(seed = 0)` (raw stream `0xE220A8397B1DCDAF`,
     * `0x6E789E6AA1B965F4`, …) the picks are:
     *
     * - topic: `0xE220A8397B1DCDAF % 2 == 1` → the second topic (`"みかん"` pair)
     * - wolf:  `0x6E789E6AA1B965F4 % 3 == 0` → `Alice`
     *
     * Same seed twice ⇒ identical `Assignment` events; that is the property a
     * parity fixture depends on.
     */
    @Test
    fun seededAssignRandomOneIsDeterministic() = runBlockingTest {
        val first = runAssignRandomOne(seed = 0uL)
        val second = runAssignRandomOne(seed = 0uL)

        assertEquals(first, second, "the same seed must replay the same picks")
        assertEquals("Alice", first.wolfName)
        assertEquals("みかん", first.assignments["Alice"])
        assertEquals("りんご", first.assignments["Bob"])
        assertEquals("りんご", first.assignments["Charlie"])
    }

    /**
     * A different seed picks a different topic *and* a different wolf, so the
     * assertion above cannot pass by accident on a seam that ignores the injected
     * source. Seed 2's first two draws reduce to `% 2 == 0` (the first topic, the
     * `"ぶどう"` pair) and `% 3 == 2` (`Charlie`).
     */
    @Test
    fun differentSeedPicksDifferentTopicAndWolf() = runBlockingTest {
        val result = runAssignRandomOne(seed = 2uL)

        assertEquals("Charlie", result.wolfName)
        assertEquals("ぶどう(minority)", result.assignments["Charlie"])
        assertEquals("ぶどう", result.assignments["Alice"])
        assertEquals("ぶどう", result.assignments["Bob"])
    }

    /**
     * The critical case: an `event_inject` nested inside a `conditional` branch
     * must see the *injected* source. [ConditionalHandler] builds a fresh
     * sub-[PhaseContext], and omitting `random` there silently reverts the
     * sub-phase to the system RNG — this run would then fire (or not) at random.
     *
     * Seed 3's stream reduces to `unit() == 0.113450…` (< the phase's `0.5`, so
     * the roll hits) and then `% 2 == 1` for the pick, i.e. the second event.
     */
    @Test
    fun seededEventInjectInsideConditionalFires() = runBlockingTest {
        assertEquals(listOf("停電"), runConditionalEventInject(seed = 3uL))
    }

    /**
     * The paired miss: seed 0's first `unit()` is `0.883310…`, which is not
     * `< 0.5`, so the same scenario injects nothing. Together with the case above
     * this pins both sides of the roll to the injected stream.
     */
    @Test
    fun seededEventInjectInsideConditionalMisses() = runBlockingTest {
        assertEquals(emptyList(), runConditionalEventInject(seed = 0uL))
    }

    /**
     * Behaviour preservation: an engine built without `random` still runs
     * `assign random_one` and produces a well-formed assignment. The default is
     * [SystemRandomSource], so only the *shape* is assertable here — that is the
     * point, since shipped behaviour must be unchanged by the seam.
     */
    @Test
    fun defaultRandomSourceStillAssigns() = runBlockingTest {
        val c = Collector()
        SimulationEngine().run(wordWolfScenario(), ScriptedLLMBackend(emptyList())) { c.record(it) }
        awaitTerminal(c)

        val assignments = assignmentsOf(c.snapshot())
        assertEquals(3, assignments.size)
        assertEquals(
            1,
            assignments.values.count { it == "みかん" || it == "ぶどう(minority)" },
            "exactly one wolf, whatever the platform RNG picked",
        )
    }

    // --- Fixtures ---

    /**
     * Two grouped topics so the topic draw is observable, and three agents so the
     * wolf draw is too. The second pair's majority/minority texts differ from the
     * first's, so a single `Assignment` value identifies both draws.
     */
    private fun wordWolfScenario() = Scenario(
        id = "t",
        name = "T",
        description = "d",
        language = "en",
        agentCount = 3,
        rounds = 1,
        context = "A test.",
        personas = listOf("Alice", "Bob", "Charlie").map {
            Persona(name = it, description = "$it's persona.")
        },
        phases = listOf(
            Phase(type = PhaseType.ASSIGN, source = "words", target = AssignTarget.RANDOM_ONE),
        ),
        extraData = mapOf(
            "words" to AnyCodableValue.ArrayOfDictionariesValue(
                listOf(
                    mapOf("majority" to "ぶどう", "minority" to "ぶどう(minority)"),
                    mapOf("majority" to "りんご", "minority" to "みかん"),
                ),
            ),
        ),
    )

    private data class AssignOutcome(
        val wolfName: String?,
        val assignments: Map<String, String>,
    )

    private fun assignmentsOf(events: List<SimulationEvent>): Map<String, String> =
        events.filterIsInstance<SimulationEvent.Assignment>().associate { it.agent to it.value }

    /**
     * Drives `assign random_one` through a full [SimulationEngine] run so the
     * engine → [PhaseContext] leg of the seam is covered, not just a hand-built
     * context.
     */
    private suspend fun runAssignRandomOne(seed: ULong): AssignOutcome {
        val c = Collector()
        SimulationEngine(random = SplitMix64RandomSource(seed = seed))
            .run(wordWolfScenario(), ScriptedLLMBackend(emptyList())) { c.record(it) }
        awaitTerminal(c)

        val assignments = assignmentsOf(c.snapshot())
        // `wolf_name` lives in state, which the event stream does not carry, so
        // derive it from the one agent holding a minority value.
        val wolf = assignments.entries.firstOrNull {
            it.value == "みかん" || it.value == "ぶどう(minority)"
        }
        return AssignOutcome(wolfName = wolf?.key, assignments = assignments)
    }

    /**
     * Runs an `event_inject` nested one level inside a `conditional` whose
     * condition always holds, and returns the non-null injected event texts.
     */
    private suspend fun runConditionalEventInject(seed: ULong): List<String> {
        val scenario = Scenario(
            id = "t",
            name = "T",
            description = "d",
            language = "en",
            // Two agents: the validator rejects a single-agent scenario
            // ("Agent count (1) is below minimum of 2") before the run starts.
            agentCount = 2,
            rounds = 1,
            context = "A test.",
            personas = listOf("Alice", "Bob").map {
                Persona(name = it, description = "$it's persona.")
            },
            phases = listOf(
                Phase(
                    type = PhaseType.CONDITIONAL,
                    condition = "current_round >= 1",
                    thenPhases = listOf(
                        Phase(
                            type = PhaseType.EVENT_INJECT,
                            source = "events",
                            probability = 0.5,
                        ),
                    ),
                ),
            ),
            extraData = mapOf("events" to AnyCodableValue.ArrayValue(listOf("大雨", "停電"))),
        )

        val c = Collector()
        SimulationEngine(random = SplitMix64RandomSource(seed = seed))
            .run(scenario, ScriptedLLMBackend(emptyList())) { c.record(it) }
        awaitTerminal(c)

        val events = c.snapshot()
        assertTrue(
            events.any { it is SimulationEvent.SimulationCompleted },
            "the run must complete: $events",
        )
        return events.filterIsInstance<SimulationEvent.EventInjected>().mapNotNull { it.event }
    }
}
