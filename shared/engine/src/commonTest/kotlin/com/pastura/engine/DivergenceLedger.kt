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
 * [entries] is read by `EngineParityTests`, which replays each `ParityGolden`
 * fixture through the Kotlin engine and compares — so the paragraphs below
 * describe a gate that runs. Slice 1b (#1458) joined the schema, the comparator
 * and the golden, which 1a (#1387) had left as three unconnected pieces.
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
     * `DivergenceLedgerTests` (#1458) guards the three ways this file rots: a
     * case that outlives its entries (a pre-approved licence), an entry whose
     * `fixture` names nothing (silently out of scope rather than unfired), and
     * a case deleted **together** with its entries — which is what resolving a
     * divergence does, and which the first two miss by construction: nothing is
     * left unfired, and the accounted-for partition quantifies over survivors.
     * ADR-021's Amendment 2026-08-06 retired `SCHEMA_GUARD_POSITION` and cost
     * the control its only structural arm exactly that way; only
     * `someFixtureDrivesBothEntryKinds` reddens on it.
     *
     * That guard was verified by reproducing the incident rather than by
     * argument: converge the engines on the control's divergent turn, then
     * delete [DivergenceClass.MULTI_OBJECT_SALVAGE] with **both** the [entries]
     * rows and the [callCountDivergences] row citing it — leaving either behind
     * fails to compile, and leaving the map row would redden the call-count
     * assertion instead, falsifying the "only kind-coverage reddens" claim.
     * Done that way, `EngineParityTests` goes green and the other two guards
     * stay green.
     *
     * A case no fixture can drive is declared in [unreachableClasses] rather
     * than cited: the plain "every case is cited" test this KDoc once
     * prescribed is unsatisfiable, and that property's KDoc records why.
     */
    internal enum class DivergenceClass(val documentedAt: String) {
        // `CANCELLATION_EVENT_TAIL` lived here — Swift's `ConditionalHandler` returned
        // silently on cancellation, so its runner emitted `phaseCompleted(.conditional)`
        // for a branch cut short where Kotlin unwinds. ADR-023 S4 (#1622) fixed Swift
        // (cancellation now throws, one `.error(.cancelled)` per run) and
        // `parityCancelConditional` pins the shared tail on both engines, so the case
        // is DELETED for the same reason `SCHEMA_GUARD_POSITION` below was.

        // `SCHEMA_GUARD_POSITION` lived here — Swift returned a present-but-empty
        // canonical field as an `agentOutput` where Kotlin's parser guard exhausted
        // retries into a `turnSkipped`. ADR-021 § Amendment 2026-08-06 resolved it
        // (both engines now skip), so the case is DELETED rather than kept with a
        // "resolved" marker: a case that outlives its entries becomes a pre-approved
        // licence a later author can attach to with no enum diff at all.

        /**
         * The ADR-010 language-adherence retry is dormant on the Kotlin side
         * **of the parity harness**. `SimulationEngine` can be fed a detector
         * since #1603 (`SimulationEngine(detector = …)`), but the parity harness
         * constructs `SimulationEngine()` with no detector, so `languageMismatch`
         * events reach the Swift transcript alone. Retiring this requires feeding
         * a scripted detector through the parity fixtures — a Stage-4 fixture
         * change, deliberately not #1603.
         */
        DETECTOR_UNINJECTED(
            "SimulationEngine.kt class KDoc § Knowingly absent (the struck-through " +
                "`LanguageDetector` / `EngineLogger` injection row); ADR-023 §4",
        ),

        /**
         * The preflight linter's D2d conditions group carries two stated
         * Kotlin↔Swift divergences that D3 makes run-visible. (1) Swift's
         * numeric-operand check parses with `Double(text)`, which also
         * accepts `nan` / `inf` / `infinity` / hex-floats (no finding), while
         * Kotlin uses the evaluator's decimal-literal regex, so the same
         * operand fires an R15 `unknown-condition-identifier` warning on the
         * Kotlin side only. (2) The relative order of two findings within one
         * condition is not a parity contract for non-ASCII operands: both
         * sides iterate `keys.sorted()`, but Swift's `String <` is
         * canonical-equivalence-aware scalar order and Kotlin's `compareTo`
         * is UTF-16 code-unit order, which agree only on ASCII / Latin-1.
         * Before D3 (#1591) neither was observable — the linter ran nowhere
         * on the Kotlin run path; D3's `semanticLintGate` turns a warning
         * into a run-visible `Summary("⚠️ …")`, so both are transcript
         * divergences now.
         */
        LINT_PREDICATE_DIVERGENCE("ScenarioSemanticLinter.kt conditionFindings + classifyOperand body comments; ADR-023 §4 D2d"),

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
         * Both sides are pinned by parser tests fed byte-identical input:
         * `salvagesFirstObjectFromMultiObjectResponseWhenSchemaGuardPasses`
         * (`JSONResponseParserTests+Repair.swift`) and
         * `multiObjectResponseFailsTheParseEvenWithASatisfiedSchema`
         * (`JSONResponseParserTests.kt`).
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
     * entry can never leak into a fixture it was not written for — and one
     * whose `fixture` names nothing is silently out of scope rather than
     * unfired, which `everyEntryNamesAKnownFixture` catches.
     *
     * **Adding an entry is not the default response to a red parity run.**
     * ADR-023 §12 condition 3 chose dual-landing: on a surface with a Kotlin
     * counterpart, a new Swift-only divergence is *fixed*, not excused. An
     * entry is correct only for a divergence genuinely accepted and already
     * documented — which citing a [DivergenceClass] enforces.
     */
    internal val entries: List<LedgerEntry> = listOf(
        // Ordinal 0, not 3: the divergent fixture's first three answers drive
        // アオイ's turn to a skip, so the FIRST `agent_output` Swift emits is
        // ハルト's — the one carrying the float. Counted against the generated
        // bytes, not inferred from the response indices, because those two
        // disagree exactly when a turn is skipped.
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
        // `someFixtureDrivesBothEntryKinds` holds it to.
        LedgerEntry.Value(
            fixture = "parityStructuralControl",
            event = "agent_output",
            ordinal = 0,
            path = "fields.confidence",
            expectedSwift = "1",
            expectedKotlin = "1.0",
            divergenceClass = DivergenceClass.NUMBER_LITERAL_FORMATTING,
        ),

        // Bo's turn (call 1) is the structural arm. Swift salvages in one call
        // and emits an `agentOutput`; Kotlin fails the parse and burns two more
        // attempts before skipping. Each attempt emits its own
        // `inference_started` / `inference_completed` pair, so the surplus is
        // four Kotlin-only lines BEFORE the `turnSkipped` — the part an estimate
        // based on "one event each way" misses.
        //
        // ⚠️ Both `inference_started` lines are BYTE-IDENTICAL, as are both
        // `inference_completed` ones: with `t` and `attempt` pinned to 0,
        // nothing distinguishes attempt 2 from attempt 3. Hence `Structural`
        // keying on an ordinal as well as the line — otherwise one entry would
        // satisfy both positions and the walk would re-sync a line early,
        // absorbing an ordering regression.
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
     * **Pinned rather than excused, and that is the point.** Absent this map
     * the honest choices were to relax the equality assertion — which would
     * stop detecting an unintended extra call anywhere — or to let the fixture
     * fail. A fixture absent from here must match Swift's count exactly, and a
     * divergence that closes fails on the pinned value rather than passing
     * quietly. `everyCallCountDivergenceStillDiverges` and
     * `everyCallCountDivergenceNamesAKnownFixture` keep the rows honest; the
     * former's KDoc has the asymmetry with `Report.unfired` that makes it
     * necessary.
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
     * the six cases are documented divergences the fixtures structurally cannot
     * reach, so the assertion would have been red the day it landed. (The gap
     * list inherited the blind spot of the list it was drawn from — a hazard of
     * gap lists generally.)
     *
     * What survives of the intent is the part that matters — a case with no
     * entry must not sit there as a pre-approved licence. So every case is
     * accounted for exactly once, by a firing [entries] row or by a row here,
     * with `everyDivergenceClassIsCitedOrDeclaredUnreachable` enforcing the
     * partition both ways. Adding a case then forces a choice visible in review.
     *
     * A reason here is a claim about the *fixtures*, not about the divergence:
     * when a fixture gains the ability to drive one of these, the row moves to
     * [entries] rather than being edited.
     */
    internal val unreachableClasses: Map<DivergenceClass, String> = mapOf(
        DivergenceClass.DETECTOR_UNINJECTED to
            "the emitter deliberately injects no detector — a real one wraps " +
            "NLLanguageRecognizer and would make the golden vary by host " +
            "(`parityRunEmitsNoLanguageMismatch` guards the omission)",
        DivergenceClass.LINT_PREDICATE_DIVERGENCE to
            "needs a condition operand that is non-finite/hex-float or non-ASCII with two " +
            "findings in one condition; re-grepped 2026-08-29 (S4) over the nine fixtures' eight " +
            "scenarios — `condition` across ParityGolden.kt, `if:` across " +
            "tools/harness/Fixtures/*.yaml plus the six presets now used " +
            "(target_score_race, prisoners_dilemma, bokete, word_wolf, last_fable, " +
            "DemoPresets/iiwake_battle_v1) — and every condition in the set is a plain " +
            "ASCII comparison of identifiers, decimal literals or a quoted ASCII string: " +
            "target_score_race `max_score >= 3`, parity_cancel `current_round >= 1`, " +
            "word_wolf `current_event != \"\"` and `vote_winner == wolf_name`; the four " +
            "other scenarios declare no conditional at all",
        DivergenceClass.SCOREBOARD_ORDERING to
            "reaches the transcript through the summarize template, but needs agent names " +
            "where Unicode-scalar and UTF-16 order disagree, or two scoreboard keys that are " +
            "canonically equivalent while differing byte-wise. Re-verified 2026-08-29 across " +
            "all six fixtures: bokete and iiwake_battle_v1 widened the set from ASCII and " +
            "katakana to kanji and hiragana (ツッコミ太郎, あるある先生, 国際派ジョージ, " +
            "浪花節たけし, …), and every name is still BMP, where scalar and UTF-16 order " +
            "coincide. The second arm is closed by a separate property: several names carry a " +
            "decomposable dakuten (ジ / ブ / ボ), but each YAML stores only the precomposed " +
            "NFC form, so no two keys are canonically equivalent and Swift's collapse has " +
            "nothing to collapse",
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
