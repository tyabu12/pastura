package com.pastura.models

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Roundtrip + discriminator wire-shape tests for [SimulationEvent].
 *
 * Validates kotlinx.serialization's default sealed-class polymorphism:
 * the wire shape carries `{"type":"<SerialName>", ...payload}`. The
 * discriminator value MUST match the Swift case name (camelCase) so a
 * future canonicalizer can align tagging across languages.
 *
 * **Scope:** Kotlin-side roundtrip only. Swift↔Kotlin H2 wire-shape
 * equivalence is PR-B's canonicalizer responsibility (deferred per the
 * intentional divergence documented in [SimulationEvent]'s kdoc).
 */
class SimulationEventSerializationTests {

    private val json = Json { ignoreUnknownKeys = true }

    private inline fun <reified T : SimulationEvent> assertRoundtripAndDiscriminator(
        original: T,
        expectedSerialName: String,
    ) {
        val encoded = json.encodeToString<SimulationEvent>(original)
        assertTrue(
            encoded.contains("\"type\":\"$expectedSerialName\""),
            "Wire shape missing discriminator '$expectedSerialName' in $encoded",
        )
        val decoded = json.decodeFromString<SimulationEvent>(encoded)
        assertEquals(original, decoded)
    }

    // ── Round lifecycle ─────────────────────────────────────────────────

    @Test
    fun roundLifecycleRoundtrip() {
        assertRoundtripAndDiscriminator(
            SimulationEvent.RoundStarted(round = 1, totalRounds = 5),
            "roundStarted",
        )
        assertRoundtripAndDiscriminator(
            SimulationEvent.RoundCompleted(
                round = 2,
                scores = mapOf("Alice" to 3, "Bob" to 1),
            ),
            "roundCompleted",
        )
    }

    // ── Phase lifecycle ─────────────────────────────────────────────────

    @Test
    fun phaseLifecycleRoundtripWithNestedPath() {
        assertRoundtripAndDiscriminator(
            SimulationEvent.PhaseStarted(
                phaseType = PhaseType.SPEAK_ALL,
                phasePath = listOf(0),
            ),
            "phaseStarted",
        )
        // Nested sub-phase path [K, N] from a conditional.
        assertRoundtripAndDiscriminator(
            SimulationEvent.PhaseCompleted(
                phaseType = PhaseType.SCORE_CALC,
                phasePath = listOf(2, 1),
            ),
            "phaseCompleted",
        )
    }

    // ── Agent outputs ───────────────────────────────────────────────────

    @Test
    fun agentOutputCarriesTurnOutputPayload() {
        val output = TurnOutput(fields = mapOf("statement" to "Hello.", "inner_thought" to "..."))
        assertRoundtripAndDiscriminator(
            SimulationEvent.AgentOutput(
                agent = "Alice",
                output = output,
                phaseType = PhaseType.SPEAK_ALL,
            ),
            "agentOutput",
        )
    }

    @Test
    fun agentOutputStreamHandlesNullablePartials() {
        // Initial snapshot before primary key opens.
        assertRoundtripAndDiscriminator(
            SimulationEvent.AgentOutputStream(
                agent = "Alice",
                primary = null,
                thought = null,
            ),
            "agentOutputStream",
        )
        // Mid-stream with partial values.
        assertRoundtripAndDiscriminator(
            SimulationEvent.AgentOutputStream(
                agent = "Bob",
                primary = "I think",
                thought = "Hmm",
            ),
            "agentOutputStream",
        )
    }

    // ── Code phase results ──────────────────────────────────────────────

    @Test
    fun codePhaseResultsRoundtrip() {
        assertRoundtripAndDiscriminator(
            SimulationEvent.ScoreUpdate(scores = mapOf("Alice" to 5, "Bob" to 2)),
            "scoreUpdate",
        )
        assertRoundtripAndDiscriminator(
            SimulationEvent.Elimination(agent = "Carol", voteCount = 3),
            "elimination",
        )
        assertRoundtripAndDiscriminator(
            SimulationEvent.Assignment(agent = "Alice", value = "りんご"),
            "assignment",
        )
        assertRoundtripAndDiscriminator(
            SimulationEvent.Summary(text = "Round 1 complete."),
            "summary",
        )
    }

    // ── Vote / Pairing ──────────────────────────────────────────────────

    @Test
    fun voteResultsRoundtrip() {
        assertRoundtripAndDiscriminator(
            SimulationEvent.VoteResults(
                votes = mapOf("Alice" to "Bob", "Bob" to "Alice"),
                tallies = mapOf("Alice" to 1, "Bob" to 1),
            ),
            "voteResults",
        )
    }

    @Test
    fun pairingResultRoundtrip() {
        assertRoundtripAndDiscriminator(
            SimulationEvent.PairingResult(
                agent1 = "Alice",
                action1 = "cooperate",
                agent2 = "Bob",
                action2 = "betray",
            ),
            "pairingResult",
        )
    }

    // ── Conditional / event injection ───────────────────────────────────

    @Test
    fun conditionalEvaluatedRoundtrip() {
        assertRoundtripAndDiscriminator(
            SimulationEvent.ConditionalEvaluated(
                condition = "score.alice > 5",
                result = true,
            ),
            "conditionalEvaluated",
        )
    }

    @Test
    fun eventInjectedHandlesHitAndMiss() {
        // Hit: an event was selected.
        assertRoundtripAndDiscriminator(
            SimulationEvent.EventInjected(event = "earthquake"),
            "eventInjected",
        )
        // Miss: rolled and lost.
        assertRoundtripAndDiscriminator(
            SimulationEvent.EventInjected(event = null),
            "eventInjected",
        )
    }

    // ── Simulation lifecycle ────────────────────────────────────────────

    @Test
    fun simulationCompletedIsUnitPayload() {
        val original: SimulationEvent = SimulationEvent.SimulationCompleted
        val encoded = json.encodeToString(original)
        // Unit case wire shape: just the discriminator key.
        assertEquals("""{"type":"simulationCompleted"}""", encoded)
        val decoded = json.decodeFromString<SimulationEvent>(encoded)
        assertEquals(original, decoded)
    }

    @Test
    fun roundCheckpointRoundtripsWithFullStatePayload() {
        // The fattest payload the §5.1 event boundary relays (ADR-023 §6
        // measurement (iii)): nested TurnOutput maps + a ConversationEntry list.
        // Built non-empty on purpose — an `initial()` state would round-trip
        // through mostly-empty collections and witness none of the nesting the
        // K/N shim budget is measured against.
        val state = SimulationState(
            scores = mapOf("Alice" to 3, "Bob" to 1),
            eliminated = mapOf("Alice" to false, "Bob" to false),
            conversationLog = listOf(
                ConversationEntry(
                    agentName = "Alice",
                    content = "I'll cooperate.",
                    phaseType = PhaseType.SPEAK_ALL,
                    round = 1,
                ),
            ),
            lastOutputs = mapOf(
                "Alice" to TurnOutput(
                    fields = mapOf("statement" to "I'll cooperate.", "inner_thought" to "Testing."),
                ),
            ),
            variables = mapOf("current_round" to "1"),
            currentRound = 1,
        )
        assertRoundtripAndDiscriminator(
            SimulationEvent.RoundCheckpoint(state = state),
            "roundCheckpoint",
        )
    }

    @Test
    fun roundCheckpointCarriesLastCompletedRound() {
        // Pins the resume contract the App layer depends on: `state.currentRound`
        // is the last *completed* round, so a paused run resumes from +1. A port
        // that emitted the checkpoint before the round completed would still pass
        // the roundtrip test above but break resume.
        val state = SimulationState.initial(
            Scenario(
                id = "t",
                name = "T",
                description = "d",
                language = "en",
                agentCount = 2,
                rounds = 5,
                context = "c",
                personas = listOf(
                    Persona(name = "Alice", description = ""),
                    Persona(name = "Bob", description = ""),
                ),
                phases = listOf(Phase(type = PhaseType.SPEAK_ALL, prompt = "Speak.")),
            ),
        ).copy(currentRound = 2)
        val decoded = json.decodeFromString<SimulationEvent>(
            json.encodeToString<SimulationEvent>(SimulationEvent.RoundCheckpoint(state = state)),
        )
        assertEquals(2, (decoded as SimulationEvent.RoundCheckpoint).state.currentRound)
    }

    @Test
    fun simulationPausedRoundtrip() {
        assertRoundtripAndDiscriminator(
            SimulationEvent.SimulationPaused(round = 2, phasePath = listOf(1)),
            "simulationPaused",
        )
    }

    // ── Error wrapping (cross-sealed-class) ─────────────────────────────

    @Test
    fun errorWrappingEachSimulationErrorCase() {
        // Confirms SimulationEvent.ErrorEvent's nested polymorphism works
        // — both the outer SimulationEvent discriminator AND the inner
        // SimulationError discriminator must roundtrip cleanly.
        val cases = listOf(
            SimulationError.ScenarioValidationFailed(message = "agentCount=2 != personas.size=3"),
            SimulationError.LlmGenerationFailed(description = "connection refused"),
            SimulationError.JsonParseFailed(raw = "{...partial"),
            SimulationError.RetriesExhausted,
            SimulationError.ModelNotLoaded,
            SimulationError.Cancelled,
        )
        for (err in cases) {
            assertRoundtripAndDiscriminator(
                SimulationEvent.ErrorEvent(error = err),
                "error",
            )
        }
    }

    // ── Inference progress ──────────────────────────────────────────────

    @Test
    fun inferenceProgressRoundtrip() {
        assertRoundtripAndDiscriminator(
            SimulationEvent.InferenceStarted(agent = "Alice"),
            "inferenceStarted",
        )
        // tokenCount = null (backend without usage metadata).
        assertRoundtripAndDiscriminator(
            SimulationEvent.InferenceCompleted(
                agent = "Alice",
                durationSeconds = 1.5,
                tokenCount = null,
            ),
            "inferenceCompleted",
        )
        // tokenCount = present.
        assertRoundtripAndDiscriminator(
            SimulationEvent.InferenceCompleted(
                agent = "Bob",
                durationSeconds = 2.25,
                tokenCount = 42,
            ),
            "inferenceCompleted",
        )
    }

    // ── Language mismatch (ADR-010 Step E PR2) ──────────────────────────

    @Test
    fun languageMismatchHandlesDetectedNullable() {
        // detected = null (output too short for confident classification).
        assertRoundtripAndDiscriminator(
            SimulationEvent.LanguageMismatch(
                agent = "Alice",
                detected = null,
                expected = "ja",
            ),
            "languageMismatch",
        )
        // detected = present.
        assertRoundtripAndDiscriminator(
            SimulationEvent.LanguageMismatch(
                agent = "Bob",
                detected = "en",
                expected = "ja",
            ),
            "languageMismatch",
        )
    }
}
