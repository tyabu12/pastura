package com.pastura.engine

import com.pastura.models.ConversationEntry
import com.pastura.models.Pairing
import com.pastura.models.Persona
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Kotlin port of `Pastura/PasturaTests/Engine/Phases/SummarizeHandlerTests.swift`.
 *
 * `summarize` is an emit-only code phase: it formats round-summary text and emits
 * one [SimulationEvent.Summary], never mutating state. Two expansion paths — a
 * per-pairing loop (pairings present AND the template carries `{agent1}`) and a
 * simple single expansion — are pinned here, along with the ADR-010 Step E
 * `simulation_language` override on the default template.
 *
 * Because [SummarizeHandler] never touches state, the tests read only the emitted
 * summaries; the "no mutation" contract is implicit in there being nothing to
 * assert on the returned state.
 *
 * Ported for the ADR-023 Stage-3 code-phase port (#501).
 */
class SummarizeHandlerTests {

    private val handler = SummarizeHandler()

    private fun scenario(
        template: String? = null,
        language: String = "en",
        simulationLanguage: String? = null,
        agents: List<String> = listOf("Alice", "Bob"),
    ) = Scenario(
        id = "t",
        name = "T",
        description = "d",
        language = language,
        simulationLanguage = simulationLanguage,
        agentCount = agents.size,
        rounds = 2,
        context = "A test.",
        personas = agents.map { Persona(name = it, description = "$it's persona.") },
        phases = listOf(Phase(type = PhaseType.SUMMARIZE, template = template)),
    )

    private fun context(
        scenario: Scenario,
        events: MutableList<SimulationEvent> = mutableListOf(),
    ) = PhaseContext(
        scenario = scenario,
        phase = scenario.phases[0],
        backend = ScriptedLLMBackend(emptyList()),
        suspensionRelay = SuspensionRelay(),
        emitter = { events += it },
        pauseCheck = { },
        phasePath = listOf(0),
        turnGate = TurnFailureGate(),
    )

    private fun List<SimulationEvent>.summaries(): List<String> =
        filterIsInstance<SimulationEvent.Summary>().map { it.text }

    @Test
    fun expandsTemplateWithVariables() = runTest {
        val s = scenario(template = "Round {current_round} done")
        val events = mutableListOf<SimulationEvent>()
        val state = SimulationState.initial(s).copy(currentRound = 3)
        handler.execute(context(s, events), state)

        val summaries = events.summaries()
        assertEquals(1, summaries.size)
        assertEquals("Round 3 done", summaries[0])
    }

    @Test
    fun expandsPairingTemplate() = runTest {
        val s = scenario(template = "{agent1}({action1}) vs {agent2}({action2})")
        val events = mutableListOf<SimulationEvent>()
        val state = SimulationState.initial(s).copy(
            currentRound = 1,
            pairings = listOf(
                Pairing(agent1 = "Alice", agent2 = "Bob", action1 = "cooperate", action2 = "betray"),
            ),
        )
        handler.execute(context(s, events), state)

        val summaries = events.summaries()
        assertEquals(1, summaries.size)
        assertEquals("Alice(cooperate) vs Bob(betray)", summaries[0])
    }

    @Test
    fun emitsSummaryEvent() = runTest {
        val s = scenario(template = null)
        val events = mutableListOf<SimulationEvent>()
        val state = SimulationState.initial(s).copy(currentRound = 1)
        handler.execute(context(s, events), state)

        assertEquals(1, events.summaries().size)
    }

    // MARK: - Simple path: derived variables

    @Test
    fun expandsScoreboardInSimplePath() = runTest {
        val s = scenario(template = "Score: {scoreboard}")
        val events = mutableListOf<SimulationEvent>()
        val state = SimulationState.initial(s).copy(
            currentRound = 1,
            scores = mapOf("Alice" to 2, "Bob" to 1),
        )
        handler.execute(context(s, events), state)

        val summaries = events.summaries()
        assertEquals(1, summaries.size)
        assertEquals("""Score: {"Alice": 2, "Bob": 1}""", summaries[0])
    }

    @Test
    fun expandsVoteResultsInSimplePath() = runTest {
        val s = scenario(template = "Votes: {vote_results}")
        val events = mutableListOf<SimulationEvent>()
        val state = SimulationState.initial(s).copy(
            currentRound = 1,
            variables = mapOf("vote_results" to """{"Alice": 2}"""),
        )
        handler.execute(context(s, events), state)

        val summaries = events.summaries()
        assertEquals(1, summaries.size)
        assertEquals("""Votes: {"Alice": 2}""", summaries[0])
    }

    @Test
    fun leavesVoteResultsLiteralWhenUnset() = runTest {
        // Documents current behavior: when a preceding vote phase has not populated
        // state.variables["vote_results"], the placeholder remains literal.
        val s = scenario(template = "Votes: {vote_results}")
        val events = mutableListOf<SimulationEvent>()
        val state = SimulationState.initial(s).copy(currentRound = 1)
        handler.execute(context(s, events), state)

        val summaries = events.summaries()
        assertEquals(1, summaries.size)
        assertEquals("Votes: {vote_results}", summaries[0])
    }

    @Test
    fun expandsConversationLogInSimplePath() = runTest {
        val s = scenario(template = "Log:\n{conversation_log}")
        val events = mutableListOf<SimulationEvent>()
        val state = SimulationState.initial(s).copy(
            currentRound = 1,
            conversationLog = listOf(
                ConversationEntry(agentName = "Alice", content = "hello", phaseType = PhaseType.SPEAK_EACH, round = 1),
            ),
        )
        handler.execute(context(s, events), state)

        val summaries = events.summaries()
        assertEquals(1, summaries.size)
        // formatConversationLog renders "  agentName: content"; the placeholder must
        // not survive literally (regression for #862).
        assertEquals("Log:\n  Alice: hello", summaries[0])
    }

    // MARK: - Pair path: derived variables

    @Test
    fun expandsScoreboardInPairPath() = runTest {
        val s = scenario(template = "{agent1} vs {agent2} | board: {scoreboard}")
        val events = mutableListOf<SimulationEvent>()
        val state = SimulationState.initial(s).copy(
            currentRound = 1,
            scores = mapOf("Alice" to 3, "Bob" to 0),
            pairings = listOf(
                Pairing(agent1 = "Alice", agent2 = "Bob", action1 = "cooperate", action2 = "betray"),
            ),
        )
        handler.execute(context(s, events), state)

        val summaries = events.summaries()
        assertEquals(1, summaries.size)
        assertEquals("""Alice vs Bob | board: {"Alice": 3, "Bob": 0}""", summaries[0])
    }

    @Test
    fun pairingVarsTakePrecedenceOverStateVariables() = runTest {
        // Pair-specific vars (agent1, action1, score1, …) must not be overridden by
        // user-defined state.variables of the same name.
        val s = scenario(template = "{agent1}({action1})")
        val events = mutableListOf<SimulationEvent>()
        val state = SimulationState.initial(s).copy(
            currentRound = 1,
            variables = mapOf("agent1" to "HIJACKED", "action1" to "HIJACKED"),
            pairings = listOf(
                Pairing(agent1 = "Alice", agent2 = "Bob", action1 = "cooperate", action2 = "betray"),
            ),
        )
        handler.execute(context(s, events), state)

        val summaries = events.summaries()
        assertEquals(1, summaries.size)
        assertEquals("Alice(cooperate)", summaries[0])
    }

    @Test
    fun expandsConversationLogInPairPath() = runTest {
        // Template carries both {agent1} and {conversation_log} with non-empty
        // pairings so the gate routes into the per-pairing loop path (#862).
        val s = scenario(template = "{agent1} log:\n{conversation_log}")
        val events = mutableListOf<SimulationEvent>()
        val state = SimulationState.initial(s).copy(
            currentRound = 1,
            pairings = listOf(
                Pairing(agent1 = "Alice", agent2 = "Bob", action1 = "cooperate", action2 = "betray"),
            ),
            conversationLog = listOf(
                ConversationEntry(agentName = "Bob", content = "hi", phaseType = PhaseType.SPEAK_EACH, round = 1),
            ),
        )
        handler.execute(context(s, events), state)

        val summaries = events.summaries()
        assertEquals(1, summaries.size)
        assertEquals("Alice log:\n  Bob: hi", summaries[0])
    }

    // MARK: - simulationLanguage override (ADR-010 Step E)

    @Test
    fun summarizeHonorsSimulationLanguageOverrideJaToEn() = runTest {
        // Scenario: ja authoring, en simulation override. template=null forces
        // fallback. After {current_round} expansion, the summary must contain the
        // English fallback.
        val s = scenario(template = null, language = "ja", simulationLanguage = "en")
        val events = mutableListOf<SimulationEvent>()
        val state = SimulationState.initial(s).copy(currentRound = 2)
        handler.execute(context(s, events), state)

        val summaries = events.summaries()
        assertEquals(1, summaries.size)
        assertTrue(summaries[0].contains("Round"))
        assertTrue(!summaries[0].contains("ラウンド"))
    }

    @Test
    fun summarizeHonorsSimulationLanguageOverrideEnToJa() = runTest {
        // Reverse: en authoring, ja simulation override. Summary must contain Japanese.
        val s = scenario(template = null, language = "en", simulationLanguage = "ja")
        val events = mutableListOf<SimulationEvent>()
        val state = SimulationState.initial(s).copy(currentRound = 2)
        handler.execute(context(s, events), state)

        val summaries = events.summaries()
        assertEquals(1, summaries.size)
        assertTrue(summaries[0].contains("ラウンド"))
        assertTrue(!summaries[0].contains("Round"))
    }
}
