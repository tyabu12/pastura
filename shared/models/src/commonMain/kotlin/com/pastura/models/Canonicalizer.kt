package com.pastura.models

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Canonical [JsonElement] form for Swift↔Kotlin wire-shape equivalence —
 * Issue #220 W2 PR-B.
 *
 * Composes three stages applied to the input tree:
 *
 * - **Stage 1 — structural**: recursive [JsonObject] key sort
 *   (alphabetical), null-omit at object keys (`key: JsonNull` dropped), and
 *   array order preservation (inner objects still get key-sorted; nulls
 *   inside arrays are preserved because position is meaningful there).
 * - **Stage 2 — numeric (no-op transform at this layer)**: the Int/Long
 *   contract applies at the Kotlin construction layer (fixtures pin to
 *   `Long` for portability). At the JSON-text layer produced by
 *   `kotlinx.serialization`, [JsonPrimitive] of `Int` and `Long` serialize
 *   identically because the value is stored as a content string — no
 *   transform is needed. See `CanonicalizerStage2Tests` for the
 *   drift-guard sanity checks.
 * - **Stage 3 — tag-form**: single-direction normalization of Kotlin
 *   polymorphic-discriminator shape (`{"type":"<name>",<payload>}`) into
 *   Swift's auto-synthesized Codable outer-wrap shape
 *   (`{"<caseName>":{<payload>}}`). The Swift form is canonical to match
 *   existing on-disk `payloadJSON` SQLite rows; the Kotlin polymorphic
 *   form is the lossy input that needs to be lifted, not the target.
 *
 * **Stage 3 is opt-in.** The default [canonicalize] call applies only
 * Stages 1+2 (which is everything needed for non-polymorphic types like
 * `Scenario` and `GalleryIndex`). For polymorphic shapes
 * ([CodePhaseEventPayload], [SimulationEvent], [SimulationError]), the
 * caller passes the set of valid discriminator-string values to opt in.
 * Why opt-in: the canonicalizer has no schema knowledge, so an
 * unconditional `type` key lift would corrupt non-polymorphic objects
 * that legitimately have a `type` field (e.g., `OutputSchema.Field`'s
 * `type: "text"` value, where `"text"` is a field type — not a
 * discriminator).
 *
 * **Test-side transform only.** No production sealed class carries a
 * `@Serializable(with = ...)` custom serializer because of this work;
 * the canonicalizer manipulates the `JsonElement` tree post-encode. The
 * custom-KSerializer-on-production-types decision is W3+ Engine port
 * scope per ADR-004.
 *
 * **Pure function — no I/O, no mutation of input.** Stateless object —
 * safe to share across coroutines and platforms.
 *
 * **Null-omit policy rationale**: Swift's `JSONEncoder` default-omits `nil`
 * Optionals; Kotlin's `kotlinx.serialization` omits properties at their
 * declared default value (also typically `null`). Both layers produce
 * absent-key form for the common case. The canonicalizer normalizes
 * explicit `key: null` → absent so that hand-crafted fixtures and
 * forced-`encodeNil` callsites compare equal to the default-omitted form.
 * Array nulls (`[1, null, 2]`) are preserved because they carry positional
 * meaning — dropping them would shift element indices.
 */
public object Canonicalizer {

    /**
     * Discriminator key for kotlinx polymorphic encoding.
     *
     * Hardcoded as kotlinx-serialization's default `"type"`. If a future
     * production change adds `@JsonClassDiscriminator("kind")` (or similar)
     * to a sealed class, this constant must update in lockstep — the
     * canonicalizer does not introspect annotations.
     */
    private const val DISCRIMINATOR_KEY: String = "type"

    /**
     * Return the canonical form of [tree]. Recursive; never mutates [tree].
     *
     * Default call (empty [polymorphicDiscriminatorValues]) applies Stages
     * 1+2 only — appropriate for non-polymorphic shapes like `Scenario`
     * and `GalleryIndex`. Pass the case-name set to opt in to Stage 3
     * tag-form normalization for polymorphic shapes.
     *
     * @param tree the JSON tree to canonicalize.
     * @param polymorphicDiscriminatorValues the set of valid
     *   `{"type":"<name>",...}` discriminator strings that should be
     *   lifted to Swift outer-wrap form. Pass an empty set (the default)
     *   to skip Stage 3.
     */
    public fun canonicalize(
        tree: JsonElement,
        polymorphicDiscriminatorValues: Set<String> = emptySet(),
    ): JsonElement {
        val tagNormalized = if (polymorphicDiscriminatorValues.isEmpty()) {
            tree
        } else {
            normalizeTagForm(tree, polymorphicDiscriminatorValues)
        }
        return canonicalizeStructure(tagNormalized)
    }

    // Stage 1 — recursive structural normalization.
    private fun canonicalizeStructure(tree: JsonElement): JsonElement = when (tree) {
        is JsonObject -> sortAndOmitNulls(tree)
        is JsonArray -> JsonArray(tree.map { canonicalizeStructure(it) })
        else -> tree
    }

    private fun sortAndOmitNulls(obj: JsonObject): JsonObject {
        // associate { } returns LinkedHashMap (Kotlin stdlib default),
        // which JsonObject + Json.encodeToString iterate in insertion order.
        // Sorted insertion order ⇒ sorted JSON-text output.
        val sorted = obj.entries
            .filterNot { it.value is JsonNull }
            .sortedBy { it.key }
            .associate { it.key to canonicalizeStructure(it.value) }
        return JsonObject(sorted)
    }

    // Stage 3 — recursive lift of `{"type":"X", ...}` → `{"X":{...}}` when
    // `"X"` is in the supplied discriminator-value set.
    private fun normalizeTagForm(
        tree: JsonElement,
        discriminatorValues: Set<String>,
    ): JsonElement = when (tree) {
        is JsonObject -> normalizeTagFormObject(tree, discriminatorValues)
        is JsonArray -> JsonArray(tree.map { normalizeTagForm(it, discriminatorValues) })
        else -> tree
    }

    private fun normalizeTagFormObject(
        obj: JsonObject,
        discriminatorValues: Set<String>,
    ): JsonObject {
        val typeValue = (obj[DISCRIMINATOR_KEY] as? JsonPrimitive)
            ?.takeIf { it.isString }
            ?.content
        if (typeValue != null && typeValue in discriminatorValues) {
            val payload = obj.entries
                .filterNot { it.key == DISCRIMINATOR_KEY }
                .associate { it.key to normalizeTagForm(it.value, discriminatorValues) }
            return JsonObject(mapOf(typeValue to JsonObject(payload)))
        }
        return JsonObject(
            obj.entries.associate { it.key to normalizeTagForm(it.value, discriminatorValues) },
        )
    }
}
