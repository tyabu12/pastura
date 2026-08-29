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
 * scenarios, same seeds, SAME expected sequences — that identity is the point, and
 * it is the first cross-language evidence for the seam, ahead of the Stage-4
 * seeded parity fixtures. A literal that diverges between the two files is a
 * parity break even when both suites are green in isolation.
 *
 * Every expectation below is derived by hand from the SplitMix64 known-answer
 * vectors in [RandomSourceTests] — the seam's reductions are
 * `index(below = n) == nextUInt64() % n` and `unit() == (bits ushr 11) * 2^-53`,
 * so the literals here are checkable without running the code. Each case's KDoc
 * carries its own derivation.
 *
 * **Why full ORDERED sequences rather than one pick.** A single-round assertion
 * over a 2-topic pool passes 1 time in 2 for a seam that silently fell back to the
 * system RNG — most of all in [ConditionalHandler], where dropping `random` from
 * the sub-context reverts only the nested phase. Asserting several rounds of an
 * 8-wide draw puts the false-pass rate at 8⁻³ ≈ 0.2%, which is the difference
 * between a regression guard and a coin flip.
 *
 * Real threads, not `runTest` — see [runBlockingTest]: [SimulationEngine.run]
 * owns its own `Dispatchers.Default` scope, so a virtual scheduler would measure
 * the scheduler rather than the engine.
 */
class RandomSourceSeamTests {

    /**
     * `assign random_one` draws the topic first, then the wolf, once per round —
     * so over three rounds with `SplitMix64RandomSource(seed = 0)` (raw stream
     * `0xE220A8397B1DCDAF`, `0x6E789E6AA1B965F4`, `0x06C45D188009454F`,
     * `0xF88BB8A8724C81EC`, `0x1B39896A51A8749B`, `0x53CB9F0C747EA2EA`) the picks
     * are:
     *
     * - round 1: `% 2 == 1` → the `"みかん"` pair; `% 3 == 0` → `Alice`
     * - round 2: `% 2 == 1` → the `"みかん"` pair; `% 3 == 1` → `Bob`
     * - round 3: `% 2 == 1` → the `"みかん"` pair; `% 3 == 0` → `Alice`
     *
     * Same seed twice ⇒ identical `Assignment` events; that is the property a
     * parity fixture depends on.
     */
    @Test
    fun seededAssignRandomOneIsDeterministic() = runBlockingTest {
        val first = runAssignRandomOne(seed = 0uL)
        val second = runAssignRandomOne(seed = 0uL)

        assertEquals(first, second, "the same seed must replay the same picks")
        assertEquals(
            listOf(
                RoundPick("みかん", "Alice"),
                RoundPick("みかん", "Bob"),
                RoundPick("みかん", "Alice"),
            ),
            first,
        )
    }

    /**
     * A different seed picks a different topic *and* a different wolf, so the
     * assertion above cannot pass by accident on a seam that ignores the injected
     * source. Seed 2's stream is `0x975835DE1C9756CE`, `0xBFC846100BFC1E42`,
     * `0x987BBCBFDD7E532F`, `0xC3F2827AFFE7F664`, `0x4FC446B53F17FB29`,
     * `0x58BC3CB37BC7B2B3`, reducing to:
     *
     * - round 1: `% 2 == 0` → the `"ぶどう"` pair; `% 3 == 2` → `Charlie`
     * - round 2: `% 2 == 1` → the `"みかん"` pair; `% 3 == 0` → `Alice`
     * - round 3: `% 2 == 1` → the `"みかん"` pair; `% 3 == 0` → `Alice`
     */
    @Test
    fun differentSeedPicksDifferentTopicAndWolf() = runBlockingTest {
        assertEquals(
            listOf(
                RoundPick("ぶどう(minority)", "Charlie"),
                RoundPick("みかん", "Alice"),
                RoundPick("みかん", "Alice"),
            ),
            runAssignRandomOne(seed = 2uL),
        )
    }

    /**
     * The critical case: an `event_inject` nested inside a `conditional` branch
     * must see the *injected* source. [ConditionalHandler] builds a fresh
     * sub-[PhaseContext], and omitting `random` there silently reverts the
     * sub-phase to the system RNG.
     *
     * Eight distinct events over three rounds at `probability = 1.0`, so the whole
     * ordered sequence is pinned and a seam that reverted to the system RNG
     * false-passes at most 8⁻³. Each round draws twice: the roll (always `< 1.0`,
     * so it never gates but is still consumed) and the pick. Seed 1's stream is
     * `0x910A2DEC89025CC1`, `0xBEEB8DA1658EEC67`, `0xF893A2EEFB32555E`,
     * `0x71C18690EE42C90B`, `0x71BB54D8D101B5B9`, `0xC34D0BFF90150280`, so the
     * picks are the odd-indexed draws reduced `% 8`: `0x…67 % 8 == 7`,
     * `0x…0B % 8 == 3`, `0x…80 % 8 == 0`.
     */
    @Test
    fun seededEventInjectInsideConditionalFires() = runBlockingTest {
        assertEquals(
            listOf("E7", "E3", "E0"),
            runConditionalEventInject(
                seed = 1uL,
                events = (0 until 8).map { "E$it" },
                rounds = 3,
                probability = 1.0,
            ),
        )
    }

    /**
     * The paired miss: seed 0's first `unit()` is `0.883310…`, which is not
     * `< 0.5`, so the same scenario injects nothing. Together with the case above
     * this pins both sides of the roll to the injected stream.
     */
    @Test
    fun seededEventInjectInsideConditionalMisses() = runBlockingTest {
        assertEquals(
            emptyList(),
            runConditionalEventInject(
                seed = 0uL,
                events = listOf("大雨", "停電"),
                rounds = 1,
                probability = 0.5,
            ),
        )
    }

    /**
     * `no_repeat = true` draws from the shrinking remainder and resets once the
     * pool is exhausted, so the reset-path draw order is a cross-language contract
     * of its own — a Kotlin/Swift disagreement about *when* the reset happens would
     * only show from round 4 onwards.
     *
     * Pool `[N0, N1, N2]`, four rounds, `probability = 1.0` — two draws a round
     * (roll, then pick over `remaining`). Seed 3's stream is `0x1D0B14E4DB018FED`,
     * `0xB3466F8A7B81A989`, `0x9CEBE8A6D050DD01`, `0x12A764FB66ABC9CF`,
     * `0x37688DADCAB79996`, `0xA2DF7737091F4F07`, `0x2298EB42CBBEFDB8`,
     * `0xE3830D21DC859216`:
     *
     * - round 1: remainder `[N0, N1, N2]`, `0xB346… % 3 == 0` → `N0`
     * - round 2: remainder `[N1, N2]`,     `0x12A7… % 2 == 1` → `N2`
     * - round 3: remainder `[N1]`,         `0xA2DF… % 1 == 0` → `N1`
     * - round 4: exhausted → reset to the full pool, `0xE383… % 3 == 1` → `N1`
     *
     * The first three are distinct (no-repeat holding) and the fourth repeats only
     * because the reset draw genuinely lands there — a late repeat after exhaustion
     * is the documented #1006 behaviour.
     */
    @Test
    fun seededNoRepeatDrawsAndResetsInStreamOrder() = runBlockingTest {
        assertEquals(
            listOf("N0", "N2", "N1", "N1"),
            runConditionalEventInject(
                seed = 3uL,
                events = listOf("N0", "N1", "N2"),
                rounds = 4,
                probability = 1.0,
                noRepeat = true,
            ),
        )
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

        val rounds = assignmentRounds(c.snapshot())
        assertEquals(3, rounds.size)
        for (round in rounds) {
            assertEquals(3, round.size)
            assertEquals(
                1,
                round.count { it.second == "みかん" || it.second == "ぶどう(minority)" },
                "exactly one wolf, whatever the platform RNG picked",
            )
        }
    }

    // --- Fixtures ---

    /**
     * Two grouped topics so the topic draw is observable, three agents so the wolf
     * draw is too, and three rounds so the assertion is over a *sequence*. The
     * second pair's majority/minority texts differ from the first's, so a single
     * `Assignment` value identifies both draws.
     */
    private fun wordWolfScenario() = Scenario(
        id = "t",
        name = "T",
        description = "d",
        language = "en",
        agentCount = 3,
        rounds = 3,
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

    /**
     * One round's two draws, read back off the event stream: which topic pair the
     * round drew (identified by its minority text) and which agent got it.
     */
    private data class RoundPick(val minority: String, val wolf: String)

    /**
     * Groups `Assignment` events into per-round chunks of one entry per active
     * agent, preserving emission order within a round.
     */
    private fun assignmentRounds(events: List<SimulationEvent>): List<List<Pair<String, String>>> =
        events.filterIsInstance<SimulationEvent.Assignment>()
            .map { it.agent to it.value }
            .chunked(3)

    /**
     * Drives `assign random_one` through a full [SimulationEngine] run so the
     * engine → [PhaseContext] leg of the seam is covered, not just a hand-built
     * context, and returns the per-round `(topic, wolf)` pair the run drew.
     */
    private suspend fun runAssignRandomOne(seed: ULong): List<RoundPick> {
        val c = Collector()
        SimulationEngine(random = SplitMix64RandomSource(seed = seed))
            .run(wordWolfScenario(), ScriptedLLMBackend(emptyList())) { c.record(it) }
        awaitTerminal(c)

        // `wolf_name` lives in state, which the event stream does not carry, so
        // derive it from the one agent holding a minority value each round.
        return assignmentRounds(c.snapshot()).mapNotNull { round ->
            round.firstOrNull { it.second == "みかん" || it.second == "ぶどう(minority)" }
                ?.let { RoundPick(minority = it.second, wolf = it.first) }
        }
    }

    /**
     * Runs an `event_inject` nested one level inside a `conditional` whose
     * condition always holds, and returns the non-null injected event texts in
     * emission order.
     */
    private suspend fun runConditionalEventInject(
        seed: ULong,
        events: List<String>,
        rounds: Int,
        probability: Double,
        noRepeat: Boolean = false,
    ): List<String> {
        val scenario = Scenario(
            id = "t",
            name = "T",
            description = "d",
            language = "en",
            // Two agents: the validator rejects a single-agent scenario
            // ("Agent count (1) is below minimum of 2") before the run starts.
            agentCount = 2,
            rounds = rounds,
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
                            probability = probability,
                            noRepeat = if (noRepeat) true else null,
                        ),
                    ),
                ),
            ),
            extraData = mapOf("events" to AnyCodableValue.ArrayValue(events)),
        )

        val c = Collector()
        SimulationEngine(random = SplitMix64RandomSource(seed = seed))
            .run(scenario, ScriptedLLMBackend(emptyList())) { c.record(it) }
        awaitTerminal(c)

        val recorded = c.snapshot()
        assertTrue(
            recorded.any { it is SimulationEvent.SimulationCompleted },
            "the run must complete: $recorded",
        )
        return recorded.filterIsInstance<SimulationEvent.EventInjected>().mapNotNull { it.event }
    }
}
