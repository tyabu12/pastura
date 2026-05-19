package com.pastura.models

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject

/**
 * Canonical [JsonElement] form for Swift↔Kotlin wire-shape equivalence —
 * Issue #220 W2 PR-B.
 *
 * Lands in stages over the PR-B commit sequence:
 *
 * - **Stage 1 (this commit) — structural**: recursive [JsonObject] key sort
 *   (alphabetical), null-omit at object keys (`key: JsonNull` dropped), and
 *   array order preservation (inner objects still get key-sorted; nulls
 *   inside arrays are preserved because position is meaningful there).
 * - **Stage 2 — numeric** (later commit): Kotlin-construction-layer
 *   Long/Int → Long canonical and Double IEEE-754 bit-equality after JSON
 *   round-trip.
 * - **Stage 3 — tag-form** (later commit): single-direction normalization of
 *   Kotlin polymorphic-discriminator shape (`{"type":"<name>",<payload>}`)
 *   into Swift's auto-synthesized Codable outer-wrap shape
 *   (`{"<caseName>":{<payload>}}`). The Swift form is canonical to match
 *   existing on-disk `payloadJSON` SQLite rows; the Kotlin polymorphic form
 *   is the lossy input that needs to be lifted, not the target.
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
     * Return the canonical form of [tree]. Recursive; never mutates [tree].
     *
     * Stage 1 rules applied:
     * - [JsonObject]: entries with [JsonNull] values dropped, surviving
     *   entries sorted alphabetically by key, values recursively
     *   canonicalized.
     * - [JsonArray]: order preserved, elements recursively canonicalized
     *   (nulls within arrays survive).
     * - [JsonNull], [kotlinx.serialization.json.JsonPrimitive]: returned
     *   as-is.
     */
    public fun canonicalize(tree: JsonElement): JsonElement = when (tree) {
        is JsonObject -> canonicalizeObject(tree)
        is JsonArray -> JsonArray(tree.map { canonicalize(it) })
        else -> tree
    }

    private fun canonicalizeObject(obj: JsonObject): JsonObject {
        // associate { } returns LinkedHashMap (Kotlin stdlib default),
        // which JsonObject + Json.encodeToString iterate in insertion order.
        // Sorted insertion order ⇒ sorted JSON-text output.
        val sorted = obj.entries
            .filterNot { it.value is JsonNull }
            .sortedBy { it.key }
            .associate { it.key to canonicalize(it.value) }
        return JsonObject(sorted)
    }
}
