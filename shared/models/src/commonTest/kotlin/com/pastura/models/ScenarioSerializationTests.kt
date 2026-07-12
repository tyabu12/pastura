package com.pastura.models

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Kotlin-side JSON roundtrip and behavioral tests for [Scenario] (Issue #220 W2 Group A).
 *
 * **Scope:** validates Scenario roundtrip with nested Persona + Phase + extraData,
 * the [Scenario.engineLanguage] resolver logic, and [Scenario.ACCEPTED_LANGUAGES].
 * Does NOT validate Swift↔Kotlin H2 wire-shape equivalence (deferred to W2/W3).
 */
class ScenarioSerializationTests {

    private val json = Json { ignoreUnknownKeys = true }

    private fun buildScenario(
        simulationLanguage: String? = null,
        extraData: Map<String, AnyCodableValue> = emptyMap(),
    ) = Scenario(
        id = "test-scenario-001",
        name = "Test Scenario",
        description = "A scenario for testing serialization.",
        language = "en",
        simulationLanguage = simulationLanguage,
        agentCount = 2,
        rounds = 3,
        context = "You are participating in a test.",
        personas = listOf(
            Persona(name = "Alice", description = "Bold cooperator."),
            Persona(name = "Bob", description = "Cautious defector."),
        ),
        phases = listOf(
            Phase(
                type = PhaseType.SPEAK_ALL,
                prompt = "Say something.",
                outputSchema = mapOf("statement" to "string"),
            ),
        ),
        extraData = extraData,
    )

    @Test
    fun topLevelRoundtripWithPersonaPhaseAndExtraData() {
        val original = buildScenario(
            extraData = mapOf("topics" to AnyCodableValue.ArrayValue(listOf("cats", "dogs"))),
        )
        val encoded = json.encodeToString(original)
        val decoded = json.decodeFromString<Scenario>(encoded)
        assertEquals(original, decoded)
        assertEquals(2, decoded.personas.size)
        assertEquals("Alice", decoded.personas[0].name)
        assertEquals(1, decoded.phases.size)
        assertEquals(PhaseType.SPEAK_ALL, decoded.phases[0].type)
        val topics = decoded.extraData["topics"] as? AnyCodableValue.ArrayValue
        assertEquals(listOf("cats", "dogs"), topics?.value)
    }

    @Test
    fun engineLanguageFallsBackToLanguageWhenSimulationLanguageIsNull() {
        val scenario = buildScenario(simulationLanguage = null)
        assertNull(scenario.simulationLanguage)
        assertEquals("en", scenario.engineLanguage)
    }

    @Test
    fun engineLanguageReturnsSimulationLanguageWhenSet() {
        val scenario = buildScenario(simulationLanguage = "ja")
        assertEquals("ja", scenario.simulationLanguage)
        assertEquals("ja", scenario.engineLanguage)
    }

    @Test
    fun acceptedLanguagesContainsJaAndEn() {
        assertTrue("ja" in Scenario.ACCEPTED_LANGUAGES)
        assertTrue("en" in Scenario.ACCEPTED_LANGUAGES)
        assertEquals(2, Scenario.ACCEPTED_LANGUAGES.size)
    }

    @Test
    fun extraDataWithAnyCodableValueVariantsRoundtrips() {
        // Verify all AnyCodableValue variants in extraData survive a Scenario roundtrip.
        val original = buildScenario(
            extraData = mapOf(
                "label" to AnyCodableValue.StringValue("hello"),
                "tags" to AnyCodableValue.ArrayValue(listOf("x", "y")),
                "meta" to AnyCodableValue.DictionaryValue(mapOf("key" to "value")),
                "pairs" to AnyCodableValue.ArrayOfDictionariesValue(
                    listOf(mapOf("majority" to "apple", "minority" to "orange")),
                ),
            ),
        )
        val encoded = json.encodeToString(original)
        val decoded = json.decodeFromString<Scenario>(encoded)
        assertEquals(original.extraData, decoded.extraData)
        assertEquals(AnyCodableValue.StringValue("hello"), decoded.extraData["label"])
        assertEquals(AnyCodableValue.ArrayValue(listOf("x", "y")), decoded.extraData["tags"])
        assertEquals(AnyCodableValue.DictionaryValue(mapOf("key" to "value")), decoded.extraData["meta"])
        assertEquals(
            AnyCodableValue.ArrayOfDictionariesValue(
                listOf(mapOf("majority" to "apple", "minority" to "orange")),
            ),
            decoded.extraData["pairs"],
        )
    }
}
