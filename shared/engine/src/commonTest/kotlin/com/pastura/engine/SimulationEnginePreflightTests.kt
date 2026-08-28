package com.pastura.engine

import com.pastura.models.Persona
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import com.pastura.models.SimulationError
import com.pastura.models.SimulationEvent
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertTrue

/**
 * The ADR-024 run gate wired into [SimulationEngine.run] (D3, #1591).
 *
 * 1:1 twins of the Swift gate tests in
 * `Pastura/PasturaTests/Engine/SimulationRunnerTests.swift` —
 * `emitsValidationError`, `lintErrorBlocksRunBeforeAnyRound` and
 * `lintWarningSurfacesSummaryBeforeRounds` — plus the validator-warning case
 * ([highInferenceCountWarningSurfacesSummaryBeforeRounds]), whose Swift twin
 * lands alongside this PR.
 *
 * Real threads rather than `runTest`, for the reason [SimulationEngineTests]'
 * KDoc records: [SimulationEngine.run] owns its own `Dispatchers.Default`
 * scope, so a virtual scheduler would measure the scheduler and not the engine.
 *
 * ## ADR-023 §12 condition-4 perturbation record
 *
 * Each mutation was applied to the production code, the suite re-run, and the
 * mutation reverted. "Reddened" names the test that failed.
 *
 * | # | Mutation of `SimulationPreflight.kt` / `SimulationEngine.kt` | Reddened |
 * |---|---|---|
 * | 1 | Drop the `LintSeverity.ERROR` filter in `semanticLintGate` — emit every finding as a `⚠️` `Summary` and return `true` | [lintErrorBlocksRunBeforeAnyRound] |
 * | 2 | Move the `preflightGate` call *after* `RunLoop(…).execute()` in `SimulationEngine.run` | all four |
 * | 3 | Drop the early `return@launch` — emit the blocking error but run anyway | [validatorFailureBlocksRunBeforeAnyRound] only: `awaitTerminal` returns on the ErrorEvent the gate already emitted, so the *following* run's events are a race the lint case does not reliably observe. Mutation 2 is the deterministic detector for placement |
 * | 4 | Skip the validator half: `preflightGate` delegates straight to `semanticLintGate` | [validatorFailureBlocksRunBeforeAnyRound], [highInferenceCountWarningSurfacesSummaryBeforeRounds] |
 * | 5 | Drop the `"⚠️ "` prefix from both `Summary` channels | [lintWarningSurfacesSummaryBeforeRounds], [highInferenceCountWarningSurfacesSummaryBeforeRounds] |
 * | 6 | Return `true` instead of `false` after emitting the validator's `ErrorEvent` | [validatorFailureBlocksRunBeforeAnyRound] |
 *
 * Ported for the ADR-023 §6 Stage-3 Engine migration (#501, D3 / #1591).
 */
class SimulationEnginePreflightTests {

    private fun scenario(
        agents: List<String> = listOf("Alice", "Bob"),
        rounds: Int = 1,
        phases: List<Phase> = listOf(
            Phase(type = PhaseType.SPEAK_ALL, prompt = "Speak.", outputSchema = mapOf("statement" to "string")),
        ),
    ) = Scenario(
        id = "t",
        name = "T",
        description = "d",
        language = "en",
        agentCount = agents.size,
        rounds = rounds,
        context = "A test.",
        personas = agents.map { Persona(name = it, description = "$it's persona.") },
        phases = phases,
    )

    private fun says(text: String) =
        ScriptedLLMBackend.Script.completing("""{"statement": "$text"}""")

    /** Index of the first `⚠️`-prefixed [SimulationEvent.Summary], or -1. */
    private fun List<SimulationEvent>.firstWarningIndex(): Int =
        indexOfFirst { it is SimulationEvent.Summary && it.text.contains("⚠️") }

    /** Index of the first [SimulationEvent.RoundStarted], or -1. */
    private fun List<SimulationEvent>.firstRoundIndex(): Int =
        indexOfFirst { it is SimulationEvent.RoundStarted }

    // MARK: - Structural validation (ScenarioValidator)

    @Test
    fun validatorFailureBlocksRunBeforeAnyRound() = runBlockingTest {
        // Swift twin: `emitsValidationError`. 11 agents exceeds the validator's
        // 10-agent cap, so the gate blocks before the round loop. No LLM call is
        // reached, hence the empty script list.
        val s = scenario(agents = (0 until 11).map { "Agent$it" })
        val c = Collector()
        SimulationEngine().run(s, ScriptedLLMBackend(emptyList())) { c.record(it) }
        awaitTerminal(c)

        val events = c.snapshot()
        // The terminal-event contract: the LAST event is the blocking ErrorEvent.
        val error = assertIs<SimulationEvent.ErrorEvent>(events.last())
        assertIs<SimulationError.ScenarioValidationFailed>(error.error)
        assertFalse(events.any { it is SimulationEvent.RoundStarted })
        assertFalse(events.any { it is SimulationEvent.SimulationCompleted })
    }

    @Test
    fun highInferenceCountWarningSurfacesSummaryBeforeRounds() = runBlockingTest {
        // The validator's non-fatal band: 2 agents x 26 rounds x speak_all = 52
        // estimated inferences, inside `> 50` and under the `> 100` throw, and
        // off the `rounds > 30` cap so a cap change cannot flip this into a
        // validation error. The warning rides the same `⚠️` Summary channel as a lint warning, and the
        // run proceeds to completion.
        val s = scenario(rounds = 26)
        val c = Collector()
        SimulationEngine().run(s, ScriptedLLMBackend(List(52) { says("a") })) { c.record(it) }
        awaitTerminal(c)

        val events = c.snapshot()
        val warningIndex = events.firstWarningIndex()
        val roundIndex = events.firstRoundIndex()
        assertTrue(warningIndex >= 0, "expected a ⚠️ summary, got ${events.map { it::class.simpleName }}")
        assertTrue(roundIndex >= 0)
        assertTrue(warningIndex < roundIndex, "the warning must precede the first round event")
        assertIs<SimulationEvent.SimulationCompleted>(events.last())
    }

    // MARK: - Semantic lint gate (ADR-024)

    @Test
    fun lintErrorBlocksRunBeforeAnyRound() = runBlockingTest {
        // Swift twin. `eliminate` with no `vote` anywhere trips R1a (error): the
        // run must emit `ScenarioValidationFailed` and execute no rounds. The gate
        // returns before the round loop, so no LLM call is reached.
        val s = scenario(phases = listOf(Phase(type = PhaseType.ELIMINATE)))
        val c = Collector()
        SimulationEngine().run(s, ScriptedLLMBackend(emptyList())) { c.record(it) }
        awaitTerminal(c)

        val events = c.snapshot()
        val error = assertIs<SimulationEvent.ErrorEvent>(events.last())
        assertIs<SimulationError.ScenarioValidationFailed>(error.error)
        assertFalse(events.any { it is SimulationEvent.RoundStarted })
        assertFalse(events.any { it is SimulationEvent.SimulationCompleted })
    }

    @Test
    fun lintWarningSurfacesSummaryBeforeRounds() = runBlockingTest {
        // Swift twin. `choose` without `options` trips R7 (warning): the run
        // proceeds and a `Summary("⚠️ …")` precedes the first round event.
        val s = scenario(
            phases = listOf(
                Phase(type = PhaseType.CHOOSE, prompt = "Pick", outputSchema = mapOf("action" to "string")),
            ),
        )
        val c = Collector()
        val backend = ScriptedLLMBackend(
            listOf(
                ScriptedLLMBackend.Script.completing("""{"action": "left"}"""),
                ScriptedLLMBackend.Script.completing("""{"action": "right"}"""),
            ),
        )
        SimulationEngine().run(s, backend) { c.record(it) }
        awaitTerminal(c)

        val events = c.snapshot()
        val warningIndex = events.firstWarningIndex()
        val roundIndex = events.firstRoundIndex()
        assertTrue(warningIndex >= 0, "expected a ⚠️ summary, got ${events.map { it::class.simpleName }}")
        assertTrue(roundIndex >= 0)
        assertTrue(warningIndex < roundIndex, "the warning must precede the first round event")
        assertIs<SimulationEvent.SimulationCompleted>(events.last())
    }
}
