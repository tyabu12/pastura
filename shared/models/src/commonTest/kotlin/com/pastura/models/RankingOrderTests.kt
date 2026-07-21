package com.pastura.models

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Swift↔Kotlin parity for [RankingOrder] (ADR-023 PR0-a2).
 *
 * **Condition-2 carve-out — behavioural parity, not golden JSON.** ADR-023 §12
 * condition 2 asks that every mirrored type land with golden-parity coverage in
 * the same PR. [RankingOrder] is a namespace of pure static functions with no
 * serialized data, so golden JSON parity has nothing to encode — the instrument
 * is the wrong shape, not missing. Its real contract is the tie-break rule
 * (value descending, then **name descending**), which is what must not fork from
 * Swift. This suite pins that rule on the Kotlin side against the exact cases the
 * Swift original documents (`RankingOrder.swift`), the "shared fixture test pins
 * the behaviour on both sides" pattern ADR-023 §7 names for the cross-boundary
 * `ScenarioConventions` rule. A silent narrowing of condition 2 would be to skip
 * the type; this is the reframe, recorded rather than assumed. `RankingOrder`
 * unblocks the engine's `VoteTally` port (#501 freeze-lift ruling, 2026-07-19).
 */
class RankingOrderTests {

    @Test
    fun higherValueOutranksLowerRegardlessOfName() {
        // "Alice" < "Bob" by name, but the higher value wins outright.
        assertTrue(RankingOrder.isOrderedBefore("Alice", 5, "Bob", 3))
        assertFalse(RankingOrder.isOrderedBefore("Bob", 3, "Alice", 5))
    }

    @Test
    fun equalValuesBreakByNameDescending() {
        // Name descending: "Bob" outranks "Alice" on a value tie.
        assertTrue(RankingOrder.isOrderedBefore("Bob", 3, "Alice", 3))
        assertFalse(RankingOrder.isOrderedBefore("Alice", 3, "Bob", 3))
    }

    @Test
    fun leaderOfEmptyRosterIsNull() {
        assertNull(RankingOrder.leader(values = emptyMap(), roster = emptyList()))
    }

    @Test
    fun leaderIsTheHighestValue() {
        assertEquals(
            "Bob",
            RankingOrder.leader(values = mapOf("Alice" to 1, "Bob" to 5), roster = listOf("Alice", "Bob")),
        )
    }

    @Test
    fun leaderBreaksATieByNameDescending() {
        // Equal scores → the name-descending winner, matching VoteTally (#1087).
        assertEquals(
            "Bob",
            RankingOrder.leader(values = mapOf("Alice" to 3, "Bob" to 3), roster = listOf("Alice", "Bob")),
        )
    }

    @Test
    fun leaderTreatsMissingKeysAsZero() {
        // Bob absent from values → counts as 0, so Alice (1) leads.
        assertEquals(
            "Alice",
            RankingOrder.leader(values = mapOf("Alice" to 1), roster = listOf("Alice", "Bob")),
        )
    }
}
