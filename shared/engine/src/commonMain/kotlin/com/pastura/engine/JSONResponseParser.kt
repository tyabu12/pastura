package com.pastura.engine

import com.pastura.models.SimulationError
import com.pastura.models.TurnOutput
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Extracts structured data from raw LLM text responses.
 *
 * Handles the common LLM output artifacts: thinking tags (`<think>`,
 * `<|channel>thought`), markdown code fences, and leading/trailing garbage. All
 * JSON values are normalized to `String` for [TurnOutput].
 *
 * ## Scope: the ADR-023 §6 Stage-2 gate slice's *minimal* subset
 *
 * Ported: the cleanup pipeline (strip thinking tags -> truncate at chat-template
 * token -> unwrap code fence -> extract the first balanced object) plus parse and
 * value normalization.
 *
 * **Knowingly absent** — named units, tracked on #501 for Stage 3, never silent
 * drops:
 *
 * | Absent | Why |
 * |---|---|
 * | The two-step repair pipeline (`unclosed_string` -> `unclosed_brace`, #194) | hardening, not a boundary concern; the gate never scripts a truncated stream |
 * | Schema-guarded multi-object salvage (#907) | same |
 * | `PartialOutputExtractor` | named Stage-3 freight in ADR-023 §6 |
 * | `TurnOutput.rawText` passthrough | Kotlin `TurnOutput` has no `rawText`; its only consumer is Data-layer `TurnRecord.rawOutput` audit, outside the Engine port |
 *
 * `expectedKeys` is therefore accepted and **only** used for the post-parse guard,
 * not to drive salvage.
 *
 * Swift original: `Pastura/Pastura/LLM/JSONResponseParser.swift`.
 */
internal class JSONResponseParser {

    private companion object {
        /** Gemma 4 channel thinking: `<|channel>thought...<channel|>`. */
        val CHANNEL_THINKING = Regex("""<\|channel>thought\s*.*?<channel\|>""", RegexOption.DOT_MATCHES_ALL)

        /** Common thinking-model format: `<think>...</think>` (DeepSeek, Qwen). */
        val THINK_TAG = Regex("""<think>.*?</think>""", RegexOption.DOT_MATCHES_ALL)

        /** Chat-template token — truncate everything from the first occurrence. */
        val CHAT_TEMPLATE_TOKEN = Regex("""<\|im_end\|>.*""", RegexOption.DOT_MATCHES_ALL)

        val CODE_BLOCK = Regex("""```(?:json)?\s*\n?(.*?)\n?```""", RegexOption.DOT_MATCHES_ALL)

        val JSON = Json { ignoreUnknownKeys = true }
    }

    /**
     * Parse raw LLM output into a [TurnOutput].
     *
     * @throws SimulationException wrapping [SimulationError.JsonParseFailed] when
     *   no valid JSON can be extracted.
     */
    fun parse(text: String): TurnOutput = parse(text, expectedKeys = emptySet()).first

    /**
     * Parse with an optional post-parse schema guard.
     *
     * @param expectedKeys When non-empty, a parse whose result is missing any of
     *   these keys — or has one empty — is rejected rather than returned. Preserves
     *   the throw instead of handing back a half-formed [TurnOutput] (#194 PR#a
     *   Item 2d).
     * @return The parsed output plus the applied repair kind. **Always `null`
     *   here** — the repair pipeline is Stage-3 freight (see the class doc). The
     *   pair shape is kept so the Stage-3 port can add repairs without changing
     *   every callsite.
     * @throws SimulationException wrapping [SimulationError.JsonParseFailed].
     */
    fun parse(text: String, expectedKeys: Set<String>): Pair<TurnOutput, String?> {
        val cleaned = applyCleanupPipeline(text)
        val output = tryParse(cleaned) ?: throw SimulationException(SimulationError.JsonParseFailed(raw = text))

        if (expectedKeys.isNotEmpty() && !hasAllExpectedKeys(output, expectedKeys)) {
            throw SimulationException(SimulationError.JsonParseFailed(raw = text))
        }
        return output to null
    }

    // MARK: - Pipeline

    private fun applyCleanupPipeline(text: String): String {
        var cleaned = text.trim()
        cleaned = CHANNEL_THINKING.replace(cleaned, "")
        cleaned = THINK_TAG.replace(cleaned, "")
        cleaned = CHAT_TEMPLATE_TOKEN.replace(cleaned, "")
        cleaned = extractFromCodeBlock(cleaned)
        cleaned = cleaned.trim()
        return extractFirstJsonObject(cleaned)
    }

    private fun extractFromCodeBlock(text: String): String {
        if (!text.contains("```")) return text
        return CODE_BLOCK.find(text)?.groupValues?.get(1) ?: text
    }

    /**
     * Extract the first balanced `{...}` object, string-aware.
     *
     * Walks from the first structural `{` (one outside any string literal) and
     * returns the slice ending at the `}` that brings balance back to zero.
     *
     * **Runs unconditionally, and that is the point (#751 sub-class 1).** A
     * `{`/`}`-framed string is not proof of a clean single object:
     * grammar-constrained generation can append a stray `}` (`{…}}`) or trailing
     * prose, both of which pass a prefix/suffix check yet break the parse. The
     * balanced scan is an identity transform for an already-clean object.
     *
     * Returns the input unchanged when there is no `{`, when braces never balance
     * (an unclosed object — Swift hands that to its repair pipeline; this slice
     * simply fails the parse), or when the trailing residue is itself object-like
     * (`{…}{…}`), which signals the model re-rolled a whole second answer — better
     * to fail and re-sample than to salvage a possibly off-persona first object.
     */
    private fun extractFirstJsonObject(text: String): String {
        val insideString = mapStringSpans(text)
        val start = text.indices.firstOrNull { text[it] == '{' && !insideString[it] } ?: return text

        var balance = 0
        for (i in start until text.length) {
            if (insideString[i]) continue
            when (text[i]) {
                '{' -> balance++
                '}' -> {
                    balance--
                    if (balance == 0) {
                        val residue = text.substring(i + 1).trimStart()
                        // Object-like residue => multi-object span. Swift's
                        // schema-guarded salvage (#907) can rescue this; that path
                        // is Stage-3 freight, so here it fails the parse.
                        if (residue.startsWith("{")) return text
                        return text.substring(start, i + 1)
                    }
                }
            }
        }
        return text
    }

    /**
     * Per-character "is inside a string literal" map — the Kotlin counterpart of
     * Swift's `StringStateMachine`.
     *
     * Marks the characters *between* quotes, not the quotes themselves, so a
     * structural `{` is distinguishable from one inside `"{"`. Honours backslash
     * escapes so `"\""` does not close the string early.
     */
    private fun mapStringSpans(text: String): BooleanArray {
        val inside = BooleanArray(text.length)
        var inString = false
        var escaped = false
        for (i in text.indices) {
            val c = text[i]
            if (inString) {
                inside[i] = true
                when {
                    escaped -> escaped = false
                    c == '\\' -> escaped = true
                    c == '"' -> {
                        inside[i] = false // the closing quote is structural
                        inString = false
                    }
                }
            } else if (c == '"') {
                inString = true
                escaped = false
            }
        }
        return inside
    }

    private fun tryParse(cleaned: String): TurnOutput? {
        val element = runCatching { JSON.parseToJsonElement(cleaned) }.getOrNull() ?: return null
        val obj = element as? JsonObject ?: return null
        return TurnOutput(fields = normalizeValues(obj))
    }

    private fun hasAllExpectedKeys(output: TurnOutput, expectedKeys: Set<String>): Boolean =
        expectedKeys.all { !output.fields[it].isNullOrEmpty() }

    /**
     * Normalize every JSON value to `String`. Null values are omitted.
     *
     * ## Deliberate divergence from Swift — a Swift bug this port does NOT copy
     *
     * Swift's `normalizeValues` checks `value as? Bool` **before** `as? NSNumber`,
     * with the comment "Check Bool before NSNumber — Bool bridges to NSNumber in
     * ObjC". The intent is to catch JSON `true`/`false`. The effect is wider,
     * because `NSNumber` -> `Bool` bridging succeeds for exactly 0 and 1.
     * Measured on this branch against the real Swift branch order:
     *
     * | JSON | Swift | Kotlin (here) |
     * |---|---|---|
     * | `0` | **`"false"`** | `"0"` |
     * | `1` | **`"true"`** | `"1"` |
     * | `0.0` | **`"false"`** | `"0.0"` |
     * | `1.0` | **`"true"`** | `"1.0"` |
     * | `2`, `-1`, `0.5` | `"2"`, `"-1"`, `"0.5"` | same |
     * | `true` / `false` | `"true"` / `"false"` | same |
     *
     * **Why Kotlin does not replicate it.** ADR-023 §6 makes the Swift test files
     * the executable spec — and that spec does **not** pin this: the only numeric
     * test uses `{"score": 42, "ratio": 3.14}`, values chosen (by luck) to sidestep
     * the 0/1 range, and no test anywhere passes a numeric 0 or 1 through the
     * parser. So the behaviour is untested, incidental, and contradicts its own
     * test's name ("Numeric values normalized to String" — `1` does not become
     * `"1"`). Replicating it would cement an unintended Foundation quirk as a
     * *cross-language contract*, in a language that has no `NSNumber`.
     *
     * Pinned by `JSONResponseParserParityTests` and filed as **#1150** with a
     * verified fix, per ADR-023 §10 ("Engine behavior gets a second,
     * cross-language executable spec, which also hardens the Swift side against
     * accidental semantic drift"). When #1150 lands the divergence closes with **no
     * change here** — this side is already correct.
     *
     * ## Nested values
     *
     * Objects and arrays re-serialize to a JSON string. Swift passes `.sortedKeys`;
     * kotlinx-serialization has no such option, so nested object keys are sorted
     * explicitly to match.
     */
    private fun normalizeValues(obj: JsonObject): Map<String, String> {
        val result = mutableMapOf<String, String>()
        for ((key, value) in obj) {
            when (value) {
                is JsonNull -> Unit // omitted, matching Swift
                is JsonPrimitive -> result[key] = value.content
                is JsonObject, is JsonArray -> result[key] = canonicalJson(value)
            }
        }
        return result
    }

    /**
     * Re-serialize a nested value with object keys sorted at every depth, matching
     * Swift's `JSONSerialization.data(withJSONObject:options: [.sortedKeys])`.
     *
     * kotlinx-serialization has no `sortedKeys` option, so the sort is explicit.
     * Without it the two engines would emit the same nested object with different
     * key order — a Stage-4 transcript diff for a value that is semantically
     * identical.
     */
    private fun canonicalJson(element: JsonElement): String =
        JSON.encodeToString(JsonElement.serializer(), sortKeysDeep(element))

    /** `associate` keeps insertion order, so the sorted order survives encoding. */
    private fun sortKeysDeep(element: JsonElement): JsonElement = when (element) {
        is JsonObject ->
            JsonObject(element.entries.sortedBy { it.key }.associate { it.key to sortKeysDeep(it.value) })
        is JsonArray -> JsonArray(element.map { sortKeysDeep(it) })
        else -> element
    }
}
