package com.pastura.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Structured representation of an LLM phase's expected JSON output shape.
 *
 * Threaded through `LLMService.generate(system, user, schema)` so each
 * backend can translate it to its native constrained-decoding mechanism
 * (llama.cpp: GBNF grammar, Ollama: `format:"json"`, Mock: recorded for
 * tests, future LiteRT-LM: JSON Schema adapter).
 *
 * **Field order is not alphabetical** — primary (user-visible) keys like
 * `statement` / `action` / `vote` precede secondary keys like
 * `inner_thought` / `reason`. This is load-bearing for the streaming UX:
 * `PartialOutputExtractor` gates visible content on seeing a recognised
 * primary key, so if grammar forced `inner_thought` first (as alphabetical
 * ordering would) the streaming row would stay empty for most of the stream.
 * See ADR-002 §12 and the PR #194 plan for the critic-driven rationale.
 *
 * **Vocabulary is intentionally minimal** ([Kind.StringKind] + [Kind.Enumeration])
 * — matches Pastura's actual scenario shape. Future backends needing richer
 * JSON Schema features (integers, booleans, regex formats) should add an
 * adapter, not extend [Kind].
 *
 * Kotlin port of `Pastura/Pastura/Models/OutputSchema.swift`.
 *
 * @property fields Ordered list of expected output fields. Order reflects the
 *                  primary-first policy (see type-level doc) and is the single
 *                  source of truth consumed by both `GBNFGrammarBuilder` and
 *                  `PromptBuilder` so grammar order and prompt example order
 *                  cannot drift.
 */
@Serializable
public data class OutputSchema(
    public val fields: List<Field>,
) {
    public companion object {
        /**
         * Known primary-output field names, in the order they should appear in
         * generated output. Matches the canonical fields advertised by
         * `ScenarioConventions.primaryField` (one canonical field per LLM phase:
         * speak → `statement`, choose → `action`, vote → `vote`).
         */
        public val knownPrimaryKeys: List<String> = listOf("statement", "action", "vote")

        /**
         * Known secondary-output field names (reasoning / justification). Emitted
         * after primary keys so the streaming row populates progressively.
         */
        public val knownSecondaryKeys: List<String> = listOf("inner_thought", "reason")

        /**
         * Build an [OutputSchema] from a [Phase]'s schema dictionary.
         *
         * @return `null` when the phase has no output schema (code phases) or an
         *         empty schema — callers should treat `null` as "no constrained
         *         decoding" and skip grammar injection.
         *
         * For [PhaseType.CHOOSE] phases with non-empty [Phase.options], the `action`
         * field (if present in the schema) becomes [Kind.Enumeration] carrying those
         * options — stronger than the runtime `validateAction` fallback.
         */
        public fun from(phase: Phase): OutputSchema? {
            val raw = phase.outputSchema?.takeIf { it.isNotEmpty() } ?: return null
            val orderedNames = orderKeys(raw.keys.toList())
            val isChooseWithOptions =
                phase.type == PhaseType.CHOOSE && !phase.options.isNullOrEmpty()
            val fields = orderedNames.map { name ->
                if (isChooseWithOptions && name == "action") {
                    // phase.options is guaranteed non-null here: isChooseWithOptions implies
                    // !phase.options.isNullOrEmpty(), so the smart-cast below is safe.
                    val options = checkNotNull(phase.options) { "options must be non-null when isChooseWithOptions" }
                    Field(name = name, kind = Kind.Enumeration(options))
                } else {
                    Field(name = name, kind = Kind.StringKind)
                }
            }
            return OutputSchema(fields = fields)
        }

        /**
         * Apply primary-first ordering policy to a raw list of field names.
         * Primary keys appear in [knownPrimaryKeys] order; secondary keys in
         * [knownSecondaryKeys] order; unknown keys sorted alphabetically at the end.
         * Keys not present in the input are skipped.
         *
         * `internal` to match Swift's `private static`. PR-B test harness +
         * future Engine port can promote if needed.
         */
        internal fun orderKeys(keys: List<String>): List<String> {
            val present = keys.toSet()
            val ordered = mutableListOf<String>()
            for (key in knownPrimaryKeys) {
                if (key in present) ordered += key
            }
            for (key in knownSecondaryKeys) {
                if (key in present) ordered += key
            }
            val knownSet = (knownPrimaryKeys + knownSecondaryKeys).toSet()
            val unknown = keys.filter { it !in knownSet }.sorted()
            ordered += unknown
            return ordered
        }
    }

    /**
     * A single named field in an [OutputSchema].
     *
     * @property name The field name expected in LLM JSON output (e.g., `"statement"`, `"action"`).
     * @property kind The kind of value this field accepts.
     */
    @Serializable
    public data class Field(
        public val name: String,
        public val kind: Kind,
    )

    /**
     * The kind of value a [Field] accepts.
     *
     * Intentionally narrow — Pastura's presets only ever express "a string" or
     * "one of these literal string options". Future scenario shapes should prefer
     * an adapter to JSON Schema over extending this sealed class.
     *
     * **Divergence from Swift — SEMANTIC, not merely a wire shape.**
     * Swift's `OutputSchema.Kind` (`Pastura/Pastura/Models/OutputSchema.swift`)
     * has exactly two cases, and the second carries **no payload**:
     * - `case string`
     * - `case choice` — a marker only
     *
     * The absence of the payload is deliberate and documented at that
     * declaration: enumerating choice options into the GBNF grammar crashed
     * llama.cpp's sampler on CJK / dynamic option values (#597, #599), so the
     * grammar constrains JSON *structure* only and the options are enforced at
     * runtime by `ChooseHandler` instead.
     *
     * The Kotlin port's [Enumeration] therefore carries a `List<String>` that
     * has no counterpart on the Swift side. An earlier version of this KDoc
     * described a Swift `.enumeration(["a","b"])` case that does not exist and
     * concluded "only the JSON tagging differs" — it does not.
     *
     * **This divergence is intentional and safe for the spike:** [OutputSchema] is
     * NOT JSON-roundtripped in production Pastura flows — it is constructed in-memory
     * by `OutputSchema.from(phase:)` and consumed directly by `LLMService` backends
     * (GBNF / Ollama-format / Mock) which translate the [Kind] cases natively, never
     * via JSON cross-language transfer. The `Codable` conformance in Swift exists for
     * testability + `Sendable`+`Equatable` consistency, NOT as a wire-shape contract.
     *
     * If PR-B's canonicalizer ever needs cross-language equivalence here, a
     * custom `KSerializer` is NOT sufficient on its own — aligning the wire
     * shape would still leave [Enumeration]'s options with nothing to map to.
     * Either Kotlin drops the payload to match `case choice`, or Swift gains
     * one and the #597 sampler constraint is revisited first.
     */
    @Serializable
    public sealed class Kind {
        /** Any string value (UTF-8, including CJK / emoji). */
        @Serializable
        @SerialName("string")
        public object StringKind : Kind()

        /**
         * One of a fixed set of string literals — used for [Phase.options] on
         * [PhaseType.CHOOSE] phases.
         *
         * @property options The accepted string literals.
         */
        @Serializable
        @SerialName("enumeration")
        public data class Enumeration(public val options: List<String>) : Kind()
    }
}
