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
 */
@Serializable
public data class Persona(
    val name: String,
    val description: String,
)
