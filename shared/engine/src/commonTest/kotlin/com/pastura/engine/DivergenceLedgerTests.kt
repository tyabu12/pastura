package com.pastura.engine

import com.pastura.engine.DivergenceLedger.DivergenceClass
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

/**
 * Structural guards on the ledger itself, closing gaps its own KDoc named.
 *
 * Distinct from `EngineParityTests`, which checks whether the entries describe
 * reality. These check that the ledger is *well-formed*, which it can stop
 * being without any test reddening: a `DivergenceClass` with no entry is a
 * pre-approved licence, and an entry whose `fixture` matches nothing is
 * filtered out of scope by `TranscriptComparator.compare` — neither applied nor
 * reported unfired.
 */
class DivergenceLedgerTests {

    private val knownFixtures: Set<String>
        get() = ParityGolden.all.map { it.name }.toSet()

    /**
     * Every citation of a [DivergenceClass], across **both** containers.
     *
     * `callCountDivergences` cites classes too, and reading only `entries` left
     * a hole: a class cited solely by a retry-budget row and also listed in
     * `unreachableClasses` satisfied both halves of the partition below —
     * absent from `cited`, so nothing looked unaccounted; absent from the
     * intersection, so nothing looked doubly-declared. A demonstrably reachable
     * divergence would then sit on record as unreachable with no signal.
     */
    private val citedClasses: Set<DivergenceClass>
        get() = (
            DivergenceLedger.entries.map { it.divergenceClass } +
                DivergenceLedger.callCountDivergences.values.map { it.divergenceClass }
            ).toSet()

    /**
     * Every case is accounted for exactly once — cited by an entry, or declared
     * unreachable with a reason.
     *
     * Both directions matter. A case in neither is the licence hazard the
     * ledger's KDoc warns about. A case in **both** is the opposite failure: a
     * divergence that became reachable while its "cannot be driven" note stayed
     * behind, which would make the next reader trust a stale claim about the
     * fixtures.
     */
    @Test
    fun everyDivergenceClassIsCitedOrDeclaredUnreachable() {
        val declared = DivergenceClass.entries.toSet()
        val unreachable = DivergenceLedger.unreachableClasses.keys
        val cited = citedClasses

        val unaccounted = declared - cited - unreachable
        assertTrue(
            unaccounted.isEmpty(),
            "DivergenceClass case(s) with neither a ledger entry nor an unreachable " +
                "declaration: $unaccounted. A case that outlives its entries is a " +
                "pre-approved licence — cite it, declare why no fixture can drive it, " +
                "or delete it.",
        )

        val both = cited intersect unreachable
        assertTrue(
            both.isEmpty(),
            "DivergenceClass case(s) both cited by an entry and declared unreachable: " +
                "$both. The divergence became drivable — remove the unreachable row rather " +
                "than leaving a stale claim about the fixtures.",
        )
    }

    /**
     * The third gap: some fixture must drive **both** entry kinds.
     *
     * The only assertion that reddens on the incident that motivated it — see
     * `DivergenceLedger.DivergenceClass`'s KDoc for the incident and for why
     * the other guards stay green through a paired deletion.
     *
     * **Held per fixture, not across the set.** A set-level version would be
     * satisfied by two fixtures driving one kind each, which is exactly the
     * state that hides the next paired deletion: losing one fixture's only kind
     * still leaves the other's. Requiring one fixture to exhibit both costs a
     * single extra override on `parityStructuralControl` and is strictly
     * stronger.
     */
    @Test
    fun someFixtureDrivesBothEntryKinds() {
        // Filtered to real fixtures first, so a Structural+Value pair sharing a
        // typo'd name cannot satisfy this on a phantom fixture. That typo is
        // caught independently by `everyEntryNamesAKnownFixture`; filtering here
        // keeps this a standalone guard rather than one leaning on a sibling.
        val byFixture = DivergenceLedger.entries
            .filter { it.fixture in knownFixtures }
            .groupBy { it.fixture }
        val bothKinds = byFixture.filterValues { entries ->
            entries.any { it is DivergenceLedger.LedgerEntry.Structural } &&
                entries.any { it is DivergenceLedger.LedgerEntry.Value }
        }
        assertTrue(
            bothKinds.isNotEmpty(),
            "no fixture drives BOTH a Structural and a Value entry, so the parity suite can " +
                "no longer prove either entry kind is reachable. Per-fixture kind counts: " +
                byFixture.mapValues { (_, entries) ->
                    "Structural=${entries.count { it is DivergenceLedger.LedgerEntry.Structural }}, " +
                        "Value=${entries.count { it is DivergenceLedger.LedgerEntry.Value }}"
                } +
                ". Resolving a divergence retires the class its fixture arm exercised and takes " +
                "the arm with it — re-arm the control rather than deleting this assertion.",
        )
    }

    /**
     * A retry-budget pin that agrees with Swift is a no-op citation.
     *
     * The asymmetry this closes: `entries` is policed from both ends —
     * `Report.unfired` turns a row that stopped describing reality into a build
     * failure — while `callCountDivergences` is read only where the pin is
     * compared, so a row equal to the fixture's own `callCount` passes forever
     * and asserts nothing. It still counts as a citation in [citedClasses],
     * keeping a retired `DivergenceClass` "accounted for" and suppressing the
     * choice [everyDivergenceClassIsCitedOrDeclaredUnreachable] exists to
     * force. And the shape is the plausible one: converging the engines drops
     * Kotlin to Swift's count, the pin reddens, and editing the pinned number
     * is the obvious way to make that go away.
     */
    @Test
    fun everyCallCountDivergenceStillDiverges() {
        val byName = ParityGolden.all.associateBy { it.name }
        for ((name, pinned) in DivergenceLedger.callCountDivergences) {
            // A key naming no fixture is `everyCallCountDivergenceNamesAKnownFixture`'s
            // finding; reporting it twice would attribute it to the wrong cause.
            val fixture = byName[name] ?: continue
            assertNotEquals(
                fixture.callCount,
                pinned.expectedKotlin,
                "callCountDivergences[\"$name\"] pins Kotlin at the same ${fixture.callCount} " +
                    "calls Swift issues, so it excuses nothing while still citing " +
                    "${pinned.divergenceClass}. If the divergence closed, delete the row — " +
                    "widening it to match keeps a retired class accounted for and hides that " +
                    "the class now needs an entry, an unreachable declaration, or deletion.",
            )
        }
    }

    /** A retry-budget pin naming no fixture is as silent as a mis-keyed entry. */
    @Test
    fun everyCallCountDivergenceNamesAKnownFixture() {
        val known = knownFixtures
        val unknown = DivergenceLedger.callCountDivergences.keys - known
        assertEquals(
            emptySet(),
            unknown,
            "callCountDivergences key(s) naming a fixture that does not exist: $unknown. " +
                "Known fixtures: $known",
        )
    }

    /** An unreachable declaration without a reason is a bare "not reachable". */
    @Test
    fun everyUnreachableDeclarationCarriesAReason() {
        val blank = DivergenceLedger.unreachableClasses.filterValues { it.isBlank() }.keys
        assertTrue(
            blank.isEmpty(),
            "unreachable declaration(s) with no reason: $blank",
        )
    }

    /**
     * An entry naming a fixture that does not exist is silently out of scope.
     *
     * `TranscriptComparator.compare` filters by `fixture` name, so a typo
     * removes the entry from every comparison — neither applied nor reported
     * unfired — and it then disappears without a signal when the divergence it
     * covered closes.
     *
     * Checkable only because `ParityGolden` carries a generated `all` roster;
     * against the hand-listed properties it would itself be a drifting subset.
     */
    @Test
    fun everyEntryNamesAKnownFixture() {
        val known = knownFixtures
        val unknown = DivergenceLedger.entries.map { it.fixture }.toSet() - known
        assertEquals(
            emptySet(),
            unknown,
            "ledger entr(ies) naming a fixture that does not exist: $unknown. " +
                "Known fixtures: $known",
        )
    }
}
