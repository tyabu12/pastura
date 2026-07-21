package com.pastura.models

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
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
            SimulationError.TurnFailureLimitReached(consecutiveCount = 3),
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

    // ── Turn degradation + shared/narration/relationship (PR0-b) ────────

    @Test
    fun degradationAndRoundLevelEventsRoundtrip() {
        assertRoundtripAndDiscriminator(
            SimulationEvent.SharedAssignment(value = "お題: 動物"),
            "sharedAssignment",
        )
        assertRoundtripAndDiscriminator(
            SimulationEvent.Narration(text = "And with that, Alice pulls ahead."),
            "narration",
        )
        // Nested map payload — the fattest of the five new cases.
        assertRoundtripAndDiscriminator(
            SimulationEvent.RelationshipUpdate(
                relationships = mapOf("Alice" to mapOf("Bob" to -1, "Carol" to 2)),
            ),
            "relationshipUpdate",
        )
        assertRoundtripAndDiscriminator(
            SimulationEvent.TurnSkipped(
                agent = "Bob",
                phaseType = PhaseType.SPEAK_ALL,
                cause = "connection refused",
            ),
            "turnSkipped",
        )
        assertRoundtripAndDiscriminator(
            SimulationEvent.ActionRejected(
                agent = "Carol",
                phaseType = PhaseType.CHOOSE,
                raw = "Betray!",
            ),
            "actionRejected",
        )
    }

    // ── Case-mirror completeness (substitute for golden JSON parity) ─────

    /**
     * The substitute parity instrument #501 mandates for [SimulationEvent],
     * which cannot take golden JSON parity: it is not `Codable` on Swift and
     * crosses the ADR-023 §5.1 boundary as an `AsyncStream` callback, never
     * JSON (PR0-b carve-out — see this file's KDoc and #501).
     *
     * Pins the Kotlin case set against [SWIFT_EVENT_CASES] (hardcoded from
     * `Pastura/Pastura/Models/SimulationEvent.swift`, 26 cases). The
     * discriminator is read from the **actual** encoded JSON, so a swapped
     * `@SerialName` reddens as well as a missing/extra case. The production
     * [SimulationEvent.isTerminal] `when` is exhaustive with no `else`, so a
     * newly-added Kotlin subclass fails to compile until handled there — the
     * compile-time canary that forces a porter to reach this test.
     *
     * Honest residual: [SWIFT_EVENT_CASES] documents the Swift target but does
     * NOT auto-detect a *future* Swift-side addition — commonMain has no
     * `sealedSubclasses` reflection, so the Swift↔Kotlin agreement is
     * hand-maintained (same posture as `SimulationEventTerminalTests`: "no gate
     * compares the two files"). A Swift change updates this set by hand.
     */
    @Test
    fun caseSetMirrorsSwift() {
        val actual = eventSamples().map(::discriminatorOf).toSet()
        assertEquals(SWIFT_EVENT_CASES, actual)
        // One sample per case, none collapsed — guards a copy-paste that drops
        // a case or duplicates a discriminator.
        assertEquals(SWIFT_EVENT_CASES.size, eventSamples().size)
        // Secondary compile-time canary co-located with the samples (no
        // `else`): adding a subclass reddens THIS file too, not only isTerminal.
        eventSamples().forEach(::assertHandledExhaustively)
    }

    private fun discriminatorOf(event: SimulationEvent): String =
        json.encodeToJsonElement(SimulationEvent.serializer(), event)
            .jsonObject["type"]!!.jsonPrimitive.content

    private fun assertHandledExhaustively(event: SimulationEvent) {
        when (event) {
            is SimulationEvent.RoundStarted -> Unit
            is SimulationEvent.RoundCompleted -> Unit
            is SimulationEvent.PhaseStarted -> Unit
            is SimulationEvent.PhaseCompleted -> Unit
            is SimulationEvent.AgentOutput -> Unit
            is SimulationEvent.AgentOutputStream -> Unit
            is SimulationEvent.ScoreUpdate -> Unit
            is SimulationEvent.Elimination -> Unit
            is SimulationEvent.Assignment -> Unit
            is SimulationEvent.SharedAssignment -> Unit
            is SimulationEvent.Summary -> Unit
            is SimulationEvent.Narration -> Unit
            is SimulationEvent.RelationshipUpdate -> Unit
            is SimulationEvent.VoteResults -> Unit
            is SimulationEvent.PairingResult -> Unit
            is SimulationEvent.ConditionalEvaluated -> Unit
            is SimulationEvent.EventInjected -> Unit
            is SimulationEvent.SimulationCompleted -> Unit
            is SimulationEvent.RoundCheckpoint -> Unit
            is SimulationEvent.SimulationPaused -> Unit
            is SimulationEvent.ErrorEvent -> Unit
            is SimulationEvent.InferenceStarted -> Unit
            is SimulationEvent.InferenceCompleted -> Unit
            is SimulationEvent.LanguageMismatch -> Unit
            is SimulationEvent.TurnSkipped -> Unit
            is SimulationEvent.ActionRejected -> Unit
        }
    }

    private fun eventSamples(): List<SimulationEvent> = listOf(
        SimulationEvent.RoundStarted(round = 1, totalRounds = 5),
        SimulationEvent.RoundCompleted(round = 1, scores = mapOf("a" to 1)),
        SimulationEvent.PhaseStarted(phaseType = PhaseType.SPEAK_ALL, phasePath = listOf(0)),
        SimulationEvent.PhaseCompleted(phaseType = PhaseType.SPEAK_ALL, phasePath = listOf(0)),
        SimulationEvent.AgentOutput(
            agent = "a",
            output = TurnOutput(fields = mapOf("statement" to "x")),
            phaseType = PhaseType.SPEAK_ALL,
        ),
        SimulationEvent.AgentOutputStream(agent = "a", primary = null, thought = null),
        SimulationEvent.ScoreUpdate(scores = mapOf("a" to 1)),
        SimulationEvent.Elimination(agent = "a", voteCount = 1),
        SimulationEvent.Assignment(agent = "a", value = "v"),
        SimulationEvent.SharedAssignment(value = "topic"),
        SimulationEvent.Summary(text = "s"),
        SimulationEvent.Narration(text = "n"),
        SimulationEvent.RelationshipUpdate(relationships = mapOf("a" to mapOf("b" to 1))),
        SimulationEvent.VoteResults(votes = mapOf("a" to "b"), tallies = mapOf("b" to 1)),
        SimulationEvent.PairingResult(agent1 = "a", action1 = "x", agent2 = "b", action2 = "y"),
        SimulationEvent.ConditionalEvaluated(condition = "c", result = true),
        SimulationEvent.EventInjected(event = null),
        SimulationEvent.SimulationCompleted,
        SimulationEvent.RoundCheckpoint(
            state = SimulationState(
                scores = emptyMap(),
                eliminated = emptyMap(),
                conversationLog = emptyList(),
                lastOutputs = emptyMap(),
                variables = emptyMap(),
                currentRound = 0,
            ),
        ),
        SimulationEvent.SimulationPaused(round = 1, phasePath = listOf(0)),
        SimulationEvent.ErrorEvent(error = SimulationError.Cancelled),
        SimulationEvent.InferenceStarted(agent = "a"),
        SimulationEvent.InferenceCompleted(agent = "a", durationSeconds = 1.0, tokenCount = null),
        SimulationEvent.LanguageMismatch(agent = "a", detected = null, expected = "ja"),
        SimulationEvent.TurnSkipped(agent = "a", phaseType = PhaseType.SPEAK_ALL, cause = "c"),
        SimulationEvent.ActionRejected(agent = "a", phaseType = PhaseType.CHOOSE, raw = "r"),
    )

    private companion object {
        /**
         * The 26 `SimulationEvent` cases on the Swift side, by wire
         * discriminator (Swift case name). Kept in sync with
         * `Pastura/Pastura/Models/SimulationEvent.swift` by hand — see
         * [caseSetMirrorsSwift]'s residual note.
         */
        val SWIFT_EVENT_CASES: Set<String> = setOf(
            "roundStarted", "roundCompleted", "phaseStarted", "phaseCompleted",
            "agentOutput", "agentOutputStream", "scoreUpdate", "elimination",
            "assignment", "sharedAssignment", "summary", "narration",
            "relationshipUpdate", "voteResults", "pairingResult", "conditionalEvaluated",
            "eventInjected", "simulationCompleted", "roundCheckpoint", "simulationPaused",
            "error", "inferenceStarted", "inferenceCompleted", "languageMismatch",
            "turnSkipped", "actionRejected",
        )
    }
}
