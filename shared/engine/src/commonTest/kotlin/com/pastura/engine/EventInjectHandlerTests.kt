package com.pastura.engine

import com.pastura.models.AnyCodableValue
import com.pastura.models.Persona
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Kotlin port of `Pastura/PasturaTests/Engine/Phases/EventInjectHandlerTests.swift`
 * and its `+NoRepeat` sibling.
 *
 * `event_inject` is a deterministic code phase: boundary probabilities (0.0 / 1.0)
 * and single-element (or pre-seeded 1-element-remainder) sources make every
 * assertion here deterministic without RNG injection — matching the Swift suite.
 *
 * Because Kotlin [SimulationState] is immutable, EVERY assertion reads the
 * **returned** state's `variables` / `drawnEvents`, never the input — a handler
 * (or the `pickWithoutRepeat` helper) that builds a `.copy` but returns the
 * original would silently drop the change.
 *
 * Ported for the ADR-023 Stage-3 code-phase port (#501).
 */
class EventInjectHandlerTests {

    private val handler = EventInjectHandler()

    private fun scenario(
        source: String,
        probability: Double? = null,
        eventVariable: String? = null,
        noRepeat: Boolean? = null,
        extraData: Map<String, AnyCodableValue> = emptyMap(),
        agents: List<String> = listOf("Alice"),
    ) = Scenario(
        id = "t",
        name = "T",
        description = "d",
        language = "en",
        agentCount = agents.size,
        rounds = 2,
        context = "A test.",
        personas = agents.map { Persona(name = it, description = "$it's persona.") },
        phases = listOf(
            Phase(
                type = PhaseType.EVENT_INJECT,
                source = source,
                probability = probability,
                eventVariable = eventVariable,
                noRepeat = noRepeat,
            ),
        ),
        extraData = extraData,
    )

    private fun context(
        scenario: Scenario,
        events: MutableList<SimulationEvent> = mutableListOf(),
    ) = PhaseContext(
        scenario = scenario,
        phase = scenario.phases[0],
        backend = ScriptedLLMBackend(emptyList()),
        suspensionRelay = SuspensionRelay(),
        emitter = { events += it },
        pauseCheck = { },
        phasePath = listOf(0),
        turnGate = TurnFailureGate(),
    )

    /**
     * Extracts every [SimulationEvent.EventInjected] payload, preserving `null`
     * payloads (the "miss" cases) — a filter that dropped them would hide misses.
     */
    private fun injectedEvents(events: List<SimulationEvent>): List<String?> =
        events.filterIsInstance<SimulationEvent.EventInjected>().map { it.event }

    private fun favoredKey(variableName: String = "current_event") =
        EventInjectHandler.favoredVariableName(variableName)

    // MARK: - Probability boundaries

    @Test
    fun firesWhenProbabilityIsOne() = runTest {
        val s = scenario(
            source = "events",
            probability = 1.0,
            extraData = mapOf("events" to AnyCodableValue.ArrayValue(listOf("突然停電"))),
        )
        val events = mutableListOf<SimulationEvent>()
        val next = handler.execute(context(s, events), SimulationState.initial(s))

        assertEquals("突然停電", next.variables["current_event"])
        assertEquals(listOf("突然停電"), injectedEvents(events))
    }

    @Test
    fun missesWhenProbabilityIsZero() = runTest {
        val s = scenario(
            source = "events",
            probability = 0.0,
            extraData = mapOf("events" to AnyCodableValue.ArrayValue(listOf("突然停電"))),
        )
        val events = mutableListOf<SimulationEvent>()
        val next = handler.execute(context(s, events), SimulationState.initial(s))

        // Empty-string write (not absent) so prompts referencing {current_event}
        // expand cleanly without ghosting last round's value.
        assertEquals("", next.variables["current_event"])
        assertEquals(listOf<String?>(null), injectedEvents(events))
    }

    // MARK: - Default probability

    @Test
    fun defaultProbabilityFires() = runTest {
        // probability null → 1.0
        val s = scenario(
            source = "events",
            extraData = mapOf("events" to AnyCodableValue.ArrayValue(listOf("only"))),
        )
        val next = handler.execute(context(s), SimulationState.initial(s))

        assertEquals("only", next.variables["current_event"])
    }

    // MARK: - Custom variable name (`as:`)

    @Test
    fun customVariableNameOverridesDefault() = runTest {
        val s = scenario(
            source = "events",
            probability = 1.0,
            eventVariable = "my_event",
            extraData = mapOf("events" to AnyCodableValue.ArrayValue(listOf("x"))),
        )
        val next = handler.execute(context(s), SimulationState.initial(s))

        assertEquals("x", next.variables["my_event"])
        // Default key untouched.
        assertNull(next.variables["current_event"])
    }

    // MARK: - Source-missing / empty

    @Test
    fun missingSourceEmitsWarningAndMissesCleanly() = runTest {
        // extraData empty — source key absent.
        val s = scenario(source = "nonexistent", probability = 1.0)
        val events = mutableListOf<SimulationEvent>()
        val next = handler.execute(context(s, events), SimulationState.initial(s))

        assertEquals("", next.variables["current_event"])
        assertEquals(listOf<String?>(null), injectedEvents(events))

        val warned = events.any {
            it is SimulationEvent.Summary && it.text.contains("nonexistent")
        }
        assertTrue(warned)
    }

    @Test
    fun absentSourceDoesNotWarn() = runTest {
        // An empty `source:` must NOT emit a Summary warning (Swift L81 guard).
        val s = scenario(source = "", probability = 1.0)
        val events = mutableListOf<SimulationEvent>()
        val next = handler.execute(context(s, events), SimulationState.initial(s))

        assertEquals("", next.variables["current_event"])
        assertEquals(listOf<String?>(null), injectedEvents(events))
        assertTrue(events.none { it is SimulationEvent.Summary })
    }

    @Test
    fun wrongShapeSourceEmitsWarning() = runTest {
        // A non-empty source pointing at a wrong shape (StringValue) IS warned.
        val s = scenario(
            source = "events",
            probability = 1.0,
            extraData = mapOf("events" to AnyCodableValue.StringValue("not a list")),
        )
        val events = mutableListOf<SimulationEvent>()
        val next = handler.execute(context(s, events), SimulationState.initial(s))

        assertEquals("", next.variables["current_event"])
        assertEquals(listOf<String?>(null), injectedEvents(events))
        assertTrue(events.any { it is SimulationEvent.Summary && it.text.contains("events") })
    }

    @Test
    fun emptyArrayBehavesLikeMiss() = runTest {
        val s = scenario(
            source = "events",
            probability = 1.0,
            extraData = mapOf("events" to AnyCodableValue.ArrayValue(emptyList())),
        )
        val events = mutableListOf<SimulationEvent>()
        val next = handler.execute(context(s, events), SimulationState.initial(s))

        assertEquals("", next.variables["current_event"])
        assertEquals(listOf<String?>(null), injectedEvents(events))
    }

    // MARK: - Single-element source determinism

    @Test
    fun singleElementSourceIsDeterministic() = runTest {
        val s = scenario(
            source = "events",
            probability = 1.0,
            extraData = mapOf("events" to AnyCodableValue.ArrayValue(listOf("only"))),
        )
        repeat(5) {
            val next = handler.execute(context(s), SimulationState.initial(s))
            assertEquals("only", next.variables["current_event"])
        }
    }

    // MARK: - Default variable name constant

    @Test
    fun defaultVariableNameMatchesPhaseDocumentation() {
        assertEquals("current_event", EventInjectHandler.defaultVariableName)
    }

    // MARK: - Dict-shaped events + companion favored variable (#931)

    @Test
    fun dictEventWritesTextAndFavoredVariable() = runTest {
        val s = scenario(
            source = "events",
            probability = 1.0,
            extraData = mapOf(
                "events" to AnyCodableValue.ArrayOfDictionariesValue(
                    listOf(mapOf("text" to "抜け駆けが得", "favors" to "betray")),
                ),
            ),
        )
        val events = mutableListOf<SimulationEvent>()
        val next = handler.execute(context(s, events), SimulationState.initial(s))

        assertEquals("抜け駆けが得", next.variables["current_event"])
        assertEquals("betray", next.variables[favoredKey()])
        assertEquals(listOf("抜け駆けが得"), injectedEvents(events))
    }

    @Test
    fun dictEventWithoutFavorsWritesEmptyFavoredVariable() = runTest {
        val s = scenario(
            source = "events",
            probability = 1.0,
            extraData = mapOf(
                "events" to AnyCodableValue.ArrayOfDictionariesValue(
                    listOf(mapOf("text" to "ただの出来事")),
                ),
            ),
        )
        // Pre-seed a stale favored value to prove it gets cleared, not preserved.
        val state = SimulationState.initial(s).copy(variables = mapOf(favoredKey() to "betray"))
        val next = handler.execute(context(s), state)

        assertEquals("ただの出来事", next.variables["current_event"])
        assertEquals("", next.variables[favoredKey()])
    }

    @Test
    fun dictEventMissClearsFavoredVariable() = runTest {
        val s = scenario(
            source = "events",
            probability = 0.0,
            extraData = mapOf(
                "events" to AnyCodableValue.ArrayOfDictionariesValue(
                    listOf(mapOf("text" to "x", "favors" to "betray")),
                ),
            ),
        )
        val state = SimulationState.initial(s).copy(variables = mapOf(favoredKey() to "betray"))
        val events = mutableListOf<SimulationEvent>()
        val next = handler.execute(context(s, events), state)

        assertEquals("", next.variables["current_event"])
        assertEquals("", next.variables[favoredKey()])
        assertEquals(listOf<String?>(null), injectedEvents(events))
    }

    @Test
    fun stringListNeverWritesFavoredVariable() = runTest {
        val s = scenario(
            source = "events",
            probability = 1.0,
            extraData = mapOf("events" to AnyCodableValue.ArrayValue(listOf("突然停電"))),
        )
        val next = handler.execute(context(s), SimulationState.initial(s))

        assertEquals("突然停電", next.variables["current_event"])
        assertNull(next.variables[favoredKey()])
    }

    @Test
    fun dictEventHonorsCustomVariableNameForFavoredKey() = runTest {
        val s = scenario(
            source = "events",
            probability = 1.0,
            eventVariable = "biz_event",
            extraData = mapOf(
                "events" to AnyCodableValue.ArrayOfDictionariesValue(
                    listOf(mapOf("text" to "x", "favors" to "cooperate")),
                ),
            ),
        )
        val next = handler.execute(context(s), SimulationState.initial(s))

        assertEquals("x", next.variables["biz_event"])
        assertEquals("cooperate", next.variables[favoredKey("biz_event")])
        assertNull(next.variables[favoredKey()])
    }

    // MARK: - no_repeat draw without replacement (#1006)

    @Test
    fun noRepeatDrawsFromRemainder() = runTest {
        val s = scenario(
            source = "events",
            probability = 1.0,
            noRepeat = true,
            extraData = mapOf("events" to AnyCodableValue.ArrayValue(listOf("A", "B"))),
        )
        // "A" already drawn → only "B" remains, so the pick is deterministic.
        val state = SimulationState.initial(s).copy(drawnEvents = mapOf("current_event" to setOf("A")))
        val events = mutableListOf<SimulationEvent>()
        val next = handler.execute(context(s, events), state)

        assertEquals("B", next.variables["current_event"])
        assertEquals(setOf("A", "B"), next.drawnEvents["current_event"])
        assertEquals(listOf("B"), injectedEvents(events))
    }

    @Test
    fun noRepeatExhaustedPoolResetsAndDraws() = runTest {
        val s = scenario(
            source = "events",
            probability = 1.0,
            noRepeat = true,
            extraData = mapOf("events" to AnyCodableValue.ArrayValue(listOf("A", "B"))),
        )
        // Both entries drawn → the remainder is empty, forcing a reset+redraw.
        val state = SimulationState.initial(s).copy(drawnEvents = mapOf("current_event" to setOf("A", "B")))
        val next = handler.execute(context(s), state)

        // A miss would blank the variable; instead we reset and redraw a real event.
        val chosen = next.variables["current_event"]
        assertTrue(chosen == "A" || chosen == "B")
        // Reset clears the pool, then adds only the freshly-redrawn entry.
        assertEquals(setOf(chosen), next.drawnEvents["current_event"])
    }

    @Test
    fun noRepeatSingleElementRedrawsAfterReset() = runTest {
        // One-element pool: every round exhausts and resets, so the same event is
        // redrawn deterministically and the drawn-set never grows past 1.
        val s = scenario(
            source = "events",
            probability = 1.0,
            noRepeat = true,
            extraData = mapOf("events" to AnyCodableValue.ArrayValue(listOf("only"))),
        )
        var state = SimulationState.initial(s)
        repeat(3) {
            state = handler.execute(context(s), state)
            assertEquals("only", state.variables["current_event"])
            assertEquals(setOf("only"), state.drawnEvents["current_event"])
        }
    }

    @Test
    fun defaultKeepsWithReplacementAndNeverTouchesDrawnEvents() = runTest {
        // no_repeat absent → existing random() path, drawnEvents untouched.
        val s = scenario(
            source = "events",
            probability = 1.0,
            extraData = mapOf("events" to AnyCodableValue.ArrayValue(listOf("A"))),
        )
        val next = handler.execute(context(s), SimulationState.initial(s))

        assertEquals("A", next.variables["current_event"])
        assertTrue(next.drawnEvents.isEmpty())
    }

    @Test
    fun noRepeatHonorsCustomVariableName() = runTest {
        val s = scenario(
            source = "events",
            probability = 1.0,
            eventVariable = "my_event",
            noRepeat = true,
            extraData = mapOf("events" to AnyCodableValue.ArrayValue(listOf("A", "B"))),
        )
        val state = SimulationState.initial(s).copy(drawnEvents = mapOf("my_event" to setOf("A")))
        val next = handler.execute(context(s), state)

        assertEquals("B", next.variables["my_event"])
        assertEquals(setOf("A", "B"), next.drawnEvents["my_event"])
        // Default key is never used when `as:` is set.
        assertNull(next.drawnEvents["current_event"])
    }

    @Test
    fun noRepeatDictSourcePreservesFavoredVariable() = runTest {
        val s = scenario(
            source = "events",
            probability = 1.0,
            noRepeat = true,
            extraData = mapOf(
                "events" to AnyCodableValue.ArrayOfDictionariesValue(
                    listOf(
                        mapOf("text" to "A", "favors" to "betray"),
                        mapOf("text" to "B", "favors" to "cooperate"),
                    ),
                ),
            ),
        )
        // only "B" remains
        val state = SimulationState.initial(s).copy(drawnEvents = mapOf("current_event" to setOf("A")))
        val next = handler.execute(context(s), state)

        assertEquals("B", next.variables["current_event"])
        assertEquals("cooperate", next.variables[favoredKey()])
        assertEquals(setOf("A", "B"), next.drawnEvents["current_event"])
    }

    @Test
    fun noRepeatMissDoesNotConsumePool() = runTest {
        val s = scenario(
            source = "events",
            probability = 0.0,
            noRepeat = true,
            extraData = mapOf("events" to AnyCodableValue.ArrayValue(listOf("A", "B"))),
        )
        val events = mutableListOf<SimulationEvent>()
        val next = handler.execute(context(s, events), SimulationState.initial(s))

        assertEquals("", next.variables["current_event"])
        // A probability miss injects nothing, so it must not mark anything drawn.
        assertTrue(next.drawnEvents.isEmpty())
        assertEquals(listOf<String?>(null), injectedEvents(events))
    }
}
