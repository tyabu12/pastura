package com.pastura.engine

import com.pastura.models.Pairing
import com.pastura.models.PayoffRule
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import com.pastura.models.ScoreCalcLogic
import com.pastura.models.SimulationError
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState
import com.pastura.models.TurnOutput
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertTrue

/**
 * Dispatch-parity tests for [ScoreCalcHandler].
 *
 * There is no dedicated Swift `ScoreCalcHandlerTests` — the handler is a thin
 * dispatcher and the five scoring logics are covered by their own
 * `*LogicTests` suites under `ScoringLogic/`. This suite proves only the
 * **routing contract**:
 * that each [ScoreCalcLogic] reaches its implementation with the correct
 * arguments, asserted via one distinguishing observable per logic (not by
 * re-testing each logic's internals). The `logic == null` case pins the
 * missing-field throw.
 *
 * Because Kotlin [SimulationState] is immutable, every assertion reads the
 * **returned** state (or an emitted [SimulationEvent]) — a handler that dropped
 * the dispatched logic's return value would compile cleanly and silently score
 * nothing.
 *
 * Ported for the ADR-023 Stage-3 CP2 score_calc slice (#501).
 */
class ScoreCalcHandlerTests {

    private val handler = ScoreCalcHandler()

    private fun scenario(
        agents: List<String> = listOf("Alice", "Bob"),
        language: String? = null,
    ): Scenario {
        val base = makeTestScenario(agentNames = agents)
        return if (language == null) base else base.copy(simulationLanguage = language)
    }

    private fun context(
        scenario: Scenario,
        logic: ScoreCalcLogic?,
        payoff: List<PayoffRule>? = null,
        events: MutableList<SimulationEvent> = mutableListOf(),
    ) = PhaseContext(
        scenario = scenario,
        phase = Phase(type = PhaseType.SCORE_CALC, logic = logic, payoff = payoff),
        backend = ScriptedLLMBackend(emptyList()),
        suspensionRelay = SuspensionRelay(),
        emitter = { events += it },
        pauseCheck = { },
        phasePath = listOf(0),
        turnGate = TurnFailureGate(),
    )

    @Test
    fun missingLogicThrowsScenarioValidationFailed() = runTest {
        val s = scenario()
        val error = assertFailsWith<SimulationException> {
            handler.execute(context(s, logic = null), SimulationState.initial(s))
        }
        val message = assertIs<SimulationError.ScenarioValidationFailed>(error.error).message
        assertTrue(message.contains("logic"), "expected the missing-field message to name 'logic': $message")
    }

    @Test
    fun routesVoteTally() = runTest {
        // Distinguishing observable: vote_tally adds voteResults into scores.
        val s = scenario()
        val state = SimulationState.initial(s).copy(voteResults = mapOf("Alice" to 2, "Bob" to 1))
        val next = handler.execute(context(s, ScoreCalcLogic.VOTE_TALLY), state)
        assertEquals(2, next.scores["Alice"])
        assertEquals(1, next.scores["Bob"])
    }

    @Test
    fun routesEventReactiveWithTheEventInjectCompanionKey() = runTest {
        // Distinguishing observable: event_reactive rewards agents whose last
        // action matched the favored value. The reward proves the handler passed
        // the `current_event__favors` companion key (EventInjectHandler's default
        // variable) — a wrong key would leave every score at 0.
        val s = scenario()
        val favoredKey = EventInjectHandler.favoredVariableName(EventInjectHandler.defaultVariableName)
        assertEquals("current_event__favors", favoredKey)
        val state = SimulationState.initial(s).copy(
            lastOutputs = mapOf(
                "Alice" to TurnOutput(fields = mapOf("action" to "betray")),
                "Bob" to TurnOutput(fields = mapOf("action" to "cooperate")),
            ),
            variables = mapOf(favoredKey to "betray"),
        )
        val next = handler.execute(context(s, ScoreCalcLogic.EVENT_REACTIVE), state)
        assertEquals(EventReactivePayoffLogic.matchReward, next.scores["Alice"])
        assertEquals(0, next.scores["Bob"])
    }

    @Test
    fun routesPairwisePayoffWithThePhasePayoffTable() = runTest {
        // Distinguishing observable: pairwise_payoff applies the phase's payoff
        // row positionally to a pairing.
        val s = scenario()
        val table = listOf(PayoffRule(`when` = listOf("cooperate", "betray"), points = listOf(0, 5)))
        val state = SimulationState.initial(s).copy(
            pairings = listOf(Pairing(agent1 = "Alice", agent2 = "Bob", action1 = "cooperate", action2 = "betray")),
        )
        val next = handler.execute(context(s, ScoreCalcLogic.PAIRWISE_PAYOFF, payoff = table), state)
        assertEquals(0, next.scores["Alice"])
        assertEquals(5, next.scores["Bob"])
        assertTrue(next.pairings.isEmpty(), "pairwise_payoff clears pairings after scoring")
    }

    @Test
    fun routesPrisonersDilemmaLegacyMatrix() = runTest {
        // Distinguishing observable: prisoners_dilemma applies the fixed 3/0/5/1
        // legacy matrix with NO phase payoff table supplied.
        val s = scenario()
        val state = SimulationState.initial(s).copy(
            pairings = listOf(Pairing(agent1 = "Alice", agent2 = "Bob", action1 = "betray", action2 = "cooperate")),
        )
        val next = handler.execute(context(s, ScoreCalcLogic.PRISONERS_DILEMMA), state)
        assertEquals(5, next.scores["Alice"])
        assertEquals(0, next.scores["Bob"])
    }

    @Test
    fun routesWordwolfJudgeWithTheScenarioEngineLanguage() = runTest {
        // Distinguishing observable: wordwolf_judge emits a language-specific
        // Summary. Using a ja scenario proves the handler passed
        // `scenario.engineLanguage` (a wrong language would emit the en text).
        val s = scenario(language = "ja")
        assertEquals("ja", s.engineLanguage)
        val events = mutableListOf<SimulationEvent>()
        val state = SimulationState.initial(s).copy(
            voteResults = mapOf("Alice" to 2, "Bob" to 1),
            variables = mapOf("wolf_name" to "Alice"),
        )
        handler.execute(context(s, ScoreCalcLogic.WORDWOLF_JUDGE, events = events), state)
        val summaries = events.filterIsInstance<SimulationEvent.Summary>()
        assertEquals(1, summaries.size)
        assertTrue(summaries[0].text.contains("最多得票"), "expected ja wordwolf text, got: ${summaries[0].text}")
        assertTrue(summaries[0].text.contains("ウルフ"), "expected ja wordwolf verdict, got: ${summaries[0].text}")
    }
}
