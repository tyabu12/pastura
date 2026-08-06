package com.pastura.engine

/**
 * The ADR-023 Stage-4 divergence ledger and the transcript comparator that
 * consumes it.
 *
 * ## Why this is data a test reads, not a prose table
 *
 * "Known divergences" maintained in prose drift silently until they absorb a
 * real regression. Every claim here is executable: the comparator fails if a
 * diff is not covered by an entry, **and** fails if an entry does not fire. The
 * second half is what stops the ledger widening — a stale entry is a build
 * failure rather than a permanent licence.
 *
 * ## Why entries pin values instead of listing fields to ignore
 *
 * An ignore-list absorbs whatever appears at the ignored site, including a new
 * regression. A [LedgerEntry.Value] pins both sides' expected text, so a
 * regression at a ledgered site fails to match and surfaces as an uncovered
 * diff — loud, in the same way an unledgered site is.
 *
 * ## What still bounds widening, and what does not
 *
 * Assertion (b) polices *existing* entries; nothing mechanical stops someone
 * adding a new entry that matches new wrong behaviour. Two schema constraints
 * narrow that: provenance is a [DivergenceClass] drawn from a closed set, so a
 * genuinely new divergence needs a new enum case — a reviewable diff, not a
 * free-text pointer — and [LedgerEntry.Structural] pins the whole expected
 * event line, so an unrelated extra event near a ledgered position is not
 * absorbed. The rest is policy, recorded on #1387: on the ported surface a new
 * Swift-only divergence is dual-landed, not ledgered.
 */
internal object DivergenceLedger {

    /**
     * The closed set of documented cross-language divergences.
     *
     * Adding a case is the deliberate act that widening requires. Each carries
     * the source that documents it, so an entry cannot cite something that was
     * never written down.
     */
    internal enum class DivergenceClass(val documentedAt: String) {
        /**
         * Swift's early return still emits `phaseCompleted(.conditional)`;
         * Kotlin unwinds the run instead.
         */
        CANCELLATION_EVENT_TAIL("ConditionalHandler.kt class KDoc, § Divergences"),

        /**
         * For a present-but-empty canonical field on a schema-declaring phase,
         * Swift's last retry attempt returns the empty output as an
         * `agentOutput`; Kotlin's parser guard exhausts retries and the turn
         * gate emits `turnSkipped`.
         */
        SCHEMA_GUARD_POSITION(".claude/rules/kmp-interop.md Pattern 4"),

        /**
         * The ADR-010 language-adherence retry is dormant on the Kotlin side:
         * `SimulationEngine` wires no detector, so `languageMismatch` events
         * reach the Swift transcript alone.
         */
        DETECTOR_UNWIRED("SimulationEngine.kt class KDoc; ADR-023 §4"),

        /**
         * Kotlin has no `ScenarioValidator` / `ScenarioSemanticLinter` port, so
         * the preflight gate behaves differently for scenarios Swift rejects.
         */
        VALIDATOR_UNPORTED("LanguageDispatch.kt KDoc; ADR-023 §4"),

        /**
         * `formatScoreboard` orders by Unicode scalar and collapses
         * canonically-equivalent `[String: Int]` keys in Swift; Kotlin orders by
         * UTF-16 code unit and keeps them.
         */
        SCOREBOARD_ORDERING("PromptBuilder.kt formatScoreboard KDoc"),

        /**
         * Swift's `NSNumber.stringValue` drops a trailing `.0` and expands
         * exponents (`1.0` -> `"1"`, `1e3` -> `"1000"`); Kotlin preserves the
         * literal. ADR-023 Stage 4 is asked to rule on which side changes.
         */
        NUMBER_LITERAL_FORMATTING("JSONResponseParser.kt normalizeValues KDoc"),
    }

    /** Which engine emits an event the other does not. */
    internal enum class Side { SWIFT_ONLY, KOTLIN_ONLY }

    /** One accepted divergence. */
    internal sealed class LedgerEntry {
        /** Fixture this entry applies to — entries never leak across fixtures. */
        abstract val fixture: String

        /** What documents it. */
        abstract val divergenceClass: DivergenceClass

        /**
         * A field that differs on an event both engines emit.
         *
         * Keyed by the event kind plus its 0-based occurrence ordinal **within
         * the Swift transcript**, never by an absolute transcript index: an
         * absolute index shifts under any upstream structural divergence, which
         * would force one entry per remaining event. The ordinal counts every
         * event of that kind the walk consumes on that side, including ones a
         * [Structural] entry accounts for — so it stays a property of the
         * transcript rather than of how far the two happened to stay paired.
         */
        internal data class Value(
            override val fixture: String,
            val event: String,
            val ordinal: Int,
            val path: String,
            val expectedSwift: String,
            val expectedKotlin: String,
            override val divergenceClass: DivergenceClass,
        ) : LedgerEntry()

        /**
         * An event one engine emits and the other does not.
         *
         * Pinned three ways, and all three are load-bearing:
         *
         * - [expectedLine] is the whole JSON line, so a *different* unexpected
         *   event arriving at the same place is not absorbed.
         * - [event] plus [ordinal] fix *which occurrence* this licenses. Without
         *   them a line-only match is position-free, and a transcript is full of
         *   byte-identical lines — pinning `t` and `attempt` to 0 makes e.g. one
         *   agent's `inference_started` recur 18 times verbatim in the committed
         *   golden. An entry written for round 4 would then fire at round 1's
         *   occurrence and the walk would re-sync as if nothing happened,
         *   silently absorbing an ordering regression.
         *
         * [ordinal] counts occurrences of [event] on [side]'s own transcript.
         */
        internal data class Structural(
            override val fixture: String,
            val side: Side,
            val event: String,
            val ordinal: Int,
            val expectedLine: String,
            override val divergenceClass: DivergenceClass,
        ) : LedgerEntry()
    }

    /** A difference no entry covers. */
    internal data class UncoveredDiff(val description: String)

    /** What one comparison found. */
    internal data class Report(
        val uncovered: List<UncoveredDiff>,
        val unfired: List<LedgerEntry>,
        /**
         * Whether an uncovered structural difference forced the walk to advance
         * both sides. Everything reported after that point may be a consequence
         * rather than a cause.
         */
        val desynced: Boolean = false,
    ) {
        val isClean: Boolean get() = uncovered.isEmpty() && unfired.isEmpty()

        /** Human-readable failure text; empty when clean. */
        fun describe(): String = buildString {
            // Emitted first, and in the failure text rather than only in a KDoc:
            // the engineer reading a red build sees this string, not the source.
            if (desynced) {
                appendLine(
                    "NOTE: the walk desynchronized at the first uncovered structural difference. " +
                        "Everything after it may be a consequence — fix the first one and re-run."
                )
            }
            if (uncovered.isNotEmpty()) {
                appendLine("Uncovered differences (${uncovered.size}):")
                uncovered.forEach { appendLine("  - ${it.description}") }
            }
            if (unfired.isNotEmpty()) {
                appendLine("Ledger entries that did not fire (${unfired.size}):")
                unfired.forEach { appendLine("  - $it  [documented at: ${it.divergenceClass.documentedAt}]") }
                appendLine(
                    "  An entry that stops firing is a divergence that closed — " +
                        "delete it rather than leaving a standing licence."
                )
            }
        }
    }
}
