package com.pastura.engine

import com.pastura.models.SimulationError
import com.pastura.models.TurnOutput
import kotlinx.serialization.ExperimentalSerializationApi
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
 * | `PartialOutputExtractor` | landed as a sibling commonMain type in PR-3 (#501 Stage 3); this parser still does not consume it — the two share only the duplicated thinking-tag regexes by parity |
 * | `TurnOutput.rawText` passthrough | Kotlin `TurnOutput` has no `rawText`; its only consumer is Data-layer `TurnRecord.rawOutput` audit, outside the Engine port |
 *
 * `expectedKeys` is therefore accepted but **currently unused**. It used to drive a
 * post-parse guard on every successful parse; ADR-021 § Amendment 2026-08-06 removed
 * that, because the guard had no counterpart position here — Swift consults it only
 * on the salvage and post-repair paths, both of which are absent above. The
 * parameter is kept as the Stage-3 port's landing point; see [parse].
 *
 * Swift original: `Pastura/Pastura/LLM/JSONResponseParser.swift`.
 */
internal class JSONResponseParser {

    private companion object {
        // These patterns must match across newlines (a model's thinking block or
        // a fenced JSON body spans many lines). The idiomatic flag for that,
        // `RegexOption.DOT_MATCHES_ALL`, is NOT in the Kotlin *common* stdlib —
        // it is a platform-specific entry present only on JVM and Native, so
        // commonMain fails to resolve it (`compileCommonMainKotlinMetadata`).
        // We therefore encode "any character including newline" directly in the
        // pattern as `[\s\S]`, which is pure regex syntax with no flag
        // dependence and identical semantics on every target.
        /** Gemma 4 channel thinking: `<|channel>thought...<channel|>`. */
        val CHANNEL_THINKING = Regex("""<\|channel>thought\s*[\s\S]*?<channel\|>""")

        /** Common thinking-model format: `<think>...</think>` (DeepSeek, Qwen). */
        val THINK_TAG = Regex("""<think>[\s\S]*?</think>""")

        /**
         * Chat-template token — truncate everything from the first occurrence.
         *
         * ChatML-only by construction, mirroring the Swift original: correct for
         * Qwen 3, and for Gemma 4 it fires only on a spelled-out `<|im_end|>`.
         * Gemma's markers are `<|turn>` / `<turn|>` and its vocabulary has no
         * `<|im_end|>`, so spelled-out is the only form that could arrive — and
         * it is not the form a Gemma hallucination would reach for. What it does
         * NOT do for Gemma is truncate a Gemma-shaped continuation.
         *
         * This type is backend-agnostic, so do not assume the llama.cpp
         * guarantee here: under that backend a control marker cannot reach
         * decoded text at all, but a server-decoding backend offers no such
         * guarantee. Which text a Gemma hallucination would spell out is **not
         * established**; whatever it is, it would not be truncated here.
         * Per-model sourcing is #1422.
         */
        val CHAT_TEMPLATE_TOKEN = Regex("""<\|im_end\|>[\s\S]*""")

        val CODE_BLOCK = Regex("""```(?:json)?\s*\n?([\s\S]*?)\n?```""")

        /**
         * `allowTrailingComma`: Swift's `JSONSerialization.jsonObject` accepts
         * `{"a":1,}` / `[1,2,]` on the HAPPY path (iOS 17+) — the Swift parse doc
         * says so explicitly, which is why it has no trailing-comma repair. Kotlin
         * defaults to rejecting them, which would have been an undocumented
         * divergence in a step this slice DOES port (not one of the deferred
         * repairs). Opting in keeps the two parsers agreeing.
         *
         * `ignoreUnknownKeys` is deliberately absent: it only affects
         * `@Serializable`-driven decoding and is a no-op for `parseToJsonElement`,
         * which is all this parser uses. The untyped `JsonObject` walk already
         * tolerates extra LLM fields.
         */
        @OptIn(ExperimentalSerializationApi::class)
        val JSON = Json { allowTrailingComma = true }
    }

    /**
     * Parse raw LLM output into a [TurnOutput].
     *
     * @throws SimulationException wrapping [SimulationError.JsonParseFailed] when
     *   no valid JSON can be extracted.
     */
    fun parse(text: String): TurnOutput = parse(text, expectedKeys = emptySet()).first

    /**
     * Parse the happy path. No schema guard runs here — see [expectedKeys].
     *
     * @param expectedKeys **Currently unused — reserved for the Stage-3 repair /
     *   salvage port.** Until ADR-021 § Amendment 2026-08-06 this parameter drove
     *   a post-parse guard applied on *every* successful parse, which made an
     *   empty declared key a `parse_failed` here while Swift returned it and let
     *   `LLMCaller` decide — the `SCHEMA_GUARD_POSITION` divergence. The guard is
     *   gone rather than relocated because this parser has neither of the two
     *   places Swift consults it (salvage, post-repair); both are Stage-3 freight
     *   per the class doc. When that port lands, re-add the guard **only** on
     *   those two acceptance paths, mirroring
     *   `JSONResponseParser.swift` — re-adding it here would silently
     *   re-open the divergence.
     * @return The parsed output plus the applied repair kind. **Always `null`
     *   here** — the repair pipeline is Stage-3 freight (see the class doc). The
     *   pair shape is kept so the Stage-3 port can add repairs without changing
     *   every callsite.
     * @throws SimulationException wrapping [SimulationError.JsonParseFailed].
     */
    @Suppress("UNUSED_PARAMETER")
    fun parse(text: String, expectedKeys: Set<String>): Pair<TurnOutput, String?> {
        val cleaned = applyCleanupPipeline(text)
        val output = tryParse(cleaned) ?: throw SimulationException(SimulationError.JsonParseFailed(raw = text))
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

    /**
     * Normalize every JSON value to `String`. Null values are omitted.
     *
     * ## The Bool-bridge divergence from Swift — a Swift bug this port never copied
     *
     * Swift's `normalizeValues` **used to** check `value as? Bool` before
     * `as? NSNumber`, with the comment "Check Bool before NSNumber — Bool bridges
     * to NSNumber in ObjC". The intent was to catch JSON `true`/`false`. The
     * effect was wider, because `NSNumber` -> `Bool` bridging succeeds for exactly
     * 0 and 1, so the numbers `0` / `1` (and `0.0` / `1.0`) were swallowed:
     *
     * | JSON | Swift (pre-#1150) | Kotlin (here) |
     * |---|---|---|
     * | `0` | **`"false"`** | `"0"` |
     * | `1` | **`"true"`** | `"1"` |
     * | `0.0` | **`"false"`** | `"0.0"` |
     * | `1.0` | **`"true"`** | `"1.0"` |
     * | `2`, `-1`, `0.5` | `"2"`, `"-1"`, `"0.5"` | same |
     * | `true` / `false` | `"true"` / `"false"` | same |
     *
     * **Why Kotlin did not replicate it.** Replicating it would have cemented an
     * unintended Foundation quirk as a *cross-language contract*, in a language
     * that has no `NSNumber`. Porting the parser is what surfaced it at all —
     * the hardening ADR-023 §10 anticipates from a cross-language spec, arriving
     * early from the port itself rather than from the Stage-4 harness that
     * section scopes it to. It was filed as **#1150** and fixed there: Swift now
     * discriminates on `CFBooleanGetTypeID` rather than on cast success.
     * **No change was needed here.**
     *
     * **The integer rows closed; the float rows did not.** #1150 makes Swift return
     * `"1"` / `"0"` for `1` / `0` — agreeing with this side. But for `1.0` / `0.0`
     * Swift returns `"1"` / `"0"` as well, because `NSNumber.stringValue` drops the
     * `.0`, so those two only changed divergence class: from the Bool bridge to
     * exponent/float FORMATTING, which also covers `1e3` -> Swift `"1000"` vs
     * Kotlin `"1e3"`. That class is a formatting choice with no correct side; see
     * `JSONResponseParserParityTests` § "Known Kotlin-side literal-preservation
     * differences", and ADR-023 Stage 4 to decide the rule once for both engines.
     * The same applies to numbers nested inside [canonicalJson].
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
