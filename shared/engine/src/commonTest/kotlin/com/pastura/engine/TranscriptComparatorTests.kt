package com.pastura.engine

import com.pastura.engine.DivergenceLedger.DivergenceClass
import com.pastura.engine.DivergenceLedger.LedgerEntry
import com.pastura.engine.DivergenceLedger.Side
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Synthetic-transcript coverage for [TranscriptComparator].
 *
 * These do not replace the end-to-end parity fixtures and are not replaced by
 * them. A real dual-engine run proves the *documented divergences are still
 * real*; only hand-built transcripts can reach the comparator's own edge cases —
 * ordinal keying under an upstream insertion, a regression at a ledgered site,
 * an entry that stopped firing — because a single fixture exhibits at most one
 * of them.
 *
 * Every case here is a negative control in the sense that matters: it
 * constructs the state the mechanism claims to catch and asserts it fires,
 * rather than asserting a green run stays green.
 */
class TranscriptComparatorTests {

    private val fixture = "syntheticFixture"

    private fun output(agent: String, statement: String): String =
        """{"agent":"$agent","event":"agent_output","fields":{"statement":"$statement"},"type":"event"}"""

    private fun skipped(agent: String): String =
        """{"agent":"$agent","event":"turn_skipped","type":"event"}"""

    private fun roundStarted(round: Int): String =
        """{"event":"round_started","round":$round,"type":"event"}"""

    private fun compare(
        swift: List<String>,
        kotlin: List<String>,
        ledger: List<LedgerEntry> = emptyList(),
    ) = TranscriptComparator.compare(fixture, swift, kotlin, ledger)

    private fun valueEntry(
        event: String = "agent_output",
        ordinal: Int = 0,
        path: String = "fields.statement",
        swift: String,
        kotlin: String,
        fixtureName: String = fixture,
    ) = LedgerEntry.Value(
        fixture = fixtureName,
        event = event,
        ordinal = ordinal,
        path = path,
        expectedSwift = swift,
        expectedKotlin = kotlin,
        divergenceClass = DivergenceClass.NUMBER_LITERAL_FORMATTING,
    )

    // MARK: - The clean case

    @Test
    fun identicalTranscriptsWithAnEmptyLedgerAreClean() {
        val lines = listOf(roundStarted(1), output("Alice", "hello"))
        val report = compare(lines, lines)
        assertTrue(report.isClean, report.describe())
    }

    // MARK: - Value divergences

    @Test
    fun anUnledgeredValueDifferenceIsReported() {
        val report = compare(
            listOf(output("Alice", "1")),
            listOf(output("Alice", "1.0")),
        )
        assertEquals(1, report.uncovered.size, report.describe())
        assertTrue(report.uncovered.single().description.contains("fields.statement"))
    }

    @Test
    fun aLedgeredValueDifferenceIsAccepted() {
        val report = compare(
            listOf(output("Alice", "1")),
            listOf(output("Alice", "1.0")),
            listOf(valueEntry(swift = "1", kotlin = "1.0")),
        )
        assertTrue(report.isClean, report.describe())
    }

    @Test
    fun aRegressionAtALedgeredSiteIsNotAbsorbed() {
        // The whole reason entries pin values instead of naming fields to
        // ignore. An ignore-list would swallow this silently.
        val report = compare(
            listOf(output("Alice", "1")),
            listOf(output("Alice", "9.9")),
            listOf(valueEntry(swift = "1", kotlin = "1.0")),
        )
        assertEquals(1, report.uncovered.size, report.describe())
        assertTrue(report.uncovered.single().description.contains("the values moved"))
        assertEquals(1, report.unfired.size, "the entry never matched, so it must read as unfired")
    }

    @Test
    fun anEntryThatStoppedFiringIsReported() {
        // Assertion (b): a divergence that closed must not leave a standing
        // licence behind.
        val lines = listOf(output("Alice", "same"))
        val report = compare(lines, lines, listOf(valueEntry(swift = "1", kotlin = "1.0")))
        assertTrue(report.uncovered.isEmpty(), report.describe())
        assertEquals(1, report.unfired.size, report.describe())
    }

    // MARK: - Ordinal keying

    @Test
    fun aLaterOccurrenceCanBeLedgeredOnItsOwn() {
        val swift = listOf(output("Alice", "a"), output("Bob", "1"))
        val kotlin = listOf(output("Alice", "a"), output("Bob", "1.0"))
        val report = compare(swift, kotlin, listOf(valueEntry(ordinal = 1, swift = "1", kotlin = "1.0")))
        assertTrue(report.isClean, report.describe())
    }

    @Test
    fun ordinalsCountPerKindNotPerTranscriptPosition() {
        // The cascade an absolute-index key would cause. Note the interleaved
        // `round_started` is present on BOTH sides — this proves per-kind rather
        // than per-position numbering, not one-sided insertion resilience. The
        // genuinely one-sided case is `aResyncedPairCanItselfBeLedgered`.
        val swift = listOf(output("Alice", "a"), roundStarted(2), output("Bob", "1"))
        val kotlin = listOf(output("Alice", "a"), roundStarted(2), output("Bob", "1.0"))
        val report = compare(swift, kotlin, listOf(valueEntry(ordinal = 1, swift = "1", kotlin = "1.0")))
        assertTrue(report.isClean, report.describe())
    }

    // MARK: - Structural divergences

    private fun structural(
        side: Side,
        event: String,
        ordinal: Int,
        line: String,
    ) = LedgerEntry.Structural(
        fixture = fixture,
        side = side,
        event = event,
        ordinal = ordinal,
        expectedLine = line,
        divergenceClass = DivergenceClass.SCHEMA_GUARD_POSITION,
    )

    @Test
    fun aLedgeredStructuralSubstitutionIsAcceptedAndResyncs() {
        // The shape the schema-guard divergence produces: Swift emits an
        // agent_output where Kotlin emits a turn_skipped. Two entries, one per
        // side. Bob's field DIFFERS across the sides on purpose — with identical
        // Bob events, a comparator that skipped the event entirely instead of
        // re-syncing would also report clean, so the test would pass for the
        // wrong reason.
        val swift = listOf(output("Alice", ""), output("Bob", "1"))
        val kotlin = listOf(skipped("Alice"), output("Bob", "1.0"))
        val report = compare(
            swift, kotlin,
            listOf(
                structural(Side.SWIFT_ONLY, "agent_output", 0, output("Alice", "")),
                structural(Side.KOTLIN_ONLY, "turn_skipped", 0, skipped("Alice")),
            ),
        )
        // The walk re-synced, so Bob's difference is seen and reported.
        assertEquals(1, report.uncovered.size, report.describe())
        assertTrue(report.uncovered.single().description.contains("fields.statement"))
        assertTrue(report.unfired.isEmpty(), report.describe())
    }

    @Test
    fun aResyncedPairCanItselfBeLedgered() {
        val report = compare(
            listOf(output("Alice", ""), output("Bob", "1")),
            listOf(skipped("Alice"), output("Bob", "1.0")),
            listOf(
                structural(Side.SWIFT_ONLY, "agent_output", 0, output("Alice", "")),
                structural(Side.KOTLIN_ONLY, "turn_skipped", 0, skipped("Alice")),
                // Ordinal 1: the Swift-side agent_output counter advanced past
                // the structurally-consumed one, so Bob is occurrence 1.
                valueEntry(ordinal = 1, swift = "1", kotlin = "1.0"),
            ),
        )
        assertTrue(report.isClean, report.describe())
    }

    @Test
    fun anUnledgeredStructuralDifferenceIsReported() {
        val report = compare(
            listOf(output("Alice", ""), output("Bob", "ok")),
            listOf(skipped("Alice"), output("Bob", "ok")),
        )
        assertTrue(report.uncovered.isNotEmpty(), report.describe())
        assertTrue(report.uncovered.first().description.contains("event kind diverged"))
        assertTrue(report.desynced, "an uncovered kind mismatch must mark the report desynced")
        assertTrue(report.describe().contains("may be a consequence"))
    }

    @Test
    fun aStructuralEntryDoesNotAbsorbADifferentEvent() {
        // Pinning the whole line is what makes this fail: a kind-plus-position
        // entry would accept any turn_skipped here.
        val report = compare(
            listOf(output("Alice", "")),
            listOf(skipped("Carol")),
            listOf(structural(Side.KOTLIN_ONLY, "turn_skipped", 0, skipped("Alice"))),
        )
        assertTrue(report.uncovered.isNotEmpty(), report.describe())
        assertEquals(1, report.unfired.size, report.describe())
    }

    // The widening path a line-only match leaves open. Pinning `t` and `attempt`
    // to 0 makes a real transcript full of byte-identical lines — one agent's
    // `inference_started` recurs 18 times verbatim in the committed golden — so
    // an entry written for one occurrence must not license a different one.
    //
    // Both arms share the fixture: occurrence 0 of `turn_skipped` is a MATCHED
    // pair, so the only kind mismatch is at occurrence 1. That is what makes the
    // ordinal observable — an earlier draft put the mismatch at occurrence 0 and
    // passed with the ordinal check deleted, because a wrongly-consumed entry
    // still left a second mismatch behind that satisfied the assertion.
    private val repeatedSwift = listOf(skipped("Alice"), output("Alice", "a"))
    private val repeatedKotlin = listOf(skipped("Alice"), skipped("Alice"))

    @Test
    fun aStructuralEntryPinnedToTheWrongOccurrenceDoesNotFire() {
        val report = compare(
            repeatedSwift, repeatedKotlin,
            // Pinned to occurrence 0 — which is a matched pair, not the mismatch.
            listOf(structural(Side.KOTLIN_ONLY, "turn_skipped", 0, skipped("Alice"))),
        )
        assertTrue(
            report.uncovered.any { it.description.contains("event kind diverged") },
            report.describe(),
        )
        assertEquals(1, report.unfired.size, "the mis-keyed entry must read as unfired")
    }

    @Test
    fun aStructuralEntryPinnedToTheRightOccurrenceFires() {
        // The positive control for the arm above: same transcripts, ordinal 1.
        // Swift's trailing agent_output is then unmatched, so one uncovered
        // trailing diff remains — the point is that the kind mismatch is gone.
        val report = compare(
            repeatedSwift, repeatedKotlin,
            listOf(structural(Side.KOTLIN_ONLY, "turn_skipped", 1, skipped("Alice"))),
        )
        assertTrue(report.unfired.isEmpty(), report.describe())
        assertTrue(
            report.uncovered.none { it.description.contains("event kind diverged") },
            report.describe(),
        )
    }

    @Test
    fun duplicateEntriesDoNotMarkEachOtherFired() {
        // Fired-ness is tracked by index. Tracked by value, one firing would
        // mark both and the stale duplicate would read as used — a hole in
        // assertion (b) exactly where a copy-paste ledger edit lands.
        val entry = valueEntry(swift = "1", kotlin = "1.0")
        val report = compare(
            listOf(output("Alice", "1")),
            listOf(output("Alice", "1.0")),
            listOf(entry, entry),
        )
        assertEquals(1, report.unfired.size, report.describe())
    }

    @Test
    fun anEmptyNestedObjectIsDistinguishedFromAnAbsentKey() {
        // `fields: {}` versus no `fields` key at all. Erased by a naive flatten,
        // and the wrong blind spot for a comparator whose reason to exist
        // includes an empty-field divergence.
        val report = compare(
            listOf("""{"event":"agent_output","fields":{},"type":"event"}"""),
            listOf("""{"event":"agent_output","type":"event"}"""),
        )
        assertEquals(1, report.uncovered.size, report.describe())
        assertTrue(report.uncovered.single().description.contains("fields"))
    }

    @Test
    fun aTrailingSwiftEventIsReported() {
        val report = compare(
            listOf(output("Alice", "a"), output("Bob", "b")),
            listOf(output("Alice", "a")),
        )
        assertEquals(1, report.uncovered.size, report.describe())
        assertTrue(report.uncovered.single().description.contains("trailing SWIFT_ONLY"))
    }

    @Test
    fun aTrailingKotlinEventIsReported() {
        val report = compare(
            listOf(output("Alice", "a")),
            listOf(output("Alice", "a"), output("Bob", "b")),
        )
        assertEquals(1, report.uncovered.size, report.describe())
        assertTrue(report.uncovered.single().description.contains("trailing KOTLIN_ONLY"))
    }

    @Test
    fun aLedgeredTrailingEventIsAccepted() {
        val report = compare(
            listOf(output("Alice", "a"), output("Bob", "b")),
            listOf(output("Alice", "a")),
            listOf(structural(Side.SWIFT_ONLY, "agent_output", 1, output("Bob", "b"))),
        )
        assertTrue(report.isClean, report.describe())
    }

    @Test
    fun aMalformedLineDegradesToAReportRatherThanAThrow() {
        val report = compare(listOf("not json"), listOf(output("Alice", "a")))
        assertTrue(report.uncovered.isNotEmpty(), report.describe())
        assertTrue(report.uncovered.any { it.description.contains("not a JSON object") })
    }

    @Test
    fun transcriptComparatorReportsAMalformedLineOnce() {
        // The state the de-duplication in `kindOf` defends, which nothing else
        // builds: the Kotlin side is what a structural entry consumes, so the
        // Swift line survives the iteration and is re-read at the same index.
        // Without the guard it reports twice and inflates `uncovered.size`.
        val report = compare(
            listOf("not json", output("Bob", "b")),
            listOf(skipped("Alice"), output("Bob", "b")),
            listOf(structural(Side.KOTLIN_ONLY, "turn_skipped", 0, skipped("Alice"))),
        )
        assertEquals(
            1,
            report.uncovered.count { it.description.contains("not a JSON object") },
            report.describe(),
        )
    }

    @Test
    fun twoMalformedLinesOnOppositeSidesStayTwoReports() {
        // The other half of "exact, not lossy": carrying side + index means two
        // genuinely distinct bad lines with identical TEXT do not collapse into
        // one report the way a text-only key would have made them.
        val report = compare(listOf("not json"), listOf("not json"))
        assertEquals(
            2,
            report.uncovered.count { it.description.contains("not a JSON object") },
            report.describe(),
        )
    }

    // MARK: - Scoping

    @Test
    fun entriesForAnotherFixtureAreNeitherAppliedNorReported() {
        val report = compare(
            listOf(output("Alice", "1")),
            listOf(output("Alice", "1.0")),
            listOf(valueEntry(swift = "1", kotlin = "1.0", fixtureName = "someOtherFixture")),
        )
        assertEquals(1, report.uncovered.size, "the foreign entry must not cover this diff")
        assertTrue(report.unfired.isEmpty(), "a foreign entry is out of scope, not unfired")
    }
}
