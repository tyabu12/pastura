package com.pastura.models

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * JSON roundtrip tests for [ConversationEntry].
 *
 * Wire shape uses camelCase key names per kotlinx.serialization default,
 * matching Swift Codable's default encoding for `struct ConversationEntry`.
 */
class ConversationEntrySerializationTests {

    @Test
    fun encodeDecodeRoundtrip() {
        val original = ConversationEntry(
            agentName = "Alice",
            content = "I think it's a word wolf game.",
            phaseType = PhaseType.SPEAK_ALL,
            round = 1,
        )
        val json = Json.encodeToString(original)
        val decoded = Json.decodeFromString<ConversationEntry>(json)
        assertEquals(original, decoded)
    }

    @Test
    fun wireShapeMatchesSwiftCodableDefault() {
        val entry = ConversationEntry(
            agentName = "Bob",
            content = "Agreed.",
            phaseType = PhaseType.SPEAK_EACH,
            round = 2,
        )
        val json = Json.encodeToString(entry)
        // camelCase keys + phaseType encoded as SerialName string
        assertTrue(json.contains("\"agentName\""), "Expected camelCase agentName; got: $json")
        assertTrue(json.contains("\"phaseType\""), "Expected camelCase phaseType; got: $json")
        assertTrue(json.contains("\"speak_each\""), "Expected speak_each wire value; got: $json")
        assertTrue(json.contains("\"round\""), "Expected round key; got: $json")
        assertTrue(json.contains("\"content\""), "Expected content key; got: $json")
    }

    @Test
    fun votePhaseRoundtrip() {
        val original = ConversationEntry(
            agentName = "Carol",
            content = "→ Alice (suspicious)",
            phaseType = PhaseType.VOTE,
            round = 3,
        )
        val json = Json.encodeToString(original)
        val decoded = Json.decodeFromString<ConversationEntry>(json)
        assertEquals(original, decoded)
    }
}
