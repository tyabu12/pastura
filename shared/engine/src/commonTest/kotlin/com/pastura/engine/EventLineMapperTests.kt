package com.pastura.engine

import com.pastura.models.Persona
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import com.pastura.models.SimulationError
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState
import com.pastura.models.TurnOutput
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Unit coverage for the [EventLineMapper] mirror.
 *
 * These pin the projection's own wire shape against the **measured** Swift
 * bytes (`RunLogTests.fullyPopulatedLinePinsTheWireShape` in the harness test
 * target), so the encoder-level differences kotlinx would otherwise introduce —
 * declaration-order keys, `null` emission, `0.0` for an integral double — fail
 * here rather than as a wall of uncovered diffs in `EngineParityTests`.
 *
 * They do not replace the end-to-end fixtures and are not replaced by them: a
 * fixture exercises whichever events its scenario happens to produce, while
 * these reach every kind, including the ones no current fixture drives.
 */
class EventLineMapperTests {

    private val scenario = Scenario(
        id = "t",
        name = "T",
        description = "d",
        language = "en",
        agentCount = 1,
        rounds = 1,
        context = "A test.",
        personas = listOf(Persona(name = "Alice", description = "Alice's persona.")),
        phases = listOf(Phase(type = PhaseType.SPEAK_ALL, prompt = "Speak.")),
    )

    /**
     * One value of every [SimulationEvent] kind.
     *
     * Built as an exhaustive roster rather than "the kinds the fixtures emit":
     * a kind absent from both fixtures is precisely the one whose projection
     * would go unverified, and `EngineParityTests` cannot reach it. Kept as a
     * `List` the tests iterate, so adding a kind here covers it everywhere at
     * once.
     */
    private fun everyKind(): List<SimulationEvent> = listOf(
        SimulationEvent.RoundStarted(round = 1, totalRounds = 4),
        SimulationEvent.RoundCompleted(round = 1, scores = mapOf("b" to 1, "a" to 2)),
        SimulationEvent.PhaseStarted(phaseType = PhaseType.VOTE, phasePath = listOf(1, 0)),
        SimulationEvent.PhaseCompleted(phaseType = PhaseType.VOTE, phasePath = listOf(1, 0)),
        SimulationEvent.AgentOutput(
            agent = "a",
            output = TurnOutput(fields = mapOf("z" to "1", "a" to "2")),
            phaseType = PhaseType.SPEAK_ALL,
        ),
        SimulationEvent.AgentOutputStream(agent = "a", primary = "p", thought = "t"),
        SimulationEvent.ScoreUpdate(scores = mapOf("b" to 1, "a" to 2)),
        SimulationEvent.Elimination(agent = "a", voteCount = 3),
        SimulationEvent.Assignment(agent = "a", value = "wolf"),
        SimulationEvent.SharedAssignment(value = "topic"),
        SimulationEvent.Summary(text = "round over"),
        SimulationEvent.Narration(text = "and so it went"),
        SimulationEvent.RelationshipUpdate(
            relationships = mapOf("z" to mapOf("b" to -1, "a" to 1), "b" to mapOf("c" to 2)),
        ),
        SimulationEvent.VoteResults(votes = mapOf("a" to "b"), tallies = mapOf("b" to 1)),
        SimulationEvent.PairingResult(agent1 = "a", action1 = "x", agent2 = "b", action2 = "y"),
        SimulationEvent.ConditionalEvaluated(condition = "s >= 1", result = true),
        SimulationEvent.EventInjected(event = "storm"),
        SimulationEvent.SimulationCompleted,
        SimulationEvent.RoundCheckpoint(state = SimulationState.initial(scenario)),
        SimulationEvent.SimulationPaused(round = 1, phasePath = listOf(0)),
        SimulationEvent.ErrorEvent(error = SimulationError.Cancelled),
        SimulationEvent.InferenceStarted(agent = "a"),
        SimulationEvent.InferenceCompleted(agent = "a", durationSeconds = 0.0, tokenCount = 7),
        SimulationEvent.LanguageMismatch(agent = "a", detected = "en", expected = "ja"),
        SimulationEvent.TurnSkipped(
            agent = "a",
            phaseType = PhaseType.SPEAK_ALL,
            cause = "retries exhausted",
        ),
        SimulationEvent.ActionRejected(
            agent = "a",
            phaseType = PhaseType.CHOOSE,
            raw = "shrug",
        ),
    )

    @Test
    fun everyKindExceptStreamAndCheckpointProducesALine() {
        val skipped = everyKind().filter { EventLineMapper.map(it) == null }
        assertEquals(
            listOf("AgentOutputStream", "RoundCheckpoint"),
            skipped.map { it::class.simpleName },
            "the set of kinds projecting to null changed",
        )
    }

    /**
     * Keeps [everyKind] honest about being a roster rather than a sample.
     *
     * **This is a pin, not a proof, and the distinction is load-bearing.** The
     * check that would actually prove coverage —
     * `SimulationEvent::class.sealedSubclasses` — is JVM-only reflection, and
     * this suite must also compile and run on `macosArm64` per ADR-023
     * Decision 5, so it is unavailable here. What genuinely breaks on a new
     * `SimulationEvent` case is [EventLineMapper]'s `else`-free `when`; this
     * assertion's job is narrower — to make the author who just fixed that
     * compile error notice that the roster needs the case too, instead of
     * leaving the projection they just wrote unasserted.
     *
     * Same shape as `PhaseTypeTests`' `allCases.count == 14` pin, and it shares
     * that pin's weakness: bumping the number is as easy as adding the entry.
     */
    @Test
    fun theRosterIsOneEntryPerKindAndItsSizeIsPinned() {
        val kinds = everyKind().map { it::class.simpleName }
        assertEquals(
            kinds.size,
            kinds.toSet().size,
            "everyKind() lists the same SimulationEvent kind twice: $kinds",
        )
        assertEquals(
            26,
            kinds.size,
            "SimulationEvent gained or lost a case — add it to everyKind() and update this pin",
        )
    }

    @Test
    fun projectedLinesMatchTheSwiftWireShape() {
        assertEquals(
            """{"attempt":0,"event":"round_started","round":1,"t":0,"total_rounds":4,"type":"event"}""",
            EventLineMapper.map(SimulationEvent.RoundStarted(round = 1, totalRounds = 4)),
        )
        assertEquals(
            """{"attempt":0,"event":"phase_started","phase_path":[1,0],"phase_type":"vote","t":0,"type":"event"}""",
            EventLineMapper.map(
                SimulationEvent.PhaseStarted(phaseType = PhaseType.VOTE, phasePath = listOf(1, 0)),
            ),
        )
        // No `raw_text` key — Kotlin's `TurnOutput` has none, and the Swift
        // emitter strips its own in `ParityFixtureEmitter.normalize`.
        assertEquals(
            """{"agent":"a","attempt":0,"event":"agent_output","fields":{"a":"2","z":"1"},"phase_type":"speak_all","t":0,"type":"event"}""",
            EventLineMapper.map(
                SimulationEvent.AgentOutput(
                    agent = "a",
                    output = TurnOutput(fields = mapOf("z" to "1", "a" to "2")),
                    phaseType = PhaseType.SPEAK_ALL,
                ),
            ),
        )
        // `agent2` / `action1` keep their trailing digit: Swift's
        // `.convertToSnakeCase` splits on uppercase only, so it leaves them
        // alone while turning `totalRounds` into `total_rounds`. Measured
        // Swift-side (`RunLogTests.fullyPopulatedLinePinsTheWireShape`), not
        // derived from the strategy's documentation — the plausible-looking
        // `agent_2` would have gone unnoticed until a `choose` fixture landed.
        assertEquals(
            """{"action1":"x","action2":"y","agent":"a","agent2":"b","attempt":0,"event":"pairing_result","t":0,"type":"event"}""",
            EventLineMapper.map(
                SimulationEvent.PairingResult(
                    agent1 = "a",
                    action1 = "x",
                    agent2 = "b",
                    action2 = "y",
                ),
            ),
        )
    }

    @Test
    fun integralDoublesDropTheirDecimalAndFractionalOnesKeepIt() {
        val integral = assertNotNull(
            EventLineMapper.map(SimulationEvent.InferenceStarted(agent = "a"), t = 0.0),
        )
        assertTrue(
            integral.contains(""""t":0,"""),
            "an integral t rendered with a decimal, which every line would carry: $integral",
        )

        val fractional = assertNotNull(
            EventLineMapper.map(SimulationEvent.InferenceStarted(agent = "a"), t = 1.5),
        )
        assertTrue(
            fractional.contains(""""t":1.5"""),
            "a fractional t lost its decimals — the renderer truncates instead of " +
                "dropping a trailing .0: $fractional",
        )

        val duration = assertNotNull(
            EventLineMapper.map(
                SimulationEvent.InferenceCompleted(agent = "a", durationSeconds = 0.0),
            ),
        )
        assertTrue(
            duration.contains(""""duration_seconds":0,"""),
            "duration_seconds rendered with a decimal: $duration",
        )
    }

    @Test
    fun nullPayloadFieldsAreOmittedRatherThanEncodedAsNull() {
        // `tokenCount` and `detected` are the two nullable payload fields the
        // projection reads; Swift omits a `nil` rather than writing `null`.
        val noTokens = assertNotNull(
            EventLineMapper.map(
                SimulationEvent.InferenceCompleted(
                    agent = "a",
                    durationSeconds = 0.0,
                    tokenCount = null,
                ),
            ),
        )
        assertTrue("token_count" !in noTokens, "a null token_count was encoded: $noTokens")
        assertTrue("null" !in noTokens, "a null leaked into the line: $noTokens")

        val noDetected = assertNotNull(
            EventLineMapper.map(
                SimulationEvent.LanguageMismatch(agent = "a", detected = null, expected = "ja"),
            ),
        )
        assertTrue("detected" !in noDetected, "a null detected was encoded: $noDetected")

        // …and the same field IS present when non-null, so the assertions above
        // are not passing because the key never appears at all.
        val withTokens = assertNotNull(
            EventLineMapper.map(
                SimulationEvent.InferenceCompleted(
                    agent = "a",
                    durationSeconds = 0.0,
                    tokenCount = 7,
                ),
            ),
        )
        assertTrue(""""token_count":7""" in withTokens, "token_count went missing: $withTokens")
    }

    @Test
    fun nestedMapsSortAtEveryDepth() {
        val line = assertNotNull(
            EventLineMapper.map(
                SimulationEvent.RelationshipUpdate(
                    relationships = mapOf("z" to mapOf("b" to -1, "a" to 1), "b" to mapOf("c" to 2)),
                ),
            ),
        )
        assertEquals(
            """{"attempt":0,"event":"relationship_update","relationships":{"b":{"c":2},"z":{"a":1,"b":-1}},"t":0,"type":"event"}""",
            line,
        )
    }

    @Test
    fun theTwoSkippedKindsProduceNoLine() {
        assertNull(
            EventLineMapper.map(SimulationEvent.AgentOutputStream(agent = "a", primary = "p")),
        )
        assertNull(
            EventLineMapper.map(
                SimulationEvent.RoundCheckpoint(state = SimulationState.initial(scenario)),
            ),
        )
    }
}
