package com.pastura.models

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Roundtrip + factory tests for [SimulationState].
 *
 * Validates kotlinx.serialization roundtrip with cross-group payloads
 * (TurnOutput from G0b, Pairing from W1, ConversationEntry from G0b) plus
 * the `SimulationState.initial(scenario:)` factory.
 *
 * **Scope:** Kotlin-side only — Swift↔Kotlin H2 wire-shape equivalence is
 * PR-B's canonicalizer responsibility.
 */
class SimulationStateSerializationTests {

    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun emptyStateRoundtrip() {
        val original = SimulationState()
        val encoded = json.encodeToString(original)
        val decoded = json.decodeFromString<SimulationState>(encoded)
        assertEquals(original, decoded)
        assertEquals(0, decoded.currentRound)
        assertTrue(decoded.scores.isEmpty())
        assertTrue(decoded.conversationLog.isEmpty())
    }

    @Test
    fun fullyPopulatedStateRoundtripWithCrossGroupPayloads() {
        // Exercise every cross-group reference: TurnOutput (G0b), Pairing
        // (W1), ConversationEntry (G0b). If any sub-port broke serialization,
        // this round-trip catches it.
        val original = SimulationState(
            scores = mapOf("Alice" to 3, "Bob" to 5),
            eliminated = mapOf("Alice" to false, "Bob" to false, "Carol" to true),
            conversationLog = listOf(
                ConversationEntry(
                    agentName = "Alice",
                    content = "Hello.",
                    phaseType = PhaseType.SPEAK_ALL,
                    round = 1,
                ),
                ConversationEntry(
                    agentName = "Bob",
                    content = "→ Alice (suspicious)",
                    phaseType = PhaseType.VOTE,
                    round = 1,
                ),
            ),
            lastOutputs = mapOf(
                "Alice" to TurnOutput(fields = mapOf("statement" to "Hello.")),
                "Bob" to TurnOutput(fields = mapOf("vote" to "Alice", "reason" to "suspicious")),
            ),
            voteResults = mapOf("Alice" to 1),
            pairings = listOf(
                Pairing(agent1 = "Alice", agent2 = "Bob", action1 = "cooperate", action2 = "betray"),
            ),
            variables = mapOf("current_event" to "earthquake"),
            currentRound = 2,
        )
        val encoded = json.encodeToString(original)
        val decoded = json.decodeFromString<SimulationState>(encoded)
        assertEquals(original, decoded)
        // Spot-check cross-group values survived roundtrip.
        assertEquals("Hello.", decoded.lastOutputs["Alice"]?.statement)
        assertEquals("Alice", decoded.lastOutputs["Bob"]?.vote)
        assertEquals(PhaseType.VOTE, decoded.conversationLog[1].phaseType)
        assertEquals("cooperate", decoded.pairings[0].action1)
    }

    @Test
    fun initialFactoryProducesZeroScoresAndUneliminated() {
        val scenario = Scenario(
            id = "test",
            name = "Test",
            description = "Test scenario for initial state.",
            language = "en",
            agentCount = 3,
            rounds = 1,
            context = "context",
            personas = listOf(
                Persona(name = "Alice", description = ""),
                Persona(name = "Bob", description = ""),
                Persona(name = "Carol", description = ""),
            ),
            phases = listOf(Phase(type = PhaseType.SPEAK_ALL, prompt = "Speak.")),
        )
        val initial = SimulationState.initial(scenario)
        assertEquals(mapOf("Alice" to 0, "Bob" to 0, "Carol" to 0), initial.scores)
        assertEquals(
            mapOf("Alice" to false, "Bob" to false, "Carol" to false),
            initial.eliminated,
        )
        assertTrue(initial.conversationLog.isEmpty())
        assertTrue(initial.lastOutputs.isEmpty())
        assertTrue(initial.pairings.isEmpty())
        assertEquals(0, initial.currentRound)
    }
}
