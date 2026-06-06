package com.pastura.models

import kotlinx.serialization.json.JsonElement
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Pattern 2 — serialize-then-parse self-equivalence (Issue #220 W4 PR-C).
 *
 * Proves `snakeyaml-engine-kmp` faithfully re-ingests the compact JSON that
 * `kotlinx.serialization` emits. Since JSON is a strict subset of YAML 1.2,
 * `YamlCodec.decode(ScenarioCodec.encodeToString(s))` must canonicalize to the
 * same tree as `ScenarioCodec.encodeToJsonElement(s)`.
 *
 * **Distinct code path from [YamlCodecSmokeTests].** Those tests parse
 * *authored* block-style YAML (`key:\n  - item`). This test feeds snakeyaml
 * kotlinx's *flow-style* JSON syntax (`{"key":["item"]}`) — a different branch
 * of snakeyaml's scanner that authored Pastura presets never reach.
 *
 * **Relationship to Pattern 1** ([YamlFidelityEquivalenceTests], jvmTest):
 * Pattern 1 validates the authored-YAML axis cross-language against Swift Yams;
 * Pattern 2 validates the JSON-subset axis self-referentially (no Swift side
 * needed). Together they close the YAML validation surface for the spike.
 *
 * **Single in-memory fixture by design.** The job is "snakeyaml can re-ingest
 * our emitted JSON shape" — one non-trivial `Scenario` (nested personas,
 * multi-key `outputSchema`, array `extraData`, special characters) discharges
 * it; per-preset breadth is Pattern 1's job.
 */
class SerializeThenParseTests {

    private fun buildScenario() = Scenario(
        id = "serialize-then-parse-001",
        name = "Flow-style fixture",
        description = "Exercises nested objects and arrays through snakeyaml's JSON path.",
        language = "en",
        agentCount = 2,
        rounds = 2,
        // Special characters that JSON escapes (`"` / `\`) and a non-ASCII run,
        // to confirm snakeyaml re-reads kotlinx's escaped flow-style strings.
        context = "Quote \"x\", backslash \\, slash /, 日本語.",
        personas = listOf(
            Persona(name = "Alice", description = "Bold cooperator."),
            Persona(name = "Bob", description = "Cautious defector."),
        ),
        phases = listOf(
            Phase(
                type = PhaseType.SPEAK_ALL,
                prompt = "Say something.",
                outputSchema = mapOf("statement" to "string", "inner_thought" to "string"),
            ),
        ),
        extraData = mapOf(
            "topics" to AnyCodableValue.ArrayValue(listOf("cats", "dogs")),
        ),
    )

    @Test
    fun compactJsonReparsesToEquivalentTree() {
        val scenario = buildScenario()
        val direct: JsonElement = ScenarioCodec.encodeToJsonElement(scenario)
        val viaYaml: JsonElement = YamlCodec.default().decode(ScenarioCodec.encodeToString(scenario))
        assertEquals(
            Canonicalizer.canonicalize(direct),
            Canonicalizer.canonicalize(viaYaml),
            "snakeyaml-engine-kmp must re-ingest kotlinx compact JSON to the same canonical tree",
        )
    }
}
