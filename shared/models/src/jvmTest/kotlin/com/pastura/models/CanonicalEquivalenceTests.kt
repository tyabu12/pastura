package com.pastura.models

import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.encodeToJsonElement
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Cross-language canonical-equivalence harness — Issue #220 W2 PR-B Stage 5.
 *
 * **This is NOT a roundtrip harness.** The pattern is
 * `Kotlin emit → canonicalize → byte-match against Swift baseline
 * (also canonicalized)`. Stage 3 of [Canonicalizer] is intentionally
 * single-direction (Kotlin polymorphic tag-form → Swift outer-wrap), so
 * the canonical form for polymorphic types is NOT a valid kotlinx
 * polymorphic-decoder input — feeding it back into
 * `Json.decodeFromString<CodePhaseEventPayload>(...)` would fail. That is
 * by design per W2 PR-B Q8 (test-side transform only; no
 * `@Serializable(with = ...)` on production sealed classes).
 *
 * Discharges the H2 hypothesis ("snake_case wire-shape equivalence is
 * achievable via per-field `@SerialName` annotations on the affected
 * types") for 8 fixtures:
 *
 * - 4 base ja preset Scenarios (camelCase Codable default wire shape)
 * - 1 GalleryIndex (snake_case via per-field `@SerialName`)
 * - 1 CodePhaseEventPayload sequence with all 7 cases including the
 *   `EventInjected(event=null)` miss case (Stage 3 lift)
 * - 2 hand-written micro-fixtures (`_micro/`) verifying Stage 1's
 *   null-omit policy (explicit `null` ≡ absent key)
 *
 * **Lives in `jvmTest/` not `commonTest/`** — uses `javaClass.getResourceAsStream`
 * to load baseline JSON, which is a JVM-only API. iOS test targets are
 * out of scope per Tier 2 plan (only `jvmTest` count is tracked). If
 * future PRs need cross-platform baseline reads, introduce `okio`
 * Filesystem or an `expect`/`actual` resource loader at that point.
 */
class CanonicalEquivalenceTests {

    /**
     * Decoder Json — matches the locked Q7 contract: default config plus
     * `ignoreUnknownKeys = true` so forward-compat (older app reading
     * newer schema) doesn't blow up. Per-field `@SerialName` annotations
     * on `GalleryScenario`/`GalleryIndex` carry the snake_case mapping;
     * no global naming strategy.
     */
    private val json = Json { ignoreUnknownKeys = true }

    /**
     * Re-encoder Json — `encodeDefaults = true` is **required** to match
     * Swift `JSONEncoder`'s default behaviour for properties with
     * empty-container defaults (e.g., `Scenario.extraData: Map = emptyMap()`).
     *
     * Swift always emits all non-Optional properties, including
     * `"extraData":{}`. Kotlinx default omits properties matching the
     * declared default, which would drop the empty-map key. Setting
     * `encodeDefaults = true` makes Kotlinx also emit them.
     *
     * Side effect: nullable defaults (e.g., `simulationLanguage: String? = null`)
     * get emitted as `"simulationLanguage":null` instead of omitted. The
     * canonicalizer's Stage 1 null-omit rule drops them back, so the
     * canonical form still matches Swift's absent-key shape.
     */
    private val reencoderJson = Json {
        encodeDefaults = true
        ignoreUnknownKeys = true
    }

    /** Match the Kotlin port's case set; mirrors `CanonicalizerStage3Tests`. */
    private val codePhaseDiscriminators: Set<String> = setOf(
        "elimination",
        "scoreUpdate",
        "summary",
        "narration",
        "voteResults",
        "pairingResult",
        "assignment",
        "sharedAssignment",
        "eventInjected",
    )

    // -------- helpers --------

    private fun loadBaseline(path: String): JsonElement {
        val stream = CanonicalEquivalenceTests::class.java
            .getResourceAsStream("/baselines/$path")
            ?: error("Missing baseline: /baselines/$path (check commonTest/resources)")
        val text = stream.bufferedReader(Charsets.UTF_8).use { it.readText() }
        return json.parseToJsonElement(text)
    }

    private fun canonicalText(
        tree: JsonElement,
        polymorphicDiscriminatorValues: Set<String> = emptySet(),
    ): String {
        val canonical = Canonicalizer.canonicalize(tree, polymorphicDiscriminatorValues)
        return json.encodeToString(JsonElement.serializer(), canonical)
    }

    /**
     * Decode the Swift baseline → Kotlin instance → re-encode → JsonElement.
     * Used for non-polymorphic types where the canonical form IS valid
     * decoder input (Scenario, GalleryIndex).
     */
    private inline fun <reified T> roundtrip(
        baseline: JsonElement,
        serializer: kotlinx.serialization.KSerializer<T>,
    ): JsonElement {
        val decoded = json.decodeFromJsonElement(serializer, baseline)
        return reencoderJson.encodeToJsonElement(serializer, decoded)
    }

    // -------- 4 base preset Scenarios (camelCase roundtrip) --------

    @Test
    fun prisonersDilemmaCanonicalEquivalence() {
        val baseline = loadBaseline("prisoners_dilemma.json")
        val reencoded = roundtrip(baseline, Scenario.serializer())
        assertEquals(canonicalText(baseline), canonicalText(reencoded))
    }

    @Test
    fun wordWolfCanonicalEquivalence() {
        val baseline = loadBaseline("word_wolf.json")
        val reencoded = roundtrip(baseline, Scenario.serializer())
        assertEquals(canonicalText(baseline), canonicalText(reencoded))
    }

    @Test
    fun boketeCanonicalEquivalence() {
        val baseline = loadBaseline("bokete.json")
        val reencoded = roundtrip(baseline, Scenario.serializer())
        assertEquals(canonicalText(baseline), canonicalText(reencoded))
    }

    @Test
    fun targetScoreRaceCanonicalEquivalence() {
        val baseline = loadBaseline("target_score_race.json")
        val reencoded = roundtrip(baseline, Scenario.serializer())
        assertEquals(canonicalText(baseline), canonicalText(reencoded))
    }

    // -------- GalleryIndex (snake_case via per-field @SerialName) --------

    @Test
    fun galleryIndexCanonicalEquivalence() {
        val baseline = loadBaseline("gallery_index.json")
        val reencoded = roundtrip(baseline, GalleryIndex.serializer())
        assertEquals(canonicalText(baseline), canonicalText(reencoded))
    }

    // -------- CodePhaseEventPayload (tag-form normalization via Stage 3) --------

    @Test
    fun codePhaseEventPayloadCanonicalEquivalence() {
        // Construct Kotlin in-memory instances that mirror the Swift
        // fixture's input shape. The two sides emit DIFFERENT raw JSON
        // (Swift outer-wrap vs Kotlin tag-form), and Stage 3 normalizes
        // both to outer-wrap for comparison.
        val kotlinInstances: List<CodePhaseEventPayload> = listOf(
            CodePhaseEventPayload.Elimination(agent = "ada", voteCount = 3),
            CodePhaseEventPayload.ScoreUpdate(scores = mapOf("ada" to 10, "bob" to 5)),
            CodePhaseEventPayload.Summary(text = "Round 1 complete"),
            CodePhaseEventPayload.VoteResults(
                votes = mapOf("ada" to "bob", "bob" to "ada"),
                tallies = mapOf("ada" to 1, "bob" to 1),
            ),
            CodePhaseEventPayload.PairingResult(
                agent1 = "ada", action1 = "cooperate",
                agent2 = "bob", action2 = "defect",
            ),
            CodePhaseEventPayload.Assignment(agent = "ada", value = "wolf"),
            CodePhaseEventPayload.EventInjected(event = null),
            CodePhaseEventPayload.EventInjected(event = "earthquake"),
            // PR0-b: order-aligned to the baseline array tail (the condition-2
            // correctness hinge — element N here ↔ element N in the baseline).
            CodePhaseEventPayload.Narration(text = "And with that, ada pulls ahead."),
            CodePhaseEventPayload.SharedAssignment(value = "topic: animals"),
        )
        val kotlinEncoded: JsonElement = json.encodeToJsonElement(
            ListSerializer(CodePhaseEventPayload.serializer()),
            kotlinInstances,
        )
        val swiftBaseline = loadBaseline("code_phase_event_payload.json")

        // Swift baseline is already in outer-wrap form (Stage 3 no-op on
        // it); Kotlin emit is in tag-form (Stage 3 lifts it). Compare the
        // two canonical forms.
        assertEquals(
            canonicalText(swiftBaseline, codePhaseDiscriminators),
            canonicalText(kotlinEncoded, codePhaseDiscriminators),
            "Kotlin polymorphic emission must canonicalize to the same outer-wrap form as Swift",
        )
    }

    // -------- Micro-fixtures (null-omit policy verification) --------

    @Test
    fun nullOmitMicroFixturesCanonicalizeIdentically() {
        // Q6 hand-written fixtures: explicit `{"simulationLanguage":null,...}`
        // vs the omitted-key variant must produce the SAME canonical form
        // after Stage 1's null-omit transform. If this assertion ever fires,
        // Stage 1's null-omit policy has regressed.
        val explicit = loadBaseline("_micro/simlang_explicit_null.json")
        val omitted = loadBaseline("_micro/simlang_omitted.json")
        assertEquals(canonicalText(explicit), canonicalText(omitted))
    }
}
