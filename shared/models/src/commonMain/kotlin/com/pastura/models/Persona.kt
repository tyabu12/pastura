package com.pastura.models

import kotlinx.serialization.Serializable

/**
 * An agent's persona definition within a scenario.
 *
 * Personas define the character traits and behavior patterns for each agent.
 * The `description` field typically follows the 【立場】【目的】 pattern
 * (Japanese: Position / Goal) for consistent LLM persona injection — see
 * `Pastura/Pastura/Models/Persona.swift:5-7` for the convention note.
 *
 * Kotlin port of `Persona.swift` (Issue #220 W1 pilot, "1 trivial data class
 * Models type"). Swift original is `nonisolated public struct Persona:
 * Codable, Sendable, Equatable`; Kotlin `data class` auto-synthesizes
 * equals/hashCode/toString/copy and `@Serializable` adds the
 * kotlinx.serialization codec.
 *
 * **Scope of this pilot:** Kotlin-side JSON encode/decode roundtrip only.
 * Full Swift↔Kotlin canonicalizer (H2 in #220) is deferred to W2/W3.
 *
 * @property name        The display name of this agent.
 * @property description Character description injected into the LLM system prompt.
 * @property secret      Hidden agenda known only to this agent (and the viewer).
 */
@Serializable
public data class Persona(
    val name: String,
    val description: String,
    /**
     * Hidden agenda known only to this agent (and the viewer).
     *
     * Injected into the owning agent's system prompt as a private section and
     * never shown to other agents. `null` means the persona has no secret.
     *
     * **Secrecy invariant (load-bearing).** The engine never copies this text
     * into the conversation log, `lastOutputs`, or a shared / `assigned_*`
     * state variable — it is written only into the owning agent's system
     * prompt.
     *
     * Note what this does *not* claim: the prompt deliberately licenses the
     * model to reference the secret in its `inner_thought`, and the speak
     * handlers store the whole [TurnOutput] (inner_thought included) into
     * `lastOutputs`. So secret-*derived* text does reach `lastOutputs`. It
     * stays private only because no consumer surfaces another agent's
     * non-primary fields — today they read `vote`, `action`, or the agent's
     * own main field. Preserve that when adding a `lastOutputs` reader.
     *
     * Both Swift ingest paths — the YAML loader and the editor boundary —
     * normalize empty (after trimming) to `null`, so in practice a non-null
     * value is non-empty. That is a convention those paths keep, not an
     * invariant this type enforces. **No Kotlin ingest path exists yet**
     * (`ScenarioLoader` is Stage 3, ADR-023 §4); preserve the convention when
     * one lands.
     *
     * Ported for the ADR-023 §6 Stage-2 gate slice: [Persona] reaches the
     * ported `PromptBuilder.buildSystemPrompt` on the speak_all path, so the
     * field is a slice-path prerequisite rather than Stage-3 freight.
     * Swift original: `Pastura/Pastura/Models/Persona.swift`.
     */
    val secret: String? = null,
)
