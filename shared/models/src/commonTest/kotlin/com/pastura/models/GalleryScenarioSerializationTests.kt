package com.pastura.models

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Roundtrip + wire-shape tests for [GalleryScenario], [GalleryIndex], and [GalleryCategory].
 *
 * Unlike [Phase] / [Scenario] (which use camelCase wire keys), these types
 * use **snake_case wire keys** by design — Swift's explicit `CodingKeys`
 * pin the contract for `gallery.json` (remote-fetched). Tests confirm
 * Kotlin's `@SerialName` overrides produce the same snake_case shape.
 */
class GalleryScenarioSerializationTests {

    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun galleryCategoryRawValueWireShape() {
        val expectations = mapOf(
            GalleryCategory.SOCIAL_PSYCHOLOGY to "\"social_psychology\"",
            GalleryCategory.GAME_THEORY to "\"game_theory\"",
            GalleryCategory.ETHICS to "\"ethics\"",
            GalleryCategory.ROLEPLAY to "\"roleplay\"",
            GalleryCategory.CREATIVE to "\"creative\"",
            GalleryCategory.EXPERIMENTAL to "\"experimental\"",
        )
        expectations.forEach { (case, expectedJson) ->
            assertEquals(expectedJson, Json.encodeToString(case), "Wire mismatch for $case")
        }
    }

    @Test
    fun galleryCategoryRoundtripPreservesEquality() {
        GalleryCategory.entries.forEach { original ->
            val decoded = Json.decodeFromString<GalleryCategory>(Json.encodeToString(original))
            assertEquals(original, decoded)
        }
    }

    @Test
    fun galleryScenarioRoundtripPreservesAllFields() {
        val original = GalleryScenario(
            id = "asch_conformity_v1",
            title = "Asch Conformity",
            category = GalleryCategory.SOCIAL_PSYCHOLOGY,
            description = "Test of conformity under group pressure.",
            author = "tyabu12",
            recommendedModel = "gemma_4_e2b",
            estimatedInferences = 24,
            yamlURL = "https://example.com/asch_conformity.yaml",
            yamlSHA256 = "a1b2c3d4e5f60718192a3b4c5d6e7f8091a2b3c4d5e6f70819293a4b5c6d7e8f",
            addedAt = "2026-04-14",
        )
        val encoded = json.encodeToString(original)
        val decoded = json.decodeFromString<GalleryScenario>(encoded)
        assertEquals(original, decoded)
    }

    @Test
    fun galleryScenarioEmitsSnakeCaseWireKeys() {
        // CRITICAL — snake_case wire is the contract for gallery.json,
        // documented in Swift's explicit CodingKeys.
        val scenario = GalleryScenario(
            id = "test",
            title = "Test",
            category = GalleryCategory.GAME_THEORY,
            description = "x",
            author = "x",
            recommendedModel = "x",
            estimatedInferences = 1,
            yamlURL = "https://example.com/x.yaml",
            yamlSHA256 = "0".repeat(64),
            addedAt = "2026-04-14",
        )
        val encoded = json.encodeToString(scenario)
        // All snake_case keys must be present; the camelCase counterparts must NOT.
        assertTrue(encoded.contains("\"recommended_model\""), "Expected snake_case: $encoded")
        assertTrue(encoded.contains("\"estimated_inferences\""), "Expected snake_case: $encoded")
        assertTrue(encoded.contains("\"yaml_url\""), "Expected snake_case: $encoded")
        assertTrue(encoded.contains("\"yaml_sha256\""), "Expected snake_case: $encoded")
        assertTrue(encoded.contains("\"added_at\""), "Expected snake_case: $encoded")
        // Sanity: camelCase must NOT appear (catches accidental @SerialName drop).
        assertTrue(!encoded.contains("\"recommendedModel\""), "Unexpected camelCase: $encoded")
        assertTrue(!encoded.contains("\"estimatedInferences\""), "Unexpected camelCase: $encoded")
    }

    @Test
    fun galleryIndexRoundtripWithMultipleScenarios() {
        val original = GalleryIndex(
            version = 1,
            updatedAt = "2026-04-14T12:00:00Z",
            scenarios = listOf(
                GalleryScenario(
                    id = "a",
                    title = "A",
                    category = GalleryCategory.ETHICS,
                    description = "",
                    author = "",
                    recommendedModel = "m",
                    estimatedInferences = 1,
                    yamlURL = "https://example.com/a.yaml",
                    yamlSHA256 = "0".repeat(64),
                    addedAt = "2026-01-01",
                ),
                GalleryScenario(
                    id = "b",
                    title = "B",
                    category = GalleryCategory.CREATIVE,
                    description = "",
                    author = "",
                    recommendedModel = "m",
                    estimatedInferences = 2,
                    yamlURL = "https://example.com/b.yaml",
                    yamlSHA256 = "1".repeat(64),
                    addedAt = "2026-02-01",
                ),
            ),
        )
        val encoded = json.encodeToString(original)
        val decoded = json.decodeFromString<GalleryIndex>(encoded)
        assertEquals(original, decoded)
        // Confirm the envelope's snake_case key is present.
        assertTrue(encoded.contains("\"updated_at\""), "Expected snake_case: $encoded")
    }

    @Test
    fun modelIdIsString() {
        // ModelID is `typealias ModelID = String` — confirm the alias survives
        // and is wire-compatible with a raw String at decode time.
        val modelId: ModelID = "gemma_4_e2b"
        val raw: String = modelId
        assertEquals("gemma_4_e2b", raw)
    }
}
