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
 * [everyKind] reaches every kind — including the ~18 that no fixture drives.
 *
 * **What the pinned lines are and are not evidence of.** Their initial values
 * were derived from the Swift original arm by arm (`EventLineMapper.swift` plus
 * the encoder rules the Swift pin measures), not read back from this mapper's
 * output. Afterwards they buy regression protection, nothing more.
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
     * One value of every [SimulationEvent] kind, paired with the exact line it
     * must project to — or `null` for the two kinds that carry no transcript
     * surface.
     *
     * Built as an exhaustive roster rather than "the kinds the fixtures emit":
     * a kind absent from every fixture is precisely the one whose projection
     * would go unverified, and `EngineParityTests` cannot reach it.
     */
    private fun everyKind(): List<Pair<SimulationEvent, String?>> = listOf(
        SimulationEvent.RoundStarted(round = 1, totalRounds = 4) to
            """{"attempt":0,"event":"round_started","round":1,"t":0,"total_rounds":4,"type":"event"}""",
        SimulationEvent.RoundCompleted(round = 1, scores = mapOf("b" to 1, "a" to 2)) to
            """{"attempt":0,"event":"round_completed","round":1,"scores":{"a":2,"b":1},"t":0,"type":"event"}""",
        SimulationEvent.PhaseStarted(phaseType = PhaseType.VOTE, phasePath = listOf(1, 0)) to
            """{"attempt":0,"event":"phase_started","phase_path":[1,0],"phase_type":"vote","t":0,"type":"event"}""",
        SimulationEvent.PhaseCompleted(phaseType = PhaseType.VOTE, phasePath = listOf(1, 0)) to
            """{"attempt":0,"event":"phase_completed","phase_path":[1,0],"phase_type":"vote","t":0,"type":"event"}""",
        // No `raw_text` key — Kotlin's `TurnOutput` has none, and the Swift
        // emitter strips its own in `ParityFixtureEmitter.normalize`.
        SimulationEvent.AgentOutput(
            agent = "a",
            output = TurnOutput(fields = mapOf("z" to "1", "a" to "2")),
            phaseType = PhaseType.SPEAK_ALL,
        ) to
            """{"agent":"a","attempt":0,"event":"agent_output","fields":{"a":"2","z":"1"},"phase_type":"speak_all","t":0,"type":"event"}""",
        SimulationEvent.AgentOutputStream(agent = "a", primary = "p", thought = "t") to null,
        SimulationEvent.ScoreUpdate(scores = mapOf("b" to 1, "a" to 2)) to
            """{"attempt":0,"event":"score_update","scores":{"a":2,"b":1},"t":0,"type":"event"}""",
        SimulationEvent.Elimination(agent = "a", voteCount = 3) to
            """{"agent":"a","attempt":0,"event":"elimination","t":0,"type":"event","vote_count":3}""",
        SimulationEvent.Assignment(agent = "a", value = "wolf") to
            """{"agent":"a","attempt":0,"event":"assignment","t":0,"type":"event","value":"wolf"}""",
        SimulationEvent.SharedAssignment(value = "topic") to
            """{"attempt":0,"event":"shared_assignment","t":0,"type":"event","value":"topic"}""",
        SimulationEvent.Summary(text = "round over") to
            """{"attempt":0,"event":"summary","t":0,"type":"event","value":"round over"}""",
        SimulationEvent.Narration(text = "and so it went") to
            """{"attempt":0,"event":"narration","t":0,"type":"event","value":"and so it went"}""",
        SimulationEvent.RelationshipUpdate(
            relationships = mapOf("z" to mapOf("b" to -1, "a" to 1), "b" to mapOf("c" to 2)),
        ) to
            """{"attempt":0,"event":"relationship_update","relationships":{"b":{"c":2},"z":{"a":1,"b":-1}},"t":0,"type":"event"}""",
        SimulationEvent.VoteResults(votes = mapOf("a" to "b"), tallies = mapOf("b" to 1)) to
            """{"attempt":0,"event":"vote_results","t":0,"tallies":{"b":1},"type":"event","votes":{"a":"b"}}""",
        // `agent` is `agent1`, and `.convertToSnakeCase` leaves a trailing
        // digit alone — `agent2` / `action1`, not `agent_2` / `action_1`.
        // Measured Swift-side, not derived from the strategy's documentation.
        SimulationEvent.PairingResult(agent1 = "a", action1 = "x", agent2 = "b", action2 = "y") to
            """{"action1":"x","action2":"y","agent":"a","agent2":"b","attempt":0,"event":"pairing_result","t":0,"type":"event"}""",
        SimulationEvent.ConditionalEvaluated(condition = "s >= 1", result = true) to
            """{"attempt":0,"condition":"s >= 1","event":"conditional_evaluated","result":true,"t":0,"type":"event"}""",
        SimulationEvent.EventInjected(event = "storm") to
            """{"attempt":0,"event":"event_injected","t":0,"type":"event","value":"storm"}""",
        SimulationEvent.SimulationCompleted to
            """{"attempt":0,"event":"simulation_completed","t":0,"type":"event"}""",
        SimulationEvent.RoundCheckpoint(state = SimulationState.initial(scenario)) to null,
        SimulationEvent.SimulationPaused(round = 1, phasePath = listOf(0)) to
            """{"attempt":0,"event":"simulation_paused","phase_path":[0],"round":1,"t":0,"type":"event"}""",
        // The case NAME, deliberately: `SimulationError`'s singletons are plain
        // `object`s, so `toString()` yields an identity hash that changes every
        // run. See the arm's comment in `EventLineMapper`.
        SimulationEvent.ErrorEvent(error = SimulationError.Cancelled) to
            """{"attempt":0,"error":"Cancelled","event":"error","t":0,"type":"event"}""",
        SimulationEvent.InferenceStarted(agent = "a") to
            """{"agent":"a","attempt":0,"event":"inference_started","t":0,"type":"event"}""",
        SimulationEvent.InferenceCompleted(agent = "a", durationSeconds = 0.0, tokenCount = 7) to
            """{"agent":"a","attempt":0,"duration_seconds":0,"event":"inference_completed","t":0,"token_count":7,"type":"event"}""",
        SimulationEvent.LanguageMismatch(agent = "a", detected = "en", expected = "ja") to
            """{"agent":"a","attempt":0,"detected":"en","event":"language_mismatch","expected":"ja","t":0,"type":"event"}""",
        SimulationEvent.TurnSkipped(
            agent = "a",
            phaseType = PhaseType.SPEAK_ALL,
            cause = "retries exhausted",
        ) to
            """{"agent":"a","attempt":0,"event":"turn_skipped","phase_type":"speak_all","t":0,"type":"event","value":"retries exhausted"}""",
        SimulationEvent.ActionRejected(agent = "a", phaseType = PhaseType.CHOOSE, raw = "shrug") to
            """{"agent":"a","attempt":0,"event":"action_rejected","phase_type":"choose","t":0,"type":"event","value":"shrug"}""",
    )

    /**
     * Every arm projects to its pinned line.
     *
     * The assertion that makes the roster worth having: the alternative
     * coverage, "does not return null", passes on a wrong key name or a swapped
     * payload.
     */
    @Test
    fun everyKindProjectsToItsPinnedLine() {
        for ((event, expected) in everyKind()) {
            assertEquals(expected, EventLineMapper.map(event), event::class.simpleName)
        }
    }

    @Test
    fun everyKindExceptStreamAndCheckpointProducesALine() {
        val skipped = everyKind().filter { it.second == null }.map { it.first::class.simpleName }
        // Compared as a set: a pure reorder of the roster is not a regression,
        // and an ordered comparison would redden for that non-reason.
        assertEquals(
            setOf("AgentOutputStream", "RoundCheckpoint"),
            skipped.toSet(),
            "the set of kinds projecting to null changed",
        )
    }

    /**
     * Keeps [everyKind] honest about being a roster rather than a sample.
     *
     * **This is a pin, not a proof, and the distinction is load-bearing.** The
     * check that would prove coverage — `SimulationEvent::class.sealedSubclasses`
     * — is JVM-only reflection, unavailable in a suite that must also run on
     * `macosArm64` (ADR-023 Decision 5). What genuinely breaks on a new
     * `SimulationEvent` case is [EventLineMapper]'s `else`-free `when`; this
     * assertion's narrower job is to make the author who just fixed that
     * compile error notice the roster needs the case too.
     *
     * Same shape as `PhaseTypeTests`' `allCases.count == 14` pin, with the same
     * weakness: bumping the number is as easy as adding the entry.
     */
    @Test
    fun theRosterIsOneEntryPerKindAndItsSizeIsPinned() {
        val kinds = everyKind().map { it.first::class.simpleName }
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
    }

    @Test
    fun nullPayloadFieldsAreOmittedRatherThanEncodedAsNull() {
        // `tokenCount` and `detected` are the two nullable payload fields the
        // projection reads; Swift omits a `nil` rather than writing `null`.
        // Their non-null shapes are pinned in the roster above, so neither
        // assertion can pass because the key never appears at all.
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
    }
}
