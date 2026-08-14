package com.pastura.engine

import com.pastura.models.AssignTarget
import com.pastura.models.PairingStrategy
import com.pastura.models.Persona
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import com.pastura.models.ScoreCalcLogic
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Kotlin sibling of the Swift inference-estimator coverage, which is **split
 * across two files** — both are ported here:
 *
 * - `Pastura/PasturaTests/Engine/ScenarioLoaderTests.swift:380-435` — the six
 *   flat-phase assertions (`speak_all`, `speak_each` × `sub_rounds`, `vote`,
 *   `choose` round-robin vs individual, code phases → 0).
 * - `Pastura/PasturaTests/Engine/ConditionalScenarioIOTests.swift:269-333` —
 *   `estimateInferenceCountUsesMaxOfBranches` and
 *   `estimateInferenceCountAsymmetricBranchesTakesMax`, which pin the
 *   `max`-not-`sum` branch reduction the Swift doc comment calls *deliberate*.
 *
 * Porting only the first file would silently drop conditional-branch coverage,
 * which is the one arm where a plausible-looking implementation (`sum`) is
 * wrong: it over-counts by construction and rejects scenarios that gate an
 * expensive branch behind a rare condition.
 *
 * **Depth-2 (a `conditional` inside a branch) is deliberately not fixtured.** It
 * is unreachable input: `ScenarioValidator` rejects it and
 * `ConditionalHandler.subHandlers` registers no `conditional` sub-handler, so
 * both the validation and dispatch layers refuse it. Note the contingency —
 * [InferenceEstimator] itself imposes **no** depth limit, so the whole
 * justification rests on that external depth-1 rule. If it is ever relaxed, this
 * fixture set becomes insufficient and the recursion needs its own case.
 *
 * Two arms have **no Swift sibling** and are added here because
 * [InferenceEstimator] implements them and nothing else would see a regression:
 * `reflect` (shares `vote`'s agent-count arm) and `whisper` / `narrate`, whose
 * formulas are unique. `whisper` in particular is the only arm with a floor
 * division, so an odd agent count is asserted explicitly.
 *
 * ## ADR-023 §12 condition-4 perturbation record
 *
 * Each mechanism was broken in isolation in
 * `shared/engine/src/commonMain/kotlin/com/pastura/engine/InferenceEstimator.kt`
 * and the named dedicated claimant confirmed to redden. Every mutation's anchor
 * count was asserted before applying, and the mutated text re-checked to confirm
 * it actually landed — a `replace` that silently no-ops leaves the original
 * behaviour and reads as verified. All anchors matched **exactly once** except
 * the `?: 1` row, which matched **twice by design** (one mechanism spelled at two
 * sites) and was mutated at both. The unmutated baseline was measured green
 * immediately before the first mutation and again after the last revert, so every
 * reddening below is signal rather than pre-existing noise. Counts are measured,
 * not derived — re-measure rather than reason if you change a fixture. Measured
 * 2026-08-14, #1464.
 *
 * | Mechanism broken | Mutation | Dedicated claimant | Incidental |
 * |---|---|---|---|
 * | Branch reduction is `max` | the `else` argument gains the `then` sum, making `maxOf(then, then + else)` ≡ `sum` for non-negative costs | [conditionalTakesTheMaxOfSymmetricBranches] | none |
 * | …other polarity | `maxOf(…)` → `minOf(…)` | [conditionalAsymmetricBranchesTakeTheMax] | none |
 * | `sub_rounds` multiplier | `agents * (phase.subRounds ?: 1)` → `agents` | [speakEachMultipliesBySubRounds] | 1 — [conditionalAsymmetricBranchesTakeTheMax] gates a `sub_rounds` phase behind its `then` branch |
 * | The `?: 1` default itself | **both** `?: 1` sites → `?: 0` | [whisperPairsOffAndCountsBothSpeakers] | 1 — [speakEachMultipliesBySubRounds]; [speakAllAndVoteCostOneInferencePerAgent] stayed green, see note 1 |
 * | Round-robin doubling | `agents * 2` → `agents` | [chooseDoublesForRoundRobinOnly] | none |
 * | …other polarity | the `if` condition negated (`==` → `!=`) | [chooseDoublesForRoundRobinOnly] | none |
 * | `whisper` floor division | `(agents / 2)` → `agents` | [whisperPairsOffAndCountsBothSpeakers] | none |
 * | `narrate` is agent-count-independent | `1` → `agents` | [narrateCostsOneInferenceRegardlessOfAgentCount] | none |
 * | Code phases cost 0 | the shared zero arm → `agents` | [codePhasesCostNothing] | none |
 * | Top-level phase list is **summed** | `scenario.phases.sumOf { … }` → `maxOfOrNull { … } ?: 0` | [phaseCostsAreSummedNotReducedAtTopLevelAndInsideABranch] | none |
 * | …and not merely its first phase | same site → `firstOrNull()?.let { … } ?: 0` | same | none |
 * | Branch phase lists are **summed** | **both** branch `.sumOf { … }` sites → `maxOfOrNull { … } ?: 0` | same | none |
 * | Rounds multiplier | `perRound * scenario.rounds` → `perRound` | [speakAllAndVoteCostOneInferencePerAgent] | 7 — every other fixture whose per-round cost is non-zero; [codePhasesCostNothing] is exempt because its `perRound` is 0, so `perRound * rounds == perRound` there |
 *
 * No test **outside** this class reddened for any of the thirteen mutations, which
 * is the expected shape rather than a gap: [InferenceEstimator] has no other
 * consumer in `shared/engine` yet.
 *
 * Three things this table encodes that are easy to misread:
 *
 * 1. **The `?: 1` row names the fixture that omits `sub_rounds`, not the
 *    obvious one.** [speakAllAndVoteCostOneInferencePerAgent] was measured and
 *    stayed **green** — a `speak_all` fixture never reads `subRounds`, so no
 *    defaulting break can reach it. Recorded here so nobody later promotes it to
 *    claimant on the assumption that it covers the arm.
 *    [whisperPairsOffAndCountsBothSpeakers] catches it because its second case
 *    deliberately omits `sub_rounds`; note the mutation is the one row applied at
 *    **two** sites, since the default is one mechanism spelled twice.
 * 2. **Both `conditional` fixtures are load-bearing, and neither alone is
 *    enough** — and the first two rows are the measurement proving it. The
 *    symmetric fixture has `max == min` by construction, so it cannot see the
 *    `min` mutation; the asymmetric one has a zero `else`, so `sum == max` and it
 *    cannot see the `sum` mutation. Each row's claimant is therefore the fixture
 *    the *other* row cannot use. Deleting either leaves one polarity unmeasured
 *    while the suite stays green.
 * 3. **The rounds-multiplier row's 7 incidental reddenings are not redundancy.**
 *    They are why a single dedicated claimant suffices there: no fixture is
 *    *designed* to isolate the multiplier, so the arm is pinned by breadth rather
 *    than by one case. The exact invariance condition is per **case**, not per
 *    fixture: a case survives the mutation iff `perRound == 0 || rounds == 1`.
 *    That enumerates the right 7 today only because no fixture is made solely of
 *    invariant cases — [whisperPairsOffAndCountsBothSpeakers]' second case and
 *    [phaseCostsAreSummedNotReducedAtTopLevelAndInsideABranch]' last two are each
 *    individually invariant (`rounds = 1`) while their enclosing tests still
 *    redden on another case. [codePhasesCostNothing] is the one fixture where
 *    *every* case is invariant, which is why it alone stays green at `rounds = 3`.
 *    Reasoning from the looser "every fixture with `rounds > 1`" would read that
 *    green as a regression.
 */
class InferenceEstimatorTests {

    private fun scenario(
        agents: Int,
        rounds: Int,
        phases: List<Phase>,
    ) = Scenario(
        id = "t",
        name = "T",
        description = "T",
        language = "ja",
        simulationLanguage = null,
        agentCount = agents,
        rounds = rounds,
        logWindow = null,
        context = "C",
        personas = (0 until agents).map { Persona(name = "A$it", description = "D") },
        phases = phases,
    )

    // ── Flat phases (Swift: ScenarioLoaderTests.swift:380-435) ──────────────

    @Test
    fun speakAllAndVoteCostOneInferencePerAgent() {
        // 5 agents × 3 rounds = 15.
        assertEquals(
            15,
            InferenceEstimator.estimateInferenceCount(
                scenario(agents = 5, rounds = 3, phases = listOf(Phase(type = PhaseType.SPEAK_ALL))),
            ),
        )
        // 5 agents × 2 rounds = 10.
        assertEquals(
            10,
            InferenceEstimator.estimateInferenceCount(
                scenario(agents = 5, rounds = 2, phases = listOf(Phase(type = PhaseType.VOTE))),
            ),
        )
        // `reflect` shares the same arm — no Swift sibling, see the class KDoc.
        assertEquals(
            10,
            InferenceEstimator.estimateInferenceCount(
                scenario(agents = 5, rounds = 2, phases = listOf(Phase(type = PhaseType.REFLECT))),
            ),
        )
    }

    @Test
    fun speakEachMultipliesBySubRounds() {
        // 3 agents × 3 sub-rounds × 2 rounds = 18.
        assertEquals(
            18,
            InferenceEstimator.estimateInferenceCount(
                scenario(
                    agents = 3,
                    rounds = 2,
                    phases = listOf(Phase(type = PhaseType.SPEAK_EACH, subRounds = 3)),
                ),
            ),
        )
        // Absent `sub_rounds` defaults to 1: 3 × 1 × 2 = 6.
        assertEquals(
            6,
            InferenceEstimator.estimateInferenceCount(
                scenario(
                    agents = 3,
                    rounds = 2,
                    phases = listOf(Phase(type = PhaseType.SPEAK_EACH)),
                ),
            ),
        )
    }

    @Test
    fun chooseDoublesForRoundRobinOnly() {
        // Round-robin: 5 agents × 2 (per pair) × 2 rounds = 20.
        assertEquals(
            20,
            InferenceEstimator.estimateInferenceCount(
                scenario(
                    agents = 5,
                    rounds = 2,
                    phases = listOf(
                        Phase(type = PhaseType.CHOOSE, pairing = PairingStrategy.ROUND_ROBIN),
                    ),
                ),
            ),
        )
        // Individual (no pairing): 5 agents × 2 rounds = 10.
        assertEquals(
            10,
            InferenceEstimator.estimateInferenceCount(
                scenario(agents = 5, rounds = 2, phases = listOf(Phase(type = PhaseType.CHOOSE))),
            ),
        )
    }

    @Test
    fun codePhasesCostNothing() {
        assertEquals(
            0,
            InferenceEstimator.estimateInferenceCount(
                scenario(
                    agents = 5,
                    rounds = 3,
                    phases = listOf(
                        Phase(type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.VOTE_TALLY),
                        Phase(
                            type = PhaseType.ASSIGN,
                            source = "words",
                            target = AssignTarget.RANDOM_ONE,
                        ),
                        Phase(type = PhaseType.ELIMINATE),
                        Phase(type = PhaseType.SUMMARIZE, template = "Done"),
                        Phase(
                            type = PhaseType.EVENT_INJECT,
                            source = "events",
                            probability = 0.5,
                        ),
                        Phase(type = PhaseType.RELATIONSHIP_UPDATE, voteAgainst = -1),
                    ),
                ),
            ),
        )
    }

    // ── Arms with no Swift sibling (see class KDoc) ─────────────────────────

    @Test
    fun whisperPairsOffAndCountsBothSpeakers() {
        // 4 agents → 2 pairs × 3 exchanges × 2 speakers = 12, × 2 rounds = 24.
        assertEquals(
            24,
            InferenceEstimator.estimateInferenceCount(
                scenario(
                    agents = 4,
                    rounds = 2,
                    phases = listOf(Phase(type = PhaseType.WHISPER, subRounds = 3)),
                ),
            ),
        )
        // 5 agents floor-divides to 2 pairs — the odd agent sits out — and the
        // absent `sub_rounds` defaults to 1: 2 × 1 × 2 = 4, × 1 round = 4.
        assertEquals(
            4,
            InferenceEstimator.estimateInferenceCount(
                scenario(
                    agents = 5,
                    rounds = 1,
                    phases = listOf(Phase(type = PhaseType.WHISPER)),
                ),
            ),
        )
    }

    @Test
    fun narrateCostsOneInferenceRegardlessOfAgentCount() {
        // The narrator is a commentator, not a participant (#909), so the cost
        // is 1 per round at any agent count — asserted at two counts so an
        // `agents`-scaling regression cannot hide behind a coincidence.
        assertEquals(
            3,
            InferenceEstimator.estimateInferenceCount(
                scenario(agents = 2, rounds = 3, phases = listOf(Phase(type = PhaseType.NARRATE))),
            ),
        )
        assertEquals(
            3,
            InferenceEstimator.estimateInferenceCount(
                scenario(agents = 9, rounds = 3, phases = listOf(Phase(type = PhaseType.NARRATE))),
            ),
        )
    }

    @Test
    fun phaseCostsAreSummedNotReducedAtTopLevelAndInsideABranch() {
        // Every other fixture holds exactly one phase per level, so the three
        // `sumOf` aggregations are only ever pinned at cardinality 1 — where
        // `sum`, `max` and `first` all agree. These two cases are the only place
        // they can disagree.
        //
        // 3 agents: speak_all = 3, speak_each × 2 sub-rounds = 6, score_calc = 0.
        // Sum = 9, `max` = 6, `first` = 3 — three distinct values, so no
        // aggregation regression can land on the right answer by coincidence.
        val mixed = listOf(
            Phase(type = PhaseType.SPEAK_ALL),
            Phase(type = PhaseType.SPEAK_EACH, subRounds = 2),
            Phase(type = PhaseType.SCORE_CALC, logic = ScoreCalcLogic.VOTE_TALLY),
        )
        // 9 per round × 2 rounds = 18.
        assertEquals(
            18,
            InferenceEstimator.estimateInferenceCount(
                scenario(agents = 3, rounds = 2, phases = mixed),
            ),
        )
        // The same three phases as a conditional's `then`, with `else` **absent**
        // rather than present-and-zero: max(9, 0) × 1 round = 9. An `else`-less
        // conditional is a real YAML shape.
        assertEquals(
            9,
            InferenceEstimator.estimateInferenceCount(
                scenario(
                    agents = 3,
                    rounds = 1,
                    phases = listOf(
                        Phase(
                            type = PhaseType.CONDITIONAL,
                            condition = "current_round == 1",
                            thenPhases = mixed,
                            elsePhases = null,
                        ),
                    ),
                ),
            ),
        )
        // Mirror image: `then` absent instead. `estimatePhase` has **two**
        // `orEmpty()` sites and `thenPhases` is just as nullable, so covering only
        // the `else` one would leave the sibling arm unexercised while looking
        // like the null path was handled. max(0, 9) × 1 = 9.
        assertEquals(
            9,
            InferenceEstimator.estimateInferenceCount(
                scenario(
                    agents = 3,
                    rounds = 1,
                    phases = listOf(
                        Phase(
                            type = PhaseType.CONDITIONAL,
                            condition = "current_round == 1",
                            thenPhases = null,
                            elsePhases = mixed,
                        ),
                    ),
                ),
            ),
        )
    }

    // ── conditional (Swift: ConditionalScenarioIOTests.swift:269-333) ───────

    @Test
    fun conditionalTakesTheMaxOfSymmetricBranches() {
        // max(2, 2) × 3 rounds = 6 — NOT the 4 × 3 = 12 that `sum` would give.
        assertEquals(
            6,
            InferenceEstimator.estimateInferenceCount(
                scenario(
                    agents = 2,
                    rounds = 3,
                    phases = listOf(
                        Phase(
                            type = PhaseType.CONDITIONAL,
                            condition = "current_round == 1",
                            thenPhases = listOf(
                                Phase(
                                    type = PhaseType.SPEAK_ALL,
                                    prompt = "p",
                                    outputSchema = mapOf("statement" to "string"),
                                ),
                            ),
                            elsePhases = listOf(
                                Phase(
                                    type = PhaseType.VOTE,
                                    prompt = "v",
                                    outputSchema = mapOf("vote" to "string"),
                                ),
                            ),
                        ),
                    ),
                ),
            ),
        )
    }

    @Test
    fun conditionalAsymmetricBranchesTakeTheMax() {
        // A rarely-taken expensive `then` (2 agents × 3 sub-rounds = 6) against a
        // zero-cost `else`: max(6, 0) × 2 rounds = 12.
        assertEquals(
            12,
            InferenceEstimator.estimateInferenceCount(
                scenario(
                    agents = 2,
                    rounds = 2,
                    phases = listOf(
                        Phase(
                            type = PhaseType.CONDITIONAL,
                            condition = "current_round == 99",
                            thenPhases = listOf(
                                Phase(
                                    type = PhaseType.SPEAK_EACH,
                                    prompt = "p",
                                    outputSchema = mapOf("statement" to "string"),
                                    subRounds = 3,
                                ),
                            ),
                            elsePhases = listOf(Phase(type = PhaseType.SUMMARIZE, template = "s")),
                        ),
                    ),
                ),
            ),
        )
    }
}
