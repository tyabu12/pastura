package com.pastura.engine

import com.pastura.engine.DivergenceLedger.DivergenceClass
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Structural guards on the ledger itself, closing gaps its own KDoc named.
 *
 * These are distinct from `EngineParityTests`, which checks whether the entries
 * describe reality. These check whether the ledger is *well-formed* — a
 * malformed one fails silently rather than loudly, which is why it needs its
 * own tests:
 *
 * - a `DivergenceClass` with no entry is a pre-approved licence a later author
 *   can attach to with no enum diff at all;
 * - an entry whose `fixture` matches no fixture is filtered out of scope by
 *   `TranscriptComparator.compare`, so it is neither applied nor reported
 *   unfired — it vanishes with no signal.
 */
class DivergenceLedgerTests {

    private val citedClasses: Set<DivergenceClass>
        get() = DivergenceLedger.entries.map { it.divergenceClass }.toSet()

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
     * removes the entry from every comparison — it is neither applied nor
     * reported unfired. It then disappears without a signal when the divergence
     * it covered closes, which is the second gap the ledger's KDoc named.
     *
     * This is checkable only because `ParityGolden` carries a generated `all`
     * roster; against the hand-listed properties it would itself have been a
     * subset that drifts.
     */
    @Test
    fun everyEntryNamesAKnownFixture() {
        val known = ParityGolden.all.map { it.name }.toSet()
        val unknown = DivergenceLedger.entries.map { it.fixture }.toSet() - known
        assertEquals(
            emptySet(),
            unknown,
            "ledger entr(ies) naming a fixture that does not exist: $unknown. " +
                "Known fixtures: $known",
        )
    }
}
