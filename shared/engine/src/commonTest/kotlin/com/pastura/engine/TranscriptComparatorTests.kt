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
    fun entriesAreKeyedByOccurrenceOrdinalNotTranscriptIndex() {
        val swift = listOf(output("Alice", "a"), output("Bob", "1"))
        val kotlin = listOf(output("Alice", "a"), output("Bob", "1.0"))
        val report = compare(swift, kotlin, listOf(valueEntry(ordinal = 1, swift = "1", kotlin = "1.0")))
        assertTrue(report.isClean, report.describe())
    }

    @Test
    fun anUpstreamInsertionDoesNotShiftLaterOrdinals() {
        // The cascade an absolute-index key would cause: an extra event early
        // would renumber every later entry. Ordinals count per kind, and the
        // inserted event is a different kind, so the ledgered agent_output keeps
        // ordinal 1.
        val swift = listOf(output("Alice", "a"), roundStarted(2), output("Bob", "1"))
        val kotlin = listOf(output("Alice", "a"), roundStarted(2), output("Bob", "1.0"))
        val report = compare(swift, kotlin, listOf(valueEntry(ordinal = 1, swift = "1", kotlin = "1.0")))
        assertTrue(report.isClean, report.describe())
    }

    // MARK: - Structural divergences

    @Test
    fun aLedgeredStructuralSubstitutionIsAcceptedAndResyncs() {
        // The shape the schema-guard divergence produces: Swift emits an
        // agent_output where Kotlin emits a turn_skipped. Two entries, one per
        // side; the walk must re-sync and compare the following event normally.
        val swift = listOf(output("Alice", ""), output("Bob", "ok"))
        val kotlin = listOf(skipped("Alice"), output("Bob", "ok"))
        val report = compare(
            swift, kotlin,
            listOf(
                LedgerEntry.Structural(
                    fixture, Side.SWIFT_ONLY, output("Alice", ""),
                    DivergenceClass.SCHEMA_GUARD_POSITION),
                LedgerEntry.Structural(
                    fixture, Side.KOTLIN_ONLY, skipped("Alice"),
                    DivergenceClass.SCHEMA_GUARD_POSITION),
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
    }

    @Test
    fun aStructuralEntryDoesNotAbsorbADifferentEvent() {
        // Pinning the whole line is what makes this fail: a kind-plus-position
        // entry would accept any turn_skipped here.
        val report = compare(
            listOf(output("Alice", "")),
            listOf(skipped("Carol")),
            listOf(
                LedgerEntry.Structural(
                    fixture, Side.KOTLIN_ONLY, skipped("Alice"),
                    DivergenceClass.SCHEMA_GUARD_POSITION),
            ),
        )
        assertTrue(report.uncovered.isNotEmpty(), report.describe())
        assertEquals(1, report.unfired.size, report.describe())
    }

    @Test
    fun aTrailingEventOnOneSideIsReported() {
        val report = compare(
            listOf(output("Alice", "a"), output("Bob", "b")),
            listOf(output("Alice", "a")),
        )
        assertEquals(1, report.uncovered.size, report.describe())
        assertTrue(report.uncovered.single().description.contains("trailing SWIFT_ONLY"))
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
