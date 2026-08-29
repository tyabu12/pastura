package com.pastura.engine

import com.pastura.engine.DivergenceLedger.LedgerEntry
import com.pastura.models.Scenario
import com.pastura.models.SimulationError
import com.pastura.models.SimulationEvent
import kotlin.concurrent.atomics.AtomicBoolean
import kotlin.concurrent.atomics.AtomicReference
import kotlin.concurrent.atomics.ExperimentalAtomicApi
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
@OptIn(ExperimentalAtomicApi::class)
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
     * fixture is a full run — 24 inferences for `targetScoreRaceNominal`, 38 for
     * `prisonersDilemmaNominal`, 36 for the three-round `lastFableNominal` —
     * doing prompt building, streaming callbacks and JSON parsing while polled
     * at `delay(1)`, and the `macosArm64` rung was the slower of the two when
     * the bound was set (measured 2026-08-29 with eight fixtures: 0.15 s for
     * the whole roster on `macosArm64`, 0.48 s on the JVM — so the bound is
     * headroom, not a budget). Under the old bound a
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
        // Null for every fixture that runs to completion, so the callback below
        // is exactly what it was before the cancelling arm landed.
        val cutter = fixture.cancelAfterPhaseCompleted?.let { CancelOnPhaseCompleted(it) }
        // A seeded fixture must feed both engines the same stream, so the replay
        // rebuilds SplitMix64 from the seed the Swift run used; an unseeded one is
        // RNG-free by construction, where the source is unobservable. The Swift
        // `seededSpecsAreExactlyTheDrawingOnes` guard holds both directions, so a
        // null seed here means the scenario draws nothing, not that the seed was
        // dropped on the way across.
        val random =
            fixture.seed?.let { SplitMix64RandomSource(it) } ?: SystemRandomSource()
        val handle =
            SimulationEngine(random = random).run(scenarioOf(fixture), backend) {
                // Recorded BEFORE the cut is requested, so the triggering event is
                // itself in the transcript — it is the Swift golden's second-to-last
                // line, not something the cancellation swallows.
                collector.record(it)
                cutter?.observe(it)
            }
        // `run` installs the callback and only then returns the handle, so the
        // trigger can fire before this line. [CancelOnPhaseCompleted] latches that
        // case and cancels here instead of dropping it.
        cutter?.adopt(handle)
        try {
            awaitTerminal(collector, timeoutMillis = 30_000)
        } finally {
            handle.cancel()
        }
        if (cutter != null && !cutter.fired) {
            throw AssertionError(
                "${fixture.name}: the replay never emitted phase_completed " +
                    "${fixture.cancelAfterPhaseCompleted}, so the run was never cancelled and " +
                    "this fixture compared a completed run against a cancelled golden. The " +
                    "Swift emitter raises `cancelTriggerNeverFired` on the same condition.",
            )
        }
        return collector.snapshot() to backend.callCount
    }

    /**
     * Cancels the run the moment a `PhaseCompleted` with [path] is recorded.
     *
     * **The trigger is an emitted-event position, not a backend call index** —
     * `ParityFixtureEmitter.FixtureSpec.cancelAfterPhaseCompleted` carries the
     * reasoning, and this class is its Kotlin half: Kotlin's [LLMCaller] observes
     * cancellation from *inside* a backend call while the Swift responder does
     * not, so a call-indexed cut would land at different logical points on the two
     * engines and the transcript diff would be about where the harness cut rather
     * than about how the engines unwind. On the event position both are at the head
     * of `ConditionalHandler`'s sub-phase loop, where Swift polls `Task.isCancelled`
     * and Kotlin's `pauseCheck` raises.
     *
     * Atomics rather than plain fields because `onEvent` fires from
     * `Dispatchers.Default` while [adopt] runs on the test's thread — the same
     * reason [Collector] uses one — and because the latch must fire exactly once:
     * a fixture whose path repeats across rounds would otherwise cancel twice,
     * which is harmless today only by accident.
     */
    private class CancelOnPhaseCompleted(private val path: List<Int>) {
        private val handle = AtomicReference<RunHandle?>(null)
        private val pendingCancel = AtomicBoolean(false)
        private val triggered = AtomicBoolean(false)

        /** Whether the trigger event was ever seen. */
        val fired: Boolean get() = triggered.load()

        /** Stores the run's handle, cancelling now when the trigger already fired. */
        fun adopt(runHandle: RunHandle) {
            handle.store(runHandle)
            if (pendingCancel.load()) runHandle.cancel()
        }

        /** Cancels the run when [event] is the trigger; ignores everything else. */
        fun observe(event: SimulationEvent) {
            if (event !is SimulationEvent.PhaseCompleted || event.phasePath != path) return
            if (!triggered.compareAndSet(false, true)) return
            val runHandle = handle.load()
            if (runHandle == null) pendingCancel.store(true) else runHandle.cancel()
        }
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
        val cancelling = fixture.cancelAfterPhaseCompleted != null
        if (terminal is SimulationEvent.ErrorEvent) {
            // A cancelling fixture's whole point is that `ErrorEvent(Cancelled)` IS
            // the terminal event — checked before the overrun arm, which would
            // otherwise report the expected tail as a failure.
            if (cancelling && terminal.error == SimulationError.Cancelled) return
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
        // A cancelled run must NOT complete: `SimulationCompleted` here means the
        // cut never took effect, which is the failure the Swift fix (#1622) exists
        // to prevent — the branch would have gone on to run its second sub-phase.
        if (cancelling) {
            throw AssertionError(
                "${fixture.name}: cancelled after phase_completed " +
                    "${fixture.cancelAfterPhaseCompleted}, so the terminal event must be " +
                    "ErrorEvent(Cancelled) — it was $terminal",
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
     * the nominal ones that is nothing at all, which
     * [theNominalFixturesExcuseNothing] asserts separately.
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
     * The happy paths excuse **nothing** — asserted rather than implied.
     *
     * A property of the ledger's contents rather than of a run, so it needs no
     * replay of its own:
     * [everyGoldenFixtureAgreesWithExactlyItsLedgeredDivergences] does the
     * comparison with the full ledger. Replaying these fixtures against
     * `emptyList()` instead would look stronger and be weaker — a
     * nominal-scoped entry added later would simply never run, so the ledger's
     * "an entry that stops firing fails" property would not cover it. This is
     * the other half: nothing may be scoped to a nominal fixture at all.
     *
     * **Derived from [ParityGolden.all] by name suffix, not hand-listed.** A
     * second nominal fixture named as a property here would have been the
     * obvious edit and the silent one: the next happy path added would keep
     * passing without ever being checked. The suffix convention is what the
     * emitter's spec names already follow, and the roster guard below stops it
     * from going vacuous if that convention is ever dropped.
     */
    @Test
    fun theNominalFixturesExcuseNothing() {
        val nominal = ParityGolden.all.filter { it.name.endsWith("Nominal") }
        // A floor, not just non-emptiness: renaming one happy path off the
        // suffix would drop it from this check while the others kept it green.
        // Raise the floor when a nominal fixture is added; never lower it.
        assertTrue(
            nominal.size >= 6,
            "only ${nominal.map { it.name }} end with \"Nominal\" (expected at least 6) — " +
                "either a happy-path fixture was lost or the naming convention moved",
        )
        for (fixture in nominal) {
            val scoped = DivergenceLedger.entries.filter { it.fixture == fixture.name }
            assertTrue(
                scoped.isEmpty(),
                "${fixture.name}: the happy-path fixture is excusing ${scoped.size} " +
                    "divergence(s), which defeats the point of it being the happy path: $scoped",
            )
        }
    }
}
