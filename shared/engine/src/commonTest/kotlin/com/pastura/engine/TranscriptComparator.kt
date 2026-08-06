package com.pastura.engine

import com.pastura.engine.DivergenceLedger.LedgerEntry
import com.pastura.engine.DivergenceLedger.Report
import com.pastura.engine.DivergenceLedger.Side
import com.pastura.engine.DivergenceLedger.UncoveredDiff
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Walks two event transcripts in lockstep and reports what the ledger does not
 * account for — in both directions (see [DivergenceLedger]).
 *
 * ## Why a two-pointer walk rather than a sequence alignment
 *
 * An LCS-style alignment optimizes for the *smallest* edit script, which is
 * exactly what a guard must not do: it re-aligns around a swap, so a transposed
 * pair reads as two small edits rather than as the ordering regression it is,
 * and the failure report stops naming where the engines actually parted. A
 * deterministic walk that fails loudly on anything unledgered is the weaker
 * algorithm and the stronger guard. After a [LedgerEntry.Structural] entry is
 * consumed the pointers re-sync on their own.
 *
 * ## Ordinals are per side, and count every consumed line
 *
 * Each side keeps its own `kind -> next ordinal` counter, advanced whenever a
 * line of that kind is consumed — paired, structurally accounted for, or
 * skipped past after a desync. So an ordinal is a property of the transcript,
 * not of how far the two happened to stay paired, and an upstream structural
 * divergence does not renumber later entries.
 *
 * ## Reading a failure
 *
 * The first uncovered structural difference desynchronizes the walk — it has no
 * way to know which side gained or lost an event — so everything reported after
 * it may be a consequence rather than a cause. [Report.describe] says so at the
 * head of the failure text; fix the first one and re-run.
 */
internal object TranscriptComparator {

    private val json = Json { ignoreUnknownKeys = true }

    /** Sentinel for "this path exists on one side only". */
    private const val ABSENT = "<absent>"

    /**
     * Sentinel so an empty nested object survives flattening.
     *
     * Without it `"fields":{}` contributes no path at all and compares equal to
     * an event with no `fields` key — the wrong blind spot for a comparator
     * whose whole reason to exist includes an empty-field divergence.
     */
    private const val EMPTY_OBJECT = "<empty object>"

    /**
     * @param fixture the fixture name; entries for other fixtures are out of
     *   scope — neither applied nor reported unfired.
     */
    internal fun compare(
        fixture: String,
        swift: List<String>,
        kotlin: List<String>,
        ledger: List<LedgerEntry>,
    ): Report {
        val scoped = ledger.filter { it.fixture == fixture }
        // Fired-ness is tracked by INDEX, not by value: two identical entries
        // are two licences, and a set keyed on data-class equality would let one
        // firing mark both, quietly defeating the unfired check exactly where a
        // copy-paste ledger edit lands.
        val fired = BooleanArray(scoped.size)
        val uncovered = mutableListOf<UncoveredDiff>()
        val swiftOrdinals = mutableMapOf<String, Int>()
        val kotlinOrdinals = mutableMapOf<String, Int>()

        var i = 0
        var j = 0
        var desynced = false

        while (i < swift.size || j < kotlin.size) {
            val swiftLine = swift.getOrNull(i)
            val kotlinLine = kotlin.getOrNull(j)

            // One side exhausted: everything left is structural by definition.
            if (swiftLine == null || kotlinLine == null) {
                val side = if (kotlinLine == null) Side.SWIFT_ONLY else Side.KOTLIN_ONLY
                val line = swiftLine ?: kotlinLine ?: break
                val ordinals = if (side == Side.SWIFT_ONLY) swiftOrdinals else kotlinOrdinals
                val eventKind = kindOf(line, uncovered)
                if (!consumeStructural(scoped, fired, side, eventKind, ordinals, line)) {
                    uncovered += UncoveredDiff("trailing ${side.name} event with no ledger entry: $line")
                    take(ordinals, eventKind)
                }
                if (side == Side.SWIFT_ONLY) i++ else j++
                continue
            }

            val swiftKind = kindOf(swiftLine, uncovered)
            val kotlinKind = kindOf(kotlinLine, uncovered)

            if (swiftKind == kotlinKind) {
                val ordinal = take(swiftOrdinals, swiftKind)
                take(kotlinOrdinals, kotlinKind)
                uncovered += diffFields(swiftKind, ordinal, swiftLine, kotlinLine, scoped, fired)
                i++
                j++
                continue
            }

            // Kinds differ: one side emitted an event the other did not. Try the
            // Swift side first, then the Kotlin side; either match re-syncs.
            if (consumeStructural(scoped, fired, Side.SWIFT_ONLY, swiftKind, swiftOrdinals, swiftLine)) {
                i++
            } else if (
                consumeStructural(scoped, fired, Side.KOTLIN_ONLY, kotlinKind, kotlinOrdinals, kotlinLine)
            ) {
                j++
            } else {
                uncovered += UncoveredDiff(
                    "event kind diverged with no ledger entry — swift=$swiftKind kotlin=$kotlinKind" +
                        "\n      swift: $swiftLine\n      kotlin: $kotlinLine"
                )
                desynced = true
                take(swiftOrdinals, swiftKind)
                take(kotlinOrdinals, kotlinKind)
                i++
                j++
            }
        }

        val unfired = scoped.filterIndexed { index, _ -> !fired[index] }
        return Report(uncovered = uncovered, unfired = unfired, desynced = desynced)
    }

    /** Returns the next ordinal for [kind] on one side and advances the counter. */
    private fun take(ordinals: MutableMap<String, Int>, kind: String): Int {
        val next = ordinals.getOrElse(kind) { 0 }
        ordinals[kind] = next + 1
        return next
    }

    /**
     * Marks a matching structural entry fired and advances that side's ordinal;
     * returns false (leaving the ordinal untouched) when none matches.
     */
    private fun consumeStructural(
        scoped: List<LedgerEntry>,
        fired: BooleanArray,
        side: Side,
        eventKind: String,
        ordinals: MutableMap<String, Int>,
        line: String,
    ): Boolean {
        val ordinal = ordinals.getOrElse(eventKind) { 0 }
        // Indexed loop, not `indexOfFirst` with an `indexOf` inside it: with two
        // identical entries `indexOf` returns the first one's position for both,
        // so the second could never be reached and the first could be consumed
        // twice.
        for (index in scoped.indices) {
            if (fired[index]) continue
            val entry = scoped[index] as? LedgerEntry.Structural ?: continue
            if (entry.side != side || entry.event != eventKind) continue
            if (entry.ordinal != ordinal || entry.expectedLine != line) continue
            fired[index] = true
            take(ordinals, eventKind)
            return true
        }
        return false
    }

    /** Compares two same-kind events field by field. */
    private fun diffFields(
        event: String,
        ordinal: Int,
        swiftLine: String,
        kotlinLine: String,
        scoped: List<LedgerEntry>,
        fired: BooleanArray,
    ): List<UncoveredDiff> {
        val swift = parse(swiftLine) ?: return listOf(malformed(swiftLine))
        val kotlin = parse(kotlinLine) ?: return listOf(malformed(kotlinLine))
        val swiftFlat = flatten(swift)
        val kotlinFlat = flatten(kotlin)
        val diffs = mutableListOf<UncoveredDiff>()

        for (path in (swiftFlat.keys + kotlinFlat.keys).sorted()) {
            val swiftValue = swiftFlat[path] ?: ABSENT
            val kotlinValue = kotlinFlat[path] ?: ABSENT
            if (swiftValue == kotlinValue) continue

            val index = scoped.indexOfFirst {
                it is LedgerEntry.Value && it.event == event && it.ordinal == ordinal && it.path == path
            }
            val entry = scoped.getOrNull(index) as? LedgerEntry.Value
            if (entry == null) {
                diffs += UncoveredDiff("$event[$ordinal].$path — swift=$swiftValue kotlin=$kotlinValue")
                continue
            }
            // The entry exists but pins different text: a regression AT a
            // ledgered site, which is exactly what an ignore-list would swallow.
            if (entry.expectedSwift != swiftValue || entry.expectedKotlin != kotlinValue) {
                diffs += UncoveredDiff(
                    "$event[$ordinal].$path — ledgered, but the values moved: " +
                        "expected swift=${entry.expectedSwift} kotlin=${entry.expectedKotlin}, " +
                        "got swift=$swiftValue kotlin=$kotlinValue"
                )
                continue
            }
            fired[index] = true
        }
        return diffs
    }

    private fun malformed(line: String) =
        UncoveredDiff("transcript line is not a JSON object: $line")

    /**
     * Reads an event's kind, degrading rather than throwing: one malformed line
     * should produce a report a reader can act on, not a stack trace in place of
     * every other finding.
     */
    private fun kindOf(line: String, uncovered: MutableList<UncoveredDiff>): String {
        val event = parse(line)
        if (event == null) {
            uncovered += malformed(line)
            return "<unparseable>"
        }
        return (event["event"] as? JsonPrimitive)?.content ?: "<no event key>"
    }

    private fun parse(line: String): JsonObject? =
        runCatching { json.parseToJsonElement(line) as? JsonObject }.getOrNull()

    /**
     * Flattens nested objects to dotted paths so a single differing leaf reports
     * as one path rather than as the whole parent object. Arrays compare whole:
     * their order is meaningful, and a per-index path would make an insertion
     * report as N differences.
     */
    private fun flatten(element: JsonElement, prefix: String = ""): Map<String, String> =
        when (element) {
            is JsonObject -> element.entries.flatMap { (key, value) ->
                val path = if (prefix.isEmpty()) key else "$prefix.$key"
                when {
                    value is JsonObject && value.isEmpty() -> listOf(path to EMPTY_OBJECT)
                    value is JsonObject -> flatten(value, path).entries.map { it.key to it.value }
                    else -> listOf(path to render(value))
                }
            }.toMap()
            else -> mapOf(prefix to render(element))
        }

    private fun render(element: JsonElement): String = when (element) {
        is JsonPrimitive -> element.content
        is JsonArray -> element.toString()
        is JsonObject -> element.toString()
    }
}
