package com.pastura.models

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * A type-safe wrapper for dynamic YAML/JSON values in scenario definitions.
 *
 * Scenarios can have arbitrary top-level fields (e.g., `topics`, `words`)
 * with varying structures. This sealed class captures the common shapes found
 * in preset scenarios while remaining serializable and comparable.
 *
 * Used by `Scenario.extraData` to hold scenario-specific data that
 * phase handlers access at runtime.
 *
 * Kotlin port of `Pastura/Pastura/Models/AnyCodableValue.swift`.
 *
 * **Disambiguation order (load-bearing):** decoding attempts shapes in this order:
 * 1. String (JSON primitive)
 * 2. `List<Map<String, String>>` (array of objects — checked BEFORE plain array)
 * 3. `List<String>` (array of strings)
 * 4. `Map<String, String>` (object)
 *
 * The arrayOfDicts-before-array order matches the Swift `init(from:)` decode
 * order and is critical: an empty JSON array `[]` would otherwise decode as
 * [ArrayValue] rather than [ArrayOfDictionariesValue] depending on context.
 * The shape-based `JsonElement` check (empty array → [ArrayValue]; first element
 * is a `JsonObject` → [ArrayOfDictionariesValue]; else → [ArrayValue]) preserves
 * the intended semantics.
 */
@Serializable(with = AnyCodableValueSerializer::class)
public sealed class AnyCodableValue {
    /** A single string value. */
    public data class StringValue(public val value: String) : AnyCodableValue()

    /** An array of strings (e.g., bokete photo descriptions). */
    public data class ArrayValue(public val value: List<String>) : AnyCodableValue()

    /**
     * A string-keyed dictionary (e.g., a single word wolf topic set).
     * Map iteration order is not guaranteed.
     */
    public data class DictionaryValue(public val value: Map<String, String>) : AnyCodableValue()

    /**
     * An array of string-keyed dictionaries
     * (e.g., word wolf topic sets: `[{"majority": "りんご", "minority": "みかん"}, ...]`).
     */
    public data class ArrayOfDictionariesValue(
        public val value: List<Map<String, String>>,
    ) : AnyCodableValue()
}

/**
 * Custom [KSerializer] for [AnyCodableValue] that disambiguates JSON shapes
 * via raw [JsonElement] inspection.
 *
 * Disambiguation order matches the Swift `init(from:)` decode order — see
 * [AnyCodableValue] class KDoc for rationale.
 */
public object AnyCodableValueSerializer : KSerializer<AnyCodableValue> {
    override val descriptor: SerialDescriptor =
        buildClassSerialDescriptor("AnyCodableValue")

    override fun deserialize(decoder: Decoder): AnyCodableValue {
        val jsonDecoder = (decoder as? JsonDecoder)
            ?: error("AnyCodableValue requires Json decoder")
        return when (val element = jsonDecoder.decodeJsonElement()) {
            is JsonPrimitive -> {
                val s = element.content.takeIf { element.isString }
                    ?: throw SerializationException(
                        "AnyCodableValue: expected String primitive, got $element"
                    )
                AnyCodableValue.StringValue(s)
            }
            is JsonArray -> {
                if (element.isEmpty() || element.first() !is JsonObject) {
                    // Empty array or array of non-objects → ArrayValue.
                    AnyCodableValue.ArrayValue(
                        element.map { e ->
                            (e as? JsonPrimitive)?.content
                                ?: throw SerializationException(
                                    "AnyCodableValue.ArrayValue: expected String element, got $e"
                                )
                        }
                    )
                } else {
                    // First element is JsonObject → ArrayOfDictionariesValue.
                    AnyCodableValue.ArrayOfDictionariesValue(
                        element.map { e ->
                            val obj = e as? JsonObject
                                ?: throw SerializationException(
                                    "AnyCodableValue.ArrayOfDictionariesValue: expected object element, got $e"
                                )
                            obj.entries.associate { (k, v) ->
                                k to ((v as? JsonPrimitive)?.content
                                    ?: throw SerializationException(
                                        "AnyCodableValue.ArrayOfDictionariesValue: expected String value for key $k, got $v"
                                    ))
                            }
                        }
                    )
                }
            }
            is JsonObject -> {
                AnyCodableValue.DictionaryValue(
                    element.entries.associate { (k, v) ->
                        k to ((v as? JsonPrimitive)?.content
                            ?: throw SerializationException(
                                "AnyCodableValue.DictionaryValue: expected String value for key $k, got $v"
                            ))
                    }
                )
            }
        }
    }

    override fun serialize(encoder: Encoder, value: AnyCodableValue) {
        val jsonEncoder = (encoder as? JsonEncoder)
            ?: error("AnyCodableValue requires Json encoder")
        jsonEncoder.encodeJsonElement(value.toJsonElement())
    }

    private fun AnyCodableValue.toJsonElement(): JsonElement = when (this) {
        is AnyCodableValue.StringValue -> JsonPrimitive(value)
        is AnyCodableValue.ArrayValue -> buildJsonArray { value.forEach { add(JsonPrimitive(it)) } }
        is AnyCodableValue.DictionaryValue -> buildJsonObject {
            value.forEach { (k, v) -> put(k, v) }
        }
        is AnyCodableValue.ArrayOfDictionariesValue -> buildJsonArray {
            value.forEach { dict ->
                add(buildJsonObject { dict.forEach { (k, v) -> put(k, v) } })
            }
        }
    }
}
