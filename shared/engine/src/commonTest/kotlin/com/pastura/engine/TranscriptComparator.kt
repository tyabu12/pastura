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
 * ## Reading a failure
 *
 * The first uncovered structural difference desynchronizes the walk — it has no
 * way to know which side gained or lost an event — so everything reported after
 * it may be a consequence rather than a cause. Fix the first one and re-run.
 */
internal object TranscriptComparator {

    private val json = Json { ignoreUnknownKeys = true }

    /**
     * @param fixture the fixture name; entries for other fixtures are ignored
     *   rather than silently applied.
     */
    internal fun compare(
        fixture: String,
        swift: List<String>,
        kotlin: List<String>,
        ledger: List<LedgerEntry>,
    ): Report {
        val scoped = ledger.filter { it.fixture == fixture }
        val fired = mutableSetOf<LedgerEntry>()
        val uncovered = mutableListOf<UncoveredDiff>()
        val ordinals = mutableMapOf<String, Int>()

        var i = 0
        var j = 0
        var desynced = false

        while (i < swift.size || j < kotlin.size) {
            val swiftLine = swift.getOrNull(i)
            val kotlinLine = kotlin.getOrNull(j)

            if (swiftLine == null || kotlinLine == null) {
                val side = if (kotlinLine == null) Side.SWIFT_ONLY else Side.KOTLIN_ONLY
                val line = swiftLine ?: kotlinLine ?: break
                if (consumeStructural(scoped, fired, side, line)) {
                    if (side == Side.SWIFT_ONLY) i++ else j++
                } else {
                    uncovered += UncoveredDiff("trailing ${side.name} event with no ledger entry: $line")
                    if (side == Side.SWIFT_ONLY) i++ else j++
                }
                continue
            }

            val swiftEvent = parse(swiftLine)
            val kotlinEvent = parse(kotlinLine)
            val swiftKind = kind(swiftEvent)
            val kotlinKind = kind(kotlinEvent)

            if (swiftKind == kotlinKind) {
                val ordinal = ordinals.getOrElse(swiftKind) { 0 }
                ordinals[swiftKind] = ordinal + 1
                uncovered += diffFields(
                    fixture, swiftKind, ordinal, swiftEvent, kotlinEvent, scoped, fired)
                i++
                j++
                continue
            }

            // Kinds differ: one side emitted an event the other did not. Try the
            // Swift side first, then the Kotlin side; either match re-syncs.
            if (consumeStructural(scoped, fired, Side.SWIFT_ONLY, swiftLine)) {
                i++
            } else if (consumeStructural(scoped, fired, Side.KOTLIN_ONLY, kotlinLine)) {
                j++
            } else {
                uncovered += UncoveredDiff(
                    "event kind diverged with no ledger entry — swift=$swiftKind kotlin=$kotlinKind" +
                        (if (desynced) " (after an earlier desync; may be a consequence)" else "") +
                        "\n      swift: $swiftLine\n      kotlin: $kotlinLine"
                )
                desynced = true
                i++
                j++
            }
        }

        return Report(uncovered = uncovered, unfired = scoped.filterNot { it in fired })
    }

    /** Marks a matching structural entry fired; false when none matches. */
    private fun consumeStructural(
        scoped: List<LedgerEntry>,
        fired: MutableSet<LedgerEntry>,
        side: Side,
        line: String,
    ): Boolean {
        val match = scoped.filterIsInstance<LedgerEntry.Structural>()
            .firstOrNull { it.side == side && it.expectedLine == line && it !in fired }
            ?: return false
        fired += match
        return true
    }

    /** Compares two same-kind events field by field. */
    private fun diffFields(
        fixture: String,
        event: String,
        ordinal: Int,
        swift: JsonObject,
        kotlin: JsonObject,
        scoped: List<LedgerEntry>,
        fired: MutableSet<LedgerEntry>,
    ): List<UncoveredDiff> {
        val swiftFlat = flatten(swift)
        val kotlinFlat = flatten(kotlin)
        val paths = (swiftFlat.keys + kotlinFlat.keys).sorted()
        val diffs = mutableListOf<UncoveredDiff>()

        for (path in paths) {
            val swiftValue = swiftFlat[path] ?: ABSENT
            val kotlinValue = kotlinFlat[path] ?: ABSENT
            if (swiftValue == kotlinValue) continue

            val entry = scoped.filterIsInstance<LedgerEntry.Value>().firstOrNull {
                it.event == event && it.ordinal == ordinal && it.path == path
            }
            if (entry == null) {
                diffs += UncoveredDiff(
                    "$event[$ordinal].$path — swift=$swiftValue kotlin=$kotlinValue")
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
            fired += entry
        }
        return diffs
    }

    /** Sentinel for "this path exists on one side only". */
    private const val ABSENT = "<absent>"

    private fun parse(line: String): JsonObject =
        json.parseToJsonElement(line) as? JsonObject
            ?: error("transcript line is not a JSON object: $line")

    private fun kind(event: JsonObject): String =
        (event["event"] as? JsonPrimitive)?.content ?: "<no event key>"

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
                when (value) {
                    is JsonObject -> flatten(value, path).entries.map { it.key to it.value }
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
