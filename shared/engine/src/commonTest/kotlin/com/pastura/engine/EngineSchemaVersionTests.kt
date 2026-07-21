package com.pastura.engine

import com.pastura.models.PhaseType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * commonTest parity spec for [EngineSchemaVersion], ported 1:1 from
 * `Pastura/PasturaTests/Engine/EngineSchemaVersionTests.swift`.
 */
class EngineSchemaVersionTests {

    /** The wire raw value for a phase type — mirrors [EngineSchemaVersion]'s idiom. */
    private fun PhaseType.serialName(): String =
        PhaseType.serializer().descriptor.getElementName(ordinal)

    // MARK: - Current version constant

    @Test
    fun currentVersionIsFive() {
        // Bumped 1→2 for event_inject no_repeat (#1006, ADR-020 §8); 2→3 for the
        // narrate phase (#909, ADR-020 §9); 3→4 for Persona.secret (#914 — an old
        // app silently drops the key and runs every agent without its hidden
        // agenda); 4→5 for ScoreCalcLogic.pairwise_payoff (ADR-027 — a new
        // by-name-parsed score_calc logic, an old app throws on it via D5). Update
        // in lockstep with any further EngineSchemaVersion.current bump.
        assertEquals(5, EngineSchemaVersion.current)
    }

    // MARK: - D2 (phase-capability) branch

    @Test
    fun nilPhasesAreUnconstrained() {
        // A legacy/older feed with no `phases` field must not grey out — the
        // index gate cannot determine capability, so it defers to D3 + the
        // parse-throw backstop.
        assertTrue(EngineSchemaVersion.isCompatible(phases = null, minEngineVersion = null))
    }

    @Test
    fun emptyPhasesAreCompatible() {
        assertTrue(EngineSchemaVersion.isCompatible(phases = emptyList(), minEngineVersion = null))
    }

    @Test
    fun allKnownPhasesAreCompatible() {
        val known = PhaseType.entries.map { it.serialName() }
        assertTrue(EngineSchemaVersion.isCompatible(phases = known, minEngineVersion = null))
    }

    @Test
    fun everyCurrentPhaseKindIsIndividuallyCompatible() {
        // No shipped phase kind may grey out at baseline.
        for (phase in PhaseType.entries) {
            assertTrue(
                EngineSchemaVersion.isCompatible(
                    phases = listOf(phase.serialName()),
                    minEngineVersion = null,
                ),
                "${phase.serialName()} should be compatible at baseline",
            )
        }
    }

    @Test
    fun unknownPhaseIsIncompatible() {
        assertFalse(
            EngineSchemaVersion.isCompatible(
                phases = listOf("vote", "future_phase"),
                minEngineVersion = null,
            ),
        )
    }

    // MARK: - D3 (declared min_engine_version) branch

    @Test
    fun minEngineVersionEqualToCurrentIsCompatible() {
        assertTrue(
            EngineSchemaVersion.isCompatible(
                phases = null,
                minEngineVersion = EngineSchemaVersion.current,
            ),
        )
    }

    @Test
    fun minEngineVersionZeroIsCompatible() {
        assertTrue(EngineSchemaVersion.isCompatible(phases = null, minEngineVersion = 0))
    }

    @Test
    fun minEngineVersionAboveCurrentIsIncompatible() {
        assertFalse(
            EngineSchemaVersion.isCompatible(
                phases = null,
                minEngineVersion = EngineSchemaVersion.current + 1,
            ),
        )
    }

    @Test
    fun knownPhasesButFutureMinEngineVersionIsIncompatible() {
        // D3 alone gates a scenario whose phases are all known but which
        // declares a future requirement (a semantics-only or non-phase break).
        assertFalse(
            EngineSchemaVersion.isCompatible(
                phases = listOf("vote", "speak_all"),
                minEngineVersion = EngineSchemaVersion.current + 1,
            ),
        )
    }

    // MARK: - AND-composition (compatible ⇔ both gates pass)

    @Test
    fun bothGatesFailingIsIncompatible() {
        assertFalse(
            EngineSchemaVersion.isCompatible(
                phases = listOf("future_phase"),
                minEngineVersion = EngineSchemaVersion.current + 1,
            ),
        )
    }
}
