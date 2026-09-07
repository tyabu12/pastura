package com.pastura.models

import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient

/**
 * Parsed output from a single LLM inference turn.
 *
 * Wraps a `Map<String, String>` with typed accessors for common fields.
 * All values are normalized to `String` by `JSONResponseParser` regardless of
 * the original JSON type.
 *
 * Kotlin port of `Pastura/Pastura/Models/TurnOutput.swift`.
 */
@Serializable
public data class TurnOutput(
    /** The raw parsed fields from the LLM's JSON response. */
    public val fields: Map<String, String>,
) {
    /**
     * The original pre-cleanup LLM text, kept so the Data layer can persist it in
     * the `TurnRecord.rawOutput` audit column. Populated by `JSONResponseParser`;
     * `null` for synthetic outputs built straight from [fields] (tests, replay).
     *
     * Declared in the class body rather than the primary constructor, so — exactly
     * like the Swift twin, which omits it from `CodingKeys` and from `==` — it is
     * excluded from [equals]/[hashCode] and from the serialized wire shape
     * (`@Transient`). Provenance metadata is not part of the domain value.
     *
     * Being outside the constructor also puts it **outside [copy]**: a `copy()`
     * returns an output with `rawText == null`, so re-set it explicitly whenever
     * a derived output must keep the provenance (see `WhisperHandler`).
     *
     * Written only before the owning event is emitted, never after — that
     * write-once discipline is what keeps the Swift side's
     * `@retroactive @unchecked Sendable` on `SimulationEvent` sound despite this
     * being a `var` (`.claude/rules/kmp-interop.md` Pattern 1).
     *
     * `public var` rather than a narrowed setter because `shared/engine`, which
     * writes it, is a separate Gradle module — `internal set` cannot reach it.
     */
    @Transient
    public var rawText: String? = null

    /** Agent's spoken statement (canonical primary field for speak phases). */
    public val statement: String? get() = fields["statement"]

    /** Agent's vote target name (canonical primary field for `.vote` phases). */
    public val vote: String? get() = fields["vote"]

    /**
     * Agent's chosen action (canonical primary field for `.choose` phases —
     * e.g., "cooperate" or "betray").
     */
    public val action: String? get() = fields["action"]

    /** Agent's private inner thought (hidden by default in UI, revealed on tap). */
    public val innerThought: String? get() = fields["inner_thought"]

    /** Reason for a vote or decision. */
    public val reason: String? get() = fields["reason"]

    /**
     * Returns the value for the given key, or throws if the key is missing or empty.
     *
     * `@Throws` is load-bearing at the K/N boundary, and the `@throws` line below
     * does not substitute for it (`.claude/rules/kmp-interop.md` Pattern 5).
     *
     * @param key The field key to look up.
     * @return The non-empty value for the key.
     * @throws [TurnOutputError.MissingField] if the key is absent or empty.
     */
    @Throws(TurnOutputError::class)
    public fun require(key: String): String {
        val value = fields[key]
        if (value.isNullOrEmpty()) throw TurnOutputError.MissingField(key)
        return value
    }

    /**
     * Phase-aware extraction of the "primary" display text — the string
     * that represents an agent's main visible action for the phase type.
     *
     * [PhaseType.VOTE] returns a composite `→ <voted> (<reason>)` string so the
     * markdown export and live UI surface the reason inline.
     * Speak / choose phases return the value at [ScenarioConventions.primaryField].
     * Code phases have no LLM output and return `null`.
     *
     * @param phaseType The phase type that produced this output.
     * @return The primary display text, or `null` for code phases or missing fields.
     */
    public fun primaryText(phaseType: PhaseType): String? {
        if (phaseType == PhaseType.VOTE) {
            val voted = vote ?: return null
            val reasonPart = reason?.let { " ($it)" } ?: ""
            return "→ $voted$reasonPart"
        }
        val key = ScenarioConventions.primaryField(phaseType) ?: return null
        return fields[key]
    }
}

/**
 * Errors related to accessing [TurnOutput] fields.
 *
 * Kotlin port of `Pastura/Pastura/Models/TurnOutput.swift:TurnOutputError`.
 * Extends [Exception] (Kotlin commonMain stdlib) for idiom alignment —
 * `RuntimeException` is not in commonMain.
 */
public sealed class TurnOutputError(message: String) : Exception(message) {
    /**
     * A required field was missing or empty in the LLM response.
     *
     * @property key The field key that was absent or empty.
     */
    public data class MissingField(public val key: String) : TurnOutputError("Missing field: $key")
}
