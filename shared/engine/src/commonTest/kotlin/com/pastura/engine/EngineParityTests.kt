package com.pastura.engine

import com.pastura.engine.DivergenceLedger.LedgerEntry
import com.pastura.models.Scenario
import com.pastura.models.SimulationEvent
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.serialization.json.Json

/**
 * ADR-023 Stage 4: replays a frozen Swift run through the Kotlin engine and
 * compares the transcripts.
 *
 * This is the slice-1b payload — before it, `ParityGolden`, [DivergenceLedger]
 * and [TranscriptComparator] were three unconnected pieces and **no code
 * compared the two engines** (#501, 2026-08-06).
 *
 * ## What a green run here means
 *
 * For the nominal fixture, green with an **empty** ledger. That is Stage 4's
 * actual goal — not that the harness runs, but that the two engines agree with
 * nothing excused. Any diff must therefore be dispositioned rather than
 * ledgered by reflex:
 *
 * - a defect on a **ported** surface is dual-landed (fix Kotlin, regenerate the
 *   golden) — ADR-023 §12 condition 3's chosen regime, and the intended path;
 * - a diff matching an already-documented `DivergenceClass` becomes a ledger
 *   entry;
 * - an RNG-bearing or unported-handler surface belongs to S3, not here.
 *
 * ## Why the backend is over-scripted
 *
 * `ScriptedLLMBackend` throws on exhaustion by design, and that throw would
 * **pre-empt the assertions below** — the test would redden without
 * [ParityGolden.Fixture.callCount] ever being checked, reporting a harness
 * fault in place of the retry-budget divergence it exists to detect
 * (`.claude/rules/kmp-interop.md` Pattern 4). So the script list is padded and
 * the written assertion stays the detector.
 *
 * An overrun past the padding does **not** hang: `SimulationEngine`'s
 * `executePhases` carries a `catch (e: Throwable)` arm, so the
 * `IllegalStateException` becomes an `ErrorEvent` and the run terminates
 * normally. [assertRunCompleted] catches that ahead of the transcript
 * comparison, so an overrun reports as an overrun rather than as a wall of
 * diffs.
 */
class EngineParityTests {

    /**
     * Strict, matching [ParityScenarioDecodeTests] — an unknown key is drift to
     * surface, not noise to swallow.
     */
    private val json = Json { ignoreUnknownKeys = false }

    /**
     * Extra scripts beyond the fixture's own answers.
     *
     * `MAX_RETRIES + 1` (`LLMCaller.MAX_RETRIES` is 2, so 3): one full retry
     * window plus one, which is the smallest padding that lets a diverging
     * Kotlin run consume a whole extra turn's budget and still reach the
     * assertions.
     */
    private val padding = LLMCaller.MAX_RETRIES + 1

    /**
     * A payload no fixture would produce, so consuming one is visible.
     *
     * Deliberately not a copy of the last real answer: that would let an
     * overrun slip into the transcript looking like a plausible turn, and the
     * only signal left would be `callCount`.
     */
    private fun padScript() =
        ScriptedLLMBackend.Script.completing("""{"__padding__": "unscripted extra call"}""")

    private fun scriptsFor(fixture: ParityGolden.Fixture): List<ScriptedLLMBackend.Script> =
        fixture.responses.map { ScriptedLLMBackend.Script.completing(it) } +
            List(padding) { padScript() }

    private fun scenarioOf(fixture: ParityGolden.Fixture): Scenario =
        json.decodeFromString(Scenario.serializer(), fixture.scenarioJson)

    /** Runs [fixture]'s answers through the Kotlin engine and returns what it saw. */
    private suspend fun replay(fixture: ParityGolden.Fixture): Pair<List<SimulationEvent>, Int> {
        val backend = ScriptedLLMBackend(scriptsFor(fixture))
        val collector = Collector()
        SimulationEngine().run(scenarioOf(fixture), backend) { collector.record(it) }
        awaitTerminal(collector)
        return collector.snapshot() to backend.callCount
    }

    /**
     * Fails on a run that ended in an error, naming the padding overrun first.
     *
     * Checked BEFORE the transcript comparison: an aborted run produces a
     * truncated transcript, so comparing first would bury the cause under every
     * event the run never reached.
     */
    private fun assertRunCompleted(fixture: ParityGolden.Fixture, events: List<SimulationEvent>) {
        val terminal = events.lastOrNull()
        if (terminal is SimulationEvent.ErrorEvent) {
            val error = terminal.error.toString()
            val overran = "ScriptedLLMBackend exhausted" in error
            throw AssertionError(
                if (overran) {
                    "${fixture.name}: the Kotlin engine issued more than " +
                        "${fixture.responses.size} + $padding backend calls, so it consumed the " +
                        "padding and ran dry. That is a retry-budget divergence, not a harness " +
                        "fault: $error"
                } else {
                    "${fixture.name}: the run ended with an error rather than completing: $error"
                },
            )
        }
        assertTrue(
            terminal is SimulationEvent.SimulationCompleted,
            "${fixture.name}: the run did not reach a terminal event — last was $terminal",
        )
    }

    private fun transcriptOf(events: List<SimulationEvent>): List<String> =
        events.mapNotNull { EventLineMapper.map(normalize(it)) }

    /**
     * Zeroes the one measured quantity a `SimulationEvent` payload carries,
     * mirroring `ParityFixtureEmitter.normalize` on the Swift side.
     *
     * `durationSeconds` is wall-clock, measured per call. The Swift emitter
     * zeroes it before freezing the golden — otherwise `parity-emit --check`
     * would report drift against itself — so the replay side must zero it too
     * or the comparison measures two machines rather than two engines. Left
     * alone it puts a diff on every `inference_completed`: 24 of them in the
     * nominal fixture, which is exactly what this suite reported before the arm
     * existed.
     *
     * **Deliberately here rather than inside [EventLineMapper].** Folding it
     * into the projection would make `EventLineMapperTests`' assertions
     * tautological — they would be pinning a constant instead of the mapper's
     * handling of the payload it was handed.
     *
     * One arm where Swift has two: Swift also strips `agentOutput.rawText`, and
     * Kotlin's `TurnOutput` carries no such property to strip. That asymmetry
     * is the point of the Swift arm, not an omission here.
     */
    private fun normalize(event: SimulationEvent): SimulationEvent =
        if (event is SimulationEvent.InferenceCompleted) {
            event.copy(durationSeconds = 0.0)
        } else {
            event
        }

    /**
     * Compares one fixture against [ledger] and fails with the report's own text.
     *
     * `Report.describe()` leads with the desync note when the walk lost
     * alignment, which is the first thing to act on — so it is passed through
     * verbatim rather than summarized.
     */
    private fun assertParity(fixture: ParityGolden.Fixture, ledger: List<LedgerEntry>) {
        val (events, callCount) = runBlockingReplay(fixture)
        assertRunCompleted(fixture, events)

        val report = TranscriptComparator.compare(
            fixture = fixture.name,
            swift = fixture.transcript,
            kotlin = transcriptOf(events),
            ledger = ledger,
        )
        assertTrue(report.isClean, "${fixture.name}:\n${report.describe()}")

        // After the transcript, not before: a call-count difference with an
        // identical transcript is the interesting case, and putting this first
        // would mask the transcript diff that usually explains it.
        assertEquals(
            fixture.callCount,
            callCount,
            "${fixture.name}: the two engines issued different numbers of backend calls. " +
                "This is a hard failure by design — `callCount` sits outside the transcript, " +
                "so no LedgerEntry shape can key on it.",
        )
    }

    private fun runBlockingReplay(fixture: ParityGolden.Fixture): Pair<List<SimulationEvent>, Int> {
        var result: Pair<List<SimulationEvent>, Int>? = null
        runBlockingTest { result = replay(fixture) }
        return requireNotNull(result) { "${fixture.name}: the replay produced no result" }
    }

    /**
     * The happy path, with **nothing excused**.
     *
     * "Nothing excused" is asserted rather than implied: the full ledger is
     * passed in, and the first assertion is that none of it is scoped to this
     * fixture. Passing `emptyList()` instead would look stronger and be weaker
     * — a nominal-scoped entry added later would simply never run, so the
     * ledger's "an entry that stops firing fails" property would not cover it.
     *
     * Given that, a green run means the two engines agree event for event and
     * field for field across a full four-round run: 24 inferences, a vote
     * tally, a conditional branch, and the summarize template on both arms.
     *
     * **The green was falsified before it was believed.** Without [normalize]
     * this reported 24 uncovered differences, one per `inference_completed`,
     * naming the live `durationSeconds` on each — so the two sides are
     * genuinely being compared here, and the wiring does not pass the golden to
     * itself. `TranscriptComparatorTests` covers the comparator's own ability
     * to redden; this note covers the wiring, which nothing else does.
     */
    @Test
    fun theNominalFixtureAgreesWithNothingExcused() {
        val fixture = ParityGolden.targetScoreRaceNominal
        val scoped = DivergenceLedger.entries.filter { it.fixture == fixture.name }
        assertTrue(
            scoped.isEmpty(),
            "the happy-path fixture is excusing ${scoped.size} divergence(s), which defeats " +
                "the point of it being the happy path: $scoped",
        )
        assertParity(fixture, DivergenceLedger.entries)
    }

    /**
     * The negative control: the ledger's entries must all fire, and nothing
     * else may differ.
     *
     * `Report.isClean` is a conjunction, so this asserts both directions at
     * once — an unledgered difference fails, **and** so does a ledger entry
     * that stopped firing. The second is what stops a closed divergence
     * leaving a standing licence behind.
     */
    @Test
    fun theDivergentFixtureDrivesExactlyItsLedgeredDivergences() {
        assertParity(ParityGolden.targetScoreRaceDivergent, DivergenceLedger.entries)
    }
}
