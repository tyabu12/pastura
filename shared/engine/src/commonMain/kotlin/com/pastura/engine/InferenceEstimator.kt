package com.pastura.engine

import com.pastura.models.PairingStrategy
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario

/**
 * Estimates how many LLM inferences a scenario will cost.
 *
 * Kotlin port of **part of** `Pastura/Pastura/Engine/ScenarioLoader.swift` —
 * specifically its `estimateInferenceCount` / `estimatePhase` pair. The rest of
 * `ScenarioLoader` (YAML ingest, structural mapping) is ported separately, so
 * this is a **1 Swift file → 2 Kotlin files** split rather than a whole-type
 * port. ADR-023 §4's vocabulary has no term for that shape — it covers many
 * Swift → 1 Kotlin (`FOLDED`) but not 1 Swift → several Kotlin under different
 * names — and `shared/adr-023-port-ledger.tsv` cannot express it either, since
 * `check-adr023-port-coverage.py` forbids a `kotlin_target` on a `PORT` row. The
 * Swift side therefore carries a hand-written pointer back to this file; see the
 * `///` note on `ScenarioLoader.estimateInferenceCount`.
 *
 * Extracted rather than folded into a Kotlin `ScenarioLoader` because the
 * validator port needs the estimate and nothing else from the loader — the
 * `estimatedInferencesExceedsMaximum` / `highInferenceCount` limits are
 * `ScenarioValidator`'s, not the loader's.
 *
 * Landed as infra for the ADR-023 §6 Stage-3 Engine migration (#501): there is
 * **no Kotlin consumer yet**, because `ScenarioValidator` itself is unported
 * (`DivergenceLedger.DivergenceClass.VALIDATOR_UNPORTED`).
 */
internal object InferenceEstimator {

    /**
     * Total estimated LLM inferences for [scenario] across all rounds.
     *
     * **Returns `Long`, not `Int`, and that is the faithful port** — Swift `Int`
     * is 64-bit on every platform Pastura ships to, which is Kotlin `Long`
     * (`CanonicalizerStage2Tests`' Int/Long contract records the same mapping).
     * Kotlin `Int` is 32-bit, so it would diverge on overflow rather than merely
     * look different: `ScenarioValidator` caps `agentCount` at 10 and `rounds` at
     * 30 *before* calling this, but nothing caps a phase's `sub_rounds`. A
     * `speak_each` with `sub_rounds: 300000000` overflows 32 bits, and the wrapped
     * value is small or negative — so a ported validator would **accept** a
     * scenario Swift rejects via `estimatedInferencesExceedsMaximum`. Latent while
     * nothing consumes this, and live the moment the validator lands, which is
     * this file's whole purpose.
     *
     * Per-phase formula (per round):
     * - `speak_all` / `vote` / `reflect`: agent count
     * - `speak_each`: agent count × `sub_rounds`
     * - `whisper`: (agent count / 2) × `sub_rounds` × 2 — pairs × exchanges ×
     *   both speakers; the integer division drops the odd agent out
     * - `narrate`: 1 — the narrator is a commentator, not a participant, so the
     *   cost does not scale with agent count (#909)
     * - `choose`: agent count × 2 for `round_robin`, else agent count
     * - `conditional`: `max(sum(then), sum(else))`
     * - every code phase: 0
     */
    fun estimateInferenceCount(scenario: Scenario): Long {
        val agents = scenario.agentCount
        val perRound = scenario.phases.sumOf { estimatePhase(it, agents) }
        return perRound * scenario.rounds
    }

    /**
     * Per-phase estimate, shared by the top level and conditional-branch
     * recursion.
     *
     * The `when` is deliberately **`else`-free** so a new [PhaseType] fails to
     * compile here rather than being silently estimated as zero — the Kotlin
     * counterpart of the Swift original's no-default `switch`, which
     * `.claude/rules/engine.md` § "Adding a new `PhaseType`" lists as one of the
     * compiler-caught sites.
     */
    private fun estimatePhase(phase: Phase, agents: Int): Long = when (phase.type) {
        PhaseType.SPEAK_ALL -> agents.toLong()
        PhaseType.SPEAK_EACH -> agents.toLong() * (phase.subRounds ?: 1)
        PhaseType.VOTE, PhaseType.REFLECT -> agents.toLong()
        PhaseType.NARRATE -> 1L
        PhaseType.WHISPER -> (agents / 2).toLong() * (phase.subRounds ?: 1) * 2
        PhaseType.CHOOSE ->
            if (phase.pairing == PairingStrategy.ROUND_ROBIN) agents.toLong() * 2 else agents.toLong()
        PhaseType.SCORE_CALC,
        PhaseType.ASSIGN,
        PhaseType.ELIMINATE,
        PhaseType.SUMMARIZE,
        PhaseType.EVENT_INJECT,
        PhaseType.RELATIONSHIP_UPDATE,
        -> 0L
        // `max`, not `sum`: exactly one branch runs per invocation, so `max`
        // matches execution semantics. `sum` would over-count by construction
        // and reject scenarios that deliberately gate an expensive branch behind
        // a rare condition — the Swift doc comment calls this "deliberate", and
        // both the >50 warning and the >100 hard cap read the same reduction.
        PhaseType.CONDITIONAL -> maxOf(
            phase.thenPhases.orEmpty().sumOf { estimatePhase(it, agents) },
            phase.elsePhases.orEmpty().sumOf { estimatePhase(it, agents) },
        )
    }
}
