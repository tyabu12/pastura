package com.pastura.models

import it.krzeminski.snakeyaml.engine.kmp.api.Load
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * YAML 1.2 decoder for the Pastura KMP spike (Issue #220 W2 PR-A item 9).
 *
 * Day-1 D3 deliverable. Decodes YAML text to [JsonElement] — the canonical
 * input format for PR-B's canonicalizer + Swift↔Kotlin roundtrip harness.
 *
 * **API surface lock (per plan v3):** `decode(yaml: String): JsonElement`.
 * Typed decode (`decode<T>(yaml, serializer)`) is recoverable at the call
 * site via `Json.decodeFromJsonElement(serializer, tree)` without giving
 * up the canonical-form view that PR-B's canonicalizer consumes.
 *
 * **Null-preservation policy (PR-A scope per Q1 (c)):**
 * - Absent YAML key produces an absent [JsonObject] key (NOT [JsonNull]).
 * - Explicit `key: ~` / `key: null` produces [JsonNull].
 * - PR-B's canonicalizer is responsible for null-vs-omit normalization
 *   when comparing Swift- and Kotlin-produced trees; the codec itself is
 *   pass-through.
 *
 * **No expect/actual required:** snakeyaml-engine-kmp's [Load] API is
 * exposed in commonMain across all KMP targets (JVM + Native iOS + JS +
 * Wasm), so a single commonMain implementation suffices. The W2 plan v3
 * listed expect/actual as the structural approach; this implementation
 * uses the simpler form because the library does the multiplatform lift.
 */
public interface YamlCodec {
    /**
     * Parse a YAML 1.2 string into a [JsonElement] tree.
     *
     * @throws YamlDecodeError if the input is malformed or contains
     *   unsupported scalar types.
     */
    public fun decode(yaml: String): JsonElement

    public companion object {
        /**
         * Returns the default [YamlCodec] implementation backed by
         * snakeyaml-engine-kmp.
         */
        public fun default(): YamlCodec = SnakeYamlEngineCodec
    }
}

/** Errors thrown by [YamlCodec] implementations. */
public sealed class YamlDecodeError(message: String) : Exception(message) {
    /** The input was not valid YAML 1.2. */
    public data class MalformedYaml(public val reason: String) :
        YamlDecodeError("Malformed YAML: $reason")

    /**
     * snakeyaml-engine produced a scalar type the [JsonElement] mapper
     * does not handle (e.g., a custom-tagged value or a Date scalar
     * preserved as a platform-native type).
     */
    public data class UnsupportedScalar(public val kotlinType: String, public val rendered: String) :
        YamlDecodeError("Unsupported YAML scalar type $kotlinType: $rendered")
}

/**
 * Production [YamlCodec] backed by snakeyaml-engine-kmp's [Load] API.
 *
 * Stateless `object` — safe to share across coroutines and platforms.
 * Per snakeyaml-engine docs, [LoadSettings] + [Load] instances are
 * thread-safe in the sense that each parse uses a fresh internal scanner;
 * reusing the singleton is the documented happy path.
 */
internal object SnakeYamlEngineCodec : YamlCodec {

    // snakeyaml-engine-kmp's no-arg Load() constructor uses default
    // LoadSettings (YAML 1.2 core schema, no recursive keys, no comment
    // parsing) — appropriate for parsing Pastura preset YAML.
    private val load: Load = Load()

    override fun decode(yaml: String): JsonElement {
        val raw: Any? = try {
            load.loadOne(yaml)
        } catch (t: Throwable) {
            throw YamlDecodeError.MalformedYaml(t.message ?: t::class.simpleName ?: "unknown")
        }
        return yamlValueToJson(raw)
    }
}

/**
 * Convert snakeyaml-engine's untyped output ([Any]?) to a [JsonElement] tree.
 *
 * Recursive walk handling the scalar types snakeyaml-engine emits in YAML
 * 1.2 core schema mode: `Map<String?, Any?>`, `List<Any?>`, `String`,
 * `Long`/`Int`, `Double`/`Float`, `Boolean`, and `null`.
 *
 * Keys are coerced to [String] via [toString] — YAML 1.2 allows non-string
 * map keys (e.g. `42: foo` or `[a, b]: 1`), but JSON object keys must be
 * strings. Pastura preset YAML never uses non-string keys, so this
 * coercion is safe and matches the implicit convention of the Swift
 * `ScenarioLoader` (Yams → `[String: Any]` cast).
 *
 * Visible for testing — the conversion contract is exercised by the
 * smoke-test suite to pre-establish PR-B's canonicalizer input shape.
 */
internal fun yamlValueToJson(value: Any?): JsonElement = when (value) {
    null -> JsonNull
    is Boolean -> JsonPrimitive(value)
    is String -> JsonPrimitive(value)
    is Int -> JsonPrimitive(value)
    is Long -> JsonPrimitive(value)
    is Float -> JsonPrimitive(value)
    is Double -> JsonPrimitive(value)
    is Map<*, *> -> JsonObject(
        value.entries.associate { (k, v) ->
            // Defensive: a null YAML map key would silently collide with an
            // explicit "null" string key. Pastura presets never use null
            // keys, so fail loud rather than coerce.
            val key = k ?: throw YamlDecodeError.UnsupportedScalar(
                kotlinType = "null-key",
                rendered = "<null map key>",
            )
            key.toString() to yamlValueToJson(v)
        },
    )
    is List<*> -> JsonArray(value.map { yamlValueToJson(it) })
    else -> throw YamlDecodeError.UnsupportedScalar(
        kotlinType = value::class.simpleName ?: "anonymous",
        rendered = value.toString(),
    )
}
