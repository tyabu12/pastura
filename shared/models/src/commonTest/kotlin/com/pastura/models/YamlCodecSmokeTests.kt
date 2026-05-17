package com.pastura.models

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.int
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * Smoke tests for [YamlCodec] (W2 PR-A item 10).
 *
 * Validates two PR-B-relevant contracts:
 *
 * 1. **YAML → [JsonElement] roundtrip for a real Pastura preset.** Inlines
 *    a subset of `prisoners_dilemma.yaml` (the canonical W1 preset
 *    fixture) and exercises the YAML 1.2 features Pastura presets
 *    actually use: nested maps, arrays-of-maps (personas / phases), folded
 *    scalars (`description: >`), mixed types (`agents: 5` int).
 *
 * 2. **Absent-key vs explicit-null divergence** — pre-establishes the
 *    contract PR-B's canonicalizer needs:
 *    - Absent YAML key → absent JsonObject key (NOT [JsonNull])
 *    - Explicit `key: ~` or `key: null` → [JsonNull]
 *
 *    Per Q1 (c) (canonicalizer-layer normalization), the codec itself
 *    is pass-through. PR-B handles the null-vs-omit reconciliation
 *    between Swift- and Kotlin-produced trees at comparison time.
 *
 * Full preset-fixture roundtrip across all presets is **PR-B scope** —
 * this commit's smoke test is the floor that confirms the YamlCodec
 * primitive works on a representative shape before PR-B builds on it.
 */
class YamlCodecSmokeTests {

    private val codec: YamlCodec = YamlCodec.default()

    /**
     * Subset of `Pastura/Pastura/Resources/Presets/prisoners_dilemma.yaml`
     * — exercises every YAML feature used by the real preset: top-level
     * scalars (id / language / name / agents / rounds), folded scalar
     * (`description: >`), array of maps (personas, phases), nested
     * keyed scalars (phase.output).
     *
     * Full-file roundtrip across all 6 presets is PR-B's harness work;
     * this canary asserts the codec primitive handles the shape Pastura
     * actually uses.
     */
    private val prisonersYaml: String = """
        id: prisoners_dilemma
        language: ja
        name: 囚人のジレンマ
        description: >
          5人のプレイヤーが「協力」か「裏切り」を選ぶ戦略ゲーム。
        agents: 5
        rounds: 3
        context: short context
        personas:
          - name: アキラ
            description: 冷静な戦略家
          - name: ミサキ
            description: お人好しの楽観主義者
        phases:
          - type: speak_all
            prompt: 全員に向けて宣言してください。
            output:
              statement: string
              inner_thought: string
          - type: choose
            options:
              - cooperate
              - betray
            pairing: round_robin
          - type: score_calc
            logic: prisoners_dilemma
    """.trimIndent()

    @Test
    fun prisonersDilemmaSubsetDecodesToExpectedShape() {
        val tree = codec.decode(prisonersYaml)
        val obj = assertIs<JsonObject>(tree, "Top-level YAML must decode to JsonObject")

        // Top-level scalars
        assertEquals("prisoners_dilemma", (obj["id"] as? JsonPrimitive)?.contentOrNull)
        assertEquals("ja", (obj["language"] as? JsonPrimitive)?.contentOrNull)
        assertEquals("囚人のジレンマ", (obj["name"] as? JsonPrimitive)?.contentOrNull)
        assertEquals(5, (obj["agents"] as? JsonPrimitive)?.int)
        assertEquals(3, (obj["rounds"] as? JsonPrimitive)?.int)

        // Folded scalar — newline collapsed to single space per YAML 1.2.
        val desc = (obj["description"] as? JsonPrimitive)?.contentOrNull
        assertTrue(
            desc != null && desc.contains("5人のプレイヤー"),
            "Description folded scalar should contain '5人のプレイヤー'; got: $desc",
        )

        // Array of maps — personas
        val personas = assertIs<JsonArray>(obj["personas"])
        assertEquals(2, personas.size)
        val firstPersona = assertIs<JsonObject>(personas[0])
        assertEquals("アキラ", (firstPersona["name"] as? JsonPrimitive)?.contentOrNull)

        // Array of maps with nested maps — phases
        val phases = assertIs<JsonArray>(obj["phases"])
        assertEquals(3, phases.size)
        val speakPhase = assertIs<JsonObject>(phases[0])
        assertEquals("speak_all", (speakPhase["type"] as? JsonPrimitive)?.contentOrNull)
        val output = assertIs<JsonObject>(speakPhase["output"])
        assertEquals("string", (output["statement"] as? JsonPrimitive)?.contentOrNull)
        assertEquals("string", (output["inner_thought"] as? JsonPrimitive)?.contentOrNull)

        // Array of primitives — options
        val choosePhase = assertIs<JsonObject>(phases[1])
        val options = assertIs<JsonArray>(choosePhase["options"])
        assertEquals(2, options.size)
        assertEquals("cooperate", (options[0] as? JsonPrimitive)?.contentOrNull)
        assertEquals("betray", (options[1] as? JsonPrimitive)?.contentOrNull)
    }

    @Test
    fun absentKeyProducesAbsentJsonKey_NotJsonNull() {
        // PR-B contract: absent YAML key must NOT appear in the JsonObject.
        // (Swift's encoding-side counterpart emits `"key": null` — that
        // divergence is the canonicalizer's job to normalize.)
        val yaml = """
            present: value
        """.trimIndent()
        val tree = assertIs<JsonObject>(codec.decode(yaml))
        assertEquals(setOf("present"), tree.keys, "Absent key 'missing' must not appear")
        assertTrue(
            "missing" !in tree,
            "Expected absent key to be physically absent; got $tree",
        )
    }

    @Test
    fun explicitNullKeyProducesJsonNull() {
        // YAML allows `~` (tilde) and `null` for explicit null. Both must
        // produce JsonNull (not "null" string).
        val yamlTilde = """
            key: ~
        """.trimIndent()
        val treeTilde = assertIs<JsonObject>(codec.decode(yamlTilde))
        assertEquals(JsonNull, treeTilde["key"], "Tilde must decode as JsonNull")

        val yamlNullWord = """
            key: null
        """.trimIndent()
        val treeNull = assertIs<JsonObject>(codec.decode(yamlNullWord))
        assertEquals(JsonNull, treeNull["key"], "Word 'null' must decode as JsonNull")

        // Sanity: the string "null" inside quotes is a string scalar.
        val yamlQuoted = """
            key: "null"
        """.trimIndent()
        val treeQuoted = assertIs<JsonObject>(codec.decode(yamlQuoted))
        assertEquals(
            JsonPrimitive("null"),
            treeQuoted["key"],
            "Quoted 'null' must decode as JsonPrimitive('null') string, NOT JsonNull",
        )
    }

    @Test
    fun mixedScalarTypesPreserveKotlinPrimitives() {
        // Confirm YAML 1.2 core-schema scalar typing survives the
        // yamlValueToJson conversion: int / double / bool / string distinct.
        val yaml = """
            anInt: 42
            aDouble: 3.14
            aBool: true
            aString: hello
        """.trimIndent()
        val tree = assertIs<JsonObject>(codec.decode(yaml))
        assertEquals(42, (tree["anInt"] as JsonPrimitive).int)
        assertEquals("3.14", (tree["aDouble"] as JsonPrimitive).content)
        assertEquals(true, (tree["aBool"] as JsonPrimitive).boolean)
        assertEquals("hello", (tree["aString"] as JsonPrimitive).content)
    }

    @Test
    fun malformedYamlThrowsMalformedYamlError() {
        val invalid = "this: is: not: valid: yaml: definitely"
        try {
            codec.decode(invalid)
            fail("Expected YamlDecodeError.MalformedYaml for invalid input")
        } catch (e: YamlDecodeError.MalformedYaml) {
            assertTrue(e.reason.isNotEmpty(), "MalformedYaml.reason must be populated")
        }
    }
}
