package com.pastura.engine

/**
 * The ADR-023 Stage-4 divergence ledger and the transcript comparator that
 * consumes it.
 *
 * ## Why this is data a test reads, not a prose table
 *
 * "Known divergences" maintained in prose drift silently until they absorb a
 * real regression. The mechanism here is executable instead: the comparator
 * fails if a diff is not covered by an entry, **and** fails if an entry does not
 * fire. The second half is what stops the ledger widening — a stale entry is a
 * build failure rather than a permanent licence.
 *
 * **This is now wired to real transcripts.** [entries] is read by
 * `EngineParityTests`, which replays each `ParityGolden` fixture through the
 * Kotlin engine and compares. Slice 1b (#1458) joined the schema, the
 * comparator and the golden, which 1a (#1387) had left as three unconnected
 * pieces. The paragraphs below describe a gate that runs, not one that is
 * planned.
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
 * absorbed. The rest is policy, first recorded on the closed #1387 and carried
 * forward on #501: on the ported surface a new
 * Swift-only divergence is dual-landed, not ledgered.
 */
internal object DivergenceLedger {

    /**
     * The closed set of documented cross-language divergences.
     *
     * Adding a case is the deliberate act that widening requires. Each carries
     * the source that documents it, so an entry cannot cite something that was
     * never written down.
     *
     * **Two gaps this file used to name are now closed** by
     * `DivergenceLedgerTests` (#1458): a case that outlives its entries is a
     * pre-approved licence, and an entry with a typo'd `fixture` is silently
     * out of scope rather than unfired, so it vanishes with no signal when the
     * divergence it covered also closes.
     *
     * The first gap's *prescribed remedy* — "a test asserting every case is
     * cited" — turned out to be unsatisfiable, and the correction is worth
     * keeping visible: four of the six cases below are documented divergences
     * no fixture can structurally reach, so that assertion would have been red
     * the day it landed. [unreachableClasses] carries the shape that works.
     * The gap list inherited the blind spot of the list it was drawn from,
     * which is a hazard of gap lists generally, not a one-off.
     *
     * **The third gap is closed too**, by `someFixtureDrivesBothEntryKinds`.
     * Neither assertion above sees a case and its entry deleted **together** —
     * which is what resolving a divergence does. Nothing is left unfired, and
     * "every case is accounted for" quantifies over survivors, so the negative
     * control can lose an entire entry *kind* while staying green. ADR-021's
     * Amendment 2026-08-06 retired `SCHEMA_GUARD_POSITION` and cost the control
     * its only structural arm exactly this way.
     *
     * That guard was verified by reproducing the incident rather than by
     * argument: converging the engines on the fixture's divergent turn, then
     * deleting [DivergenceClass.MULTI_OBJECT_SALVAGE] together with **both** the
     * [entries] rows and the [callCountDivergences] row that cite it — leaving
     * either behind fails to compile, and leaving the map row in place would
     * redden the call-count assertion instead, falsifying the "only the
     * kind-coverage one reddens" claim. Done that way, `EngineParityTests` goes
     * fully green and both assertions above stay green.
     */
    internal enum class DivergenceClass(val documentedAt: String) {
        /**
         * Swift's early return still emits `phaseCompleted(.conditional)`;
         * Kotlin unwinds the run instead.
         */
        CANCELLATION_EVENT_TAIL("ConditionalHandler.kt class KDoc, § Divergences"),

        // `SCHEMA_GUARD_POSITION` lived here — Swift returned a present-but-empty
        // canonical field as an `agentOutput` where Kotlin's parser guard exhausted
        // retries into a `turnSkipped`. ADR-021 § Amendment 2026-08-06 resolved it
        // (both engines now skip), so the case is DELETED rather than kept with a
        // "resolved" marker: a case that outlives its entries becomes a pre-approved
        // licence a later author can attach to with no enum diff at all.

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

        /**
         * Swift's schema-guarded multi-object salvage (#907) accepts the first
         * object of `{...}{...}` when every expected key is present and
         * non-empty; Kotlin's `extractFirstJsonObject` returns object-like
         * residue unchanged, so the parse fails and the turn exhausts its
         * retries into a `turnSkipped`.
         *
         * Pinned on both sides by paired parser tests fed byte-identical
         * input: `JSONResponseParserTests+Repair.swift`'s
         * `salvagesFirstObjectFromMultiObjectResponseWhenSchemaGuardPasses`
         * and `JSONResponseParserTests.kt`'s
         * `multiObjectResponseFailsTheParseEvenWithASatisfiedSchema`.
         */
        MULTI_OBJECT_SALVAGE(
            "JSONResponseParser.swift multi_object_salvage (#907) vs " +
                "JSONResponseParser.kt extractFirstJsonObject; paired parser tests in both " +
                "languages",
        ),
    }

    /**
     * Every accepted divergence, across every fixture.
     *
     * `TranscriptComparator.compare` scopes this to one fixture per call, so an
     * entry can never leak into a fixture it was not written for — and an entry
     * whose `fixture` names nothing is silently out of scope rather than
     * unfired, which is what `everyEntryNamesAKnownFixture` exists to catch.
     *
     * **Adding an entry is not the default response to a red parity run.** The
     * regime ADR-023 §12 condition 3 chose is dual-landing: on a surface with a
     * Kotlin counterpart, a new Swift-only divergence is *fixed*, not excused.
     * An entry is correct only when the divergence is genuinely accepted and
     * already documented — which the [DivergenceClass] requirement enforces,
     * since citing one means the write-up exists.
     */
    internal val entries: List<LedgerEntry> = listOf(
        // Ordinal 0, not 3. The divergent fixture's first three answers drive
        // アオイ's turn to a skip, so the FIRST `agent_output` Swift emits is
        // ハルト's — the one carrying the float. Counted against the generated
        // bytes rather than inferred from the response indices, because those
        // two disagree exactly when a turn is skipped.
        LedgerEntry.Value(
            fixture = "targetScoreRaceDivergent",
            event = "agent_output",
            ordinal = 0,
            path = "fields.confidence",
            expectedSwift = "1",
            expectedKotlin = "1.0",
            divergenceClass = DivergenceClass.NUMBER_LITERAL_FORMATTING,
        ),

        // --- parityStructuralControl -------------------------------------
        //
        // Ada's turn (call 0) carries the same float key, so this fixture
        // drives one divergence of EACH entry kind by itself — which is what
        // `kindCoverage` holds it to.
        LedgerEntry.Value(
            fixture = "parityStructuralControl",
            event = "agent_output",
            ordinal = 0,
            path = "fields.confidence",
            expectedSwift = "1",
            expectedKotlin = "1.0",
            divergenceClass = DivergenceClass.NUMBER_LITERAL_FORMATTING,
        ),

        // Bo's turn (call 1) is the structural arm. Swift salvages in one
        // call and emits an `agentOutput`; Kotlin fails the parse and burns
        // two more attempts before skipping. Every attempt emits its own
        // `inference_started` / `inference_completed` pair, so the surplus
        // shows up as four Kotlin-only lines BEFORE the `turnSkipped` — the
        // part an estimate based on "one event each way" misses.
        //
        // ⚠️ The two `inference_started` lines are BYTE-IDENTICAL, as are the
        // two `inference_completed` ones: `t` and `attempt` are pinned to 0,
        // so nothing in the text distinguishes attempt 2 from attempt 3. That
        // is exactly why `Structural` keys on an ordinal as well as the line —
        // without it, one entry would satisfy both positions and the walk
        // would re-sync a line early, absorbing an ordering regression.
        LedgerEntry.Structural(
            fixture = "parityStructuralControl",
            side = Side.SWIFT_ONLY,
            event = "agent_output",
            ordinal = 1,
            expectedLine = """{"agent":"Bo","attempt":0,"event":"agent_output","fields":{"inner_thought":"thinking","statement":"hello"},"phase_type":"speak_all","t":0,"type":"event"}""",
            divergenceClass = DivergenceClass.MULTI_OBJECT_SALVAGE,
        ),
        LedgerEntry.Structural(
            fixture = "parityStructuralControl",
            side = Side.KOTLIN_ONLY,
            event = "inference_started",
            ordinal = 2,
            expectedLine = """{"agent":"Bo","attempt":0,"event":"inference_started","t":0,"type":"event"}""",
            divergenceClass = DivergenceClass.MULTI_OBJECT_SALVAGE,
        ),
        LedgerEntry.Structural(
            fixture = "parityStructuralControl",
            side = Side.KOTLIN_ONLY,
            event = "inference_completed",
            ordinal = 2,
            expectedLine = """{"agent":"Bo","attempt":0,"duration_seconds":0,"event":"inference_completed","t":0,"type":"event"}""",
            divergenceClass = DivergenceClass.MULTI_OBJECT_SALVAGE,
        ),
        LedgerEntry.Structural(
            fixture = "parityStructuralControl",
            side = Side.KOTLIN_ONLY,
            event = "inference_started",
            ordinal = 3,
            expectedLine = """{"agent":"Bo","attempt":0,"event":"inference_started","t":0,"type":"event"}""",
            divergenceClass = DivergenceClass.MULTI_OBJECT_SALVAGE,
        ),
        LedgerEntry.Structural(
            fixture = "parityStructuralControl",
            side = Side.KOTLIN_ONLY,
            event = "inference_completed",
            ordinal = 3,
            expectedLine = """{"agent":"Bo","attempt":0,"duration_seconds":0,"event":"inference_completed","t":0,"type":"event"}""",
            divergenceClass = DivergenceClass.MULTI_OBJECT_SALVAGE,
        ),
        LedgerEntry.Structural(
            fixture = "parityStructuralControl",
            side = Side.KOTLIN_ONLY,
            event = "turn_skipped",
            ordinal = 0,
            expectedLine = """{"agent":"Bo","attempt":0,"event":"turn_skipped","phase_type":"speak_all","t":0,"type":"event","value":"retries exhausted"}""",
            divergenceClass = DivergenceClass.MULTI_OBJECT_SALVAGE,
        ),
    )

    /**
     * A fixture where the two engines issue different numbers of backend calls.
     *
     * @property expectedKotlin what the Kotlin engine must issue. Pinned, not
     *   bounded: a *different* surplus is a different divergence, so it fails
     *   the same way an unexpected one does.
     */
    internal data class CallCountDivergence(
        val expectedKotlin: Int,
        val divergenceClass: DivergenceClass,
    )

    /**
     * Retry-budget divergences, keyed by fixture.
     *
     * `callCount` sits outside the transcript, so neither [LedgerEntry.Value]
     * (event kind + ordinal + path) nor [LedgerEntry.Structural] (a whole
     * expected line) has a key shape for it — which is why it gets its own map
     * rather than a third entry kind.
     *
     * **Pinned rather than excused, and that is the point.** A structural
     * divergence in which one engine retries and the other does not IS a
     * retry-count divergence; `ParityGolden.Fixture.callCount` exists as a
     * first-class field for exactly that reason. Absent this map the honest
     * choices were to relax the equality assertion — which would stop
     * detecting an unintended extra call anywhere — or to let the fixture fail.
     * Pinning both sides keeps the surplus itself under assertion.
     *
     * A fixture absent from here must match Swift's count exactly.
     * `everyCallCountDivergenceNamesAKnownFixture` keeps the keys honest, and
     * a divergence that closes fails on the pinned value rather than passing
     * quietly.
     *
     * **A row must still describe a divergence**, which
     * `everyCallCountDivergenceStillDiverges` enforces. This map has no
     * counterpart to `Report.unfired`: a row whose [CallCountDivergence.expectedKotlin]
     * equals the fixture's own `callCount` asserts nothing, yet still counts as
     * a citation in `DivergenceLedgerTests.citedClasses` — so "fixing" a failed
     * pin by copying Swift's number would keep a retired [DivergenceClass]
     * accounted for and suppress the cite-or-declare-unreachable choice the
     * partition test exists to force. Delete the row instead.
     */
    internal val callCountDivergences: Map<String, CallCountDivergence> = mapOf(
        // Swift salvages the multi-object answer in one call; Kotlin fails the
        // parse and burns the full `LLMCaller.MAX_RETRIES + 1` window before
        // skipping the turn. 2 + 2 surplus = 4. Measured against the generated
        // golden, not derived from the retry constant alone — the two agree
        // here only because the divergent turn is the run's last.
        //
        // The surplus is served by `EngineParityTests`' padding scripts, not by
        // the fixture's `responses` — that list stops at Swift's 2. So this pin
        // and the Structural entries above both depend on the padding payload
        // staying schema-invalid; `EngineParityTests.padScript` carries the
        // other end of that coupling.
        "parityStructuralControl" to CallCountDivergence(
            expectedKotlin = 4,
            divergenceClass = DivergenceClass.MULTI_OBJECT_SALVAGE,
        ),
    )

    /**
     * Cases no fixture can currently drive, each with the reason.
     *
     * **Why this exists rather than a plain "every case is cited" test.** That
     * is what this file's gap list prescribed, and it is unsatisfiable: four of
     * the six cases are documented divergences the fixtures structurally
     * cannot reach, so the assertion would have been red on the day it landed.
     * The remedy inherited the blind spot of the list it came from.
     *
     * What survives of the original intent is the part that matters — a case
     * with no entry must not sit there as a pre-approved licence. So every case
     * is accounted for exactly once, either by a firing [entries] row or by a
     * row here, and `everyDivergenceClassIsCitedOrDeclaredUnreachable` enforces
     * the partition in both directions. Adding a case then forces a choice that
     * shows up in review, which is the property the gap was about.
     *
     * A reason here is a claim about the *fixtures*, not about the divergence:
     * when a fixture gains the ability to drive one of these, the row moves to
     * [entries] rather than being edited.
     */
    internal val unreachableClasses: Map<DivergenceClass, String> = mapOf(
        DivergenceClass.CANCELLATION_EVENT_TAIL to
            "needs a mid-run cancellation `ParityFixtureEmitter` never performs (ADR-023 S4)",
        DivergenceClass.DETECTOR_UNWIRED to
            "the emitter deliberately injects no detector — a real one wraps " +
            "NLLanguageRecognizer and would make the golden vary by host " +
            "(`parityRunEmitsNoLanguageMismatch` guards the omission)",
        DivergenceClass.VALIDATOR_UNPORTED to
            "needs a scenario Swift rejects, which produces no transcript to compare",
        DivergenceClass.SCOREBOARD_ORDERING to
            "reaches the transcript through the summarize template, but needs agent names " +
            "where Unicode-scalar and UTF-16 order disagree, or canonically-equivalent keys; " +
            "every fixture's agent names are BMP (katakana or ASCII), where the two orders " +
            "coincide",
    )

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
