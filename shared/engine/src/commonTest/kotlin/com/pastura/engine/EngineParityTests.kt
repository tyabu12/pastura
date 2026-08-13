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
 * diffs — except in one shape: a sentinel that parses but fails the declared
 * canonical-primary check burns the padding into a `TurnSkipped`, and if the
 * diverging call is the run's last the run *completes*, so the overrun surfaces
 * as extra `turn_skipped` / `inference_started` lines instead.
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
     *
     * **For `parityStructuralControl` two of the three are consumed by the
     * expected run, not held as slack.** That fixture's `responses` stops at
     * 2 — Swift's count — while Kotlin is pinned at 4, so Bo's attempts 2 and 3
     * are served by [padScript]: the ledgered structural arm and the pinned
     * call count both run *on* the padding, leaving a margin of one call rather
     * than three. Raising `MAX_RETRIES` without raising this would exhaust the
     * backend inside that arm.
     */
    private val padding = LLMCaller.MAX_RETRIES + 1

    /**
     * A payload no fixture would produce, so consuming one is visible.
     *
     * Deliberately not a copy of the last real answer: that would let an
     * overrun slip into the transcript looking like a plausible turn, and the
     * only signal left would be `callCount`.
     *
     * **"Visible" describes an unintended overrun only** — where it is consumed
     * on purpose it is load-bearing. `parityStructuralControl` reaches its
     * `turn_skipped` *because* this payload parses yet carries no `statement`,
     * the phase's declared canonical primary (`.claude/rules/kmp-interop.md`
     * Pattern 4's empty-primary skip rule). A padding payload satisfying the
     * declared schema would let Bo's attempt 2 succeed instead: measured by
     * making that edit, the fixture reports four uncovered differences and
     * **three** unfired `Structural` entries, so the coupling announces itself
     * rather than silently disarming the arm.
     */
    private fun padScript() =
        ScriptedLLMBackend.Script.completing("""{"__padding__": "unscripted extra call"}""")

    private fun scriptsFor(fixture: ParityGolden.Fixture): List<ScriptedLLMBackend.Script> =
        fixture.responses.map { ScriptedLLMBackend.Script.completing(it) } +
            List(padding) { padScript() }

    private fun scenarioOf(fixture: ParityGolden.Fixture): Scenario =
        json.decodeFromString(Scenario.serializer(), fixture.scenarioJson)

    /**
     * Runs [fixture]'s answers through the Kotlin engine and returns what it saw.
     *
     * The timeout is raised well above `awaitTerminal`'s 5 s default, which was
     * calibrated for the 1–2 round toy runs in `SimulationEngineTests`. A parity
     * fixture is a full run — 24 inferences for the nominal one — doing prompt
     * building, streaming callbacks and JSON parsing while polled at `delay(1)`,
     * and the `macosArm64` rung is the slower of the two. Under the old bound a
     * loaded runner would fail as a timeout that reads like a hang rather than
     * as the parity diff this suite is for.
     *
     * The handle is cancelled on the way out: otherwise a timed-out run keeps
     * executing on `Dispatchers.Default` after its call returned, and since
     * every fixture is replayed from one loop the orphan can overlap the next
     * iteration.
     */
    private suspend fun replay(fixture: ParityGolden.Fixture): Pair<List<SimulationEvent>, Int> {
        val backend = ScriptedLLMBackend(scriptsFor(fixture))
        val collector = Collector()
        val handle = SimulationEngine().run(scenarioOf(fixture), backend) { collector.record(it) }
        try {
            awaitTerminal(collector, timeoutMillis = 30_000)
        } finally {
            handle.cancel()
        }
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
     * alone it puts a diff on every `inference_completed`: 24 in the nominal
     * fixture, which is what this suite reported before the arm existed.
     *
     * **Deliberately here rather than inside [EventLineMapper].** Folding it
     * into the projection would make `EventLineMapperTests`' assertions
     * tautological — pinning a constant instead of the mapper's handling of the
     * payload it was handed.
     *
     * One arm where Swift has two: Swift also strips `agentOutput.rawText`,
     * which Kotlin's `TurnOutput` has no property for. That asymmetry is the
     * point of the Swift arm, not an omission here.
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
     *
     * `Report.isClean` is a conjunction, so a green call asserts both
     * directions at once — an unledgered difference fails, **and** so does a
     * ledger entry that stopped firing. The second is what stops a closed
     * divergence leaving a standing licence behind.
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
        val pinned = DivergenceLedger.callCountDivergences[fixture.name]
        assertEquals(
            pinned?.expectedKotlin ?: fixture.callCount,
            callCount,
            if (pinned == null) {
                "${fixture.name}: the two engines issued different numbers of backend calls, " +
                    "and no retry-budget divergence is ledgered for this fixture. " +
                    "`callCount` sits outside the transcript, so no LedgerEntry shape can key " +
                    "on it — add a DivergenceLedger.callCountDivergences row, or fix the cause."
            } else {
                "${fixture.name}: the ledgered retry-budget divergence " +
                    "(${pinned.divergenceClass}) moved. Swift issues ${fixture.callCount}; " +
                    "Kotlin was pinned at ${pinned.expectedKotlin}. A different surplus is a " +
                    "different divergence — re-derive it rather than widening the pin."
            },
        )
    }

    private fun runBlockingReplay(fixture: ParityGolden.Fixture): Pair<List<SimulationEvent>, Int> {
        var result: Pair<List<SimulationEvent>, Int>? = null
        runBlockingTest { result = replay(fixture) }
        return requireNotNull(result) { "${fixture.name}: the replay produced no result" }
    }

    /**
     * Every fixture in the generated roster, replayed and compared.
     *
     * **Iterated rather than one `@Test` per fixture, which is the hazard
     * [ParityGolden.all] exists to close.** Against hand-listed properties, a
     * fourth fixture would be picked up by `ParityScenarioDecodeTests` and
     * `DivergenceLedgerTests` — both iterate `all` — while never being replayed
     * here, and since `TranscriptComparator.compare` scopes the ledger by
     * fixture name, any entry written for it would be neither applied nor
     * reported unfired. Per-fixture diagnosis survives the merge: every
     * assertion leads with `fixture.name`.
     *
     * A green run means the two engines agree event for event and field for
     * field on every fixture, with only the ledger's own entries excused — for
     * the nominal one that is nothing at all, which
     * [theNominalFixtureExcusesNothing] asserts separately.
     *
     * **The green was falsified before it was believed.** Without [normalize]
     * this reported 24 uncovered differences, one per `inference_completed`,
     * naming the live `durationSeconds` on each — so the two sides are
     * genuinely compared here and the wiring does not pass the golden to
     * itself. `TranscriptComparatorTests` covers the comparator's own ability
     * to redden; nothing but this note covers the wiring.
     */
    @Test
    fun everyGoldenFixtureAgreesWithExactlyItsLedgeredDivergences() {
        // An empty roster would make the loop below green for the wrong reason,
        // and this is now the only replay driver. Asserted here rather than
        // left to `ParityScenarioDecodeTests` so the guard does not depend on a
        // sibling suite still existing.
        assertTrue(ParityGolden.all.isNotEmpty(), "the generated fixture roster is empty")

        for (fixture in ParityGolden.all) {
            assertParity(fixture, DivergenceLedger.entries)
        }
    }

    /**
     * The happy path excuses **nothing** — asserted rather than implied.
     *
     * A property of the ledger's contents rather than of a run, so it needs no
     * replay of its own:
     * [everyGoldenFixtureAgreesWithExactlyItsLedgeredDivergences] does the
     * comparison with the full ledger. Replaying this fixture against
     * `emptyList()` instead would look stronger and be weaker — a
     * nominal-scoped entry added later would simply never run, so the ledger's
     * "an entry that stops firing fails" property would not cover it. This is
     * the other half: nothing may be scoped to the nominal fixture at all.
     */
    @Test
    fun theNominalFixtureExcusesNothing() {
        val fixture = ParityGolden.targetScoreRaceNominal
        val scoped = DivergenceLedger.entries.filter { it.fixture == fixture.name }
        assertTrue(
            scoped.isEmpty(),
            "the happy-path fixture is excusing ${scoped.size} divergence(s), which defeats " +
                "the point of it being the happy path: $scoped",
        )
    }
}
