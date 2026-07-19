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
 * **Vocabulary is intentionally minimal** ([Kind.StringKind] + [Kind.Choice])
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
         * speak → `statement`, choose → `action`, vote → `vote`, reflect →
         * `note`).
         *
         * `note` is present ahead of its phase: `PhaseType` does not yet carry
         * `REFLECT` (it lands with the mechanical mirrors). The ordering policy
         * is keyed on field names rather than phase types, so listing it early
         * is inert until a reflect schema appears — and omitting it would leave
         * this list diverged from Swift in the one type this PR exists to align.
         * Note that a mismatch here would NOT be caught by golden parity: the
         * fixtures pin encoded schemas, not [orderKeys]' policy.
         */
        public val knownPrimaryKeys: List<String> =
            listOf("statement", "action", "vote", "note")

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
         * field (if present in the schema) becomes [Kind.Choice] — a payload-free
         * marker. The option values themselves are deliberately not carried; see
         * [Kind.Choice] for why, and `ScenarioConventions` for where the model
         * actually learns them.
         */
        public fun from(phase: Phase): OutputSchema? {
            val raw = phase.outputSchema?.takeIf { it.isNotEmpty() } ?: return null
            val orderedNames = orderKeys(raw.keys.toList())
            val isChooseWithOptions =
                phase.type == PhaseType.CHOOSE && !phase.options.isNullOrEmpty()
            val fields = orderedNames.map { name ->
                if (isChooseWithOptions && name == "action") {
                    Field(name = name, kind = Kind.Choice)
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
     * **Aligned to Swift 2026-07-19** (ADR-023 §12 condition 1). Swift's
     * `OutputSchema.Kind` (`Pastura/Pastura/Models/OutputSchema.swift`) has exactly
     * two cases and the second carries **no payload** — `case string`, `case choice`.
     * This sealed class now matches: [Choice] replaced an `Enumeration(options:
     * List<String>)` that modelled a concept Swift had already retired.
     *
     * The absence of the payload is deliberate and documented at the Swift
     * declaration: enumerating choice options into the GBNF grammar crashed
     * llama.cpp's sampler on CJK / dynamic option values (#597, #599), so the
     * grammar constrains JSON *structure* only and the options are enforced at
     * runtime by `ChooseHandler` instead.
     *
     * **One difference remains by decision, not by omission: the tag form.**
     * kotlinx.serialization emits an internal discriminator (`{"type":"choice"}`)
     * where Swift's synthesized `Codable` emits an outer wrap (`{"choice":{}}`).
     * That is *not* closed here, because [OutputSchema] is never JSON-crossed in
     * production: it is built in memory by [from] and consumed directly by the
     * backends behind the §5.2 `LLMBackend` interface, which read the [Kind] cases
     * natively. Swift's `Codable` conformance exists for testability and
     * `Sendable`/`Equatable` consistency, not as a wire contract.
     *
     * Adding a hand-written `KSerializer` to close it would put a mechanism in
     * production whose stated reason — matching a wire contract — has no wire. The
     * parity test absorbs the difference instead, via `Canonicalizer` (Stage 3 lifts
     * the discriminator form into the outer-wrap form). `SwiftGoldenParityTests`
     * pins this class's *native* emission so the difference cannot drift unnoticed,
     * and `scripts/check-outputschema-no-serialization.py` fails the build if a
     * production serialization site ever appears — at which point this decision is
     * the thing to revisit, not the gate.
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
         * A **marker only**: the accepted literals are deliberately not carried
         * here (see the class KDoc above for the sampler-crash reason). The model
         * learns them from the prompt, and `ChooseHandler` enforces them at runtime.
         */
        @Serializable
        @SerialName("choice")
        public object Choice : Kind()
    }
}
