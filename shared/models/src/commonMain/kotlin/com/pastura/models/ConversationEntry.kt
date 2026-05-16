package com.pastura.models

import kotlinx.serialization.Serializable

/**
 * A single entry in the simulation's conversation log.
 *
 * The conversation log accumulates entries as the simulation progresses.
 * When building LLM prompts, the Engine trims to the most recent N entries
 * to prevent context overflow. The full log is preserved in the DB via `TurnRecord`.
 *
 * Kotlin port of `Pastura/Pastura/Models/ConversationEntry.swift`.
 * Wire shape: `{"agentName": "...", "content": "...", "phaseType": "speak_all", "round": 1}`
 * (camelCase per kotlinx.serialization default; matches Swift Codable default).
 *
 * @property agentName The name of the agent who produced this entry.
 * @property content   The visible content of this entry (e.g., the agent's spoken statement).
 * @property phaseType The phase type during which this entry was produced.
 * @property round     The round number (1-based) when this entry was produced.
 */
@Serializable
public data class ConversationEntry(
    public val agentName: String,
    public val content: String,
    public val phaseType: PhaseType,
    public val round: Int,
)
