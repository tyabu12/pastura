import Foundation

/// An agent's persona definition within a scenario.
///
/// Personas define the character traits and behavior patterns for each agent.
/// The `description` field typically follows the 【立場】【目的】 pattern
/// for consistent LLM persona injection.
nonisolated public struct Persona: Codable, Sendable, Equatable {
  /// The display name of this agent.
  public let name: String

  /// Character description injected into the LLM system prompt.
  public let description: String

  /// Hidden agenda known only to this agent (and the viewer).
  ///
  /// Injected into the owning agent's system prompt as a private section and
  /// never shown to other agents. `nil` means the persona has no secret.
  ///
  /// **Secrecy invariant (load-bearing).** The engine never copies this text
  /// into the conversation log, `lastOutputs`, or a shared / `assigned_*` state
  /// variable — it is written only into the owning agent's system prompt.
  ///
  /// Note what this does *not* claim: the prompt deliberately licenses the model
  /// to reference the secret in its `inner_thought`, and the speak handlers
  /// store the whole `TurnOutput` (inner_thought included) into `lastOutputs`.
  /// So secret-*derived* text does reach `lastOutputs`. It stays private only
  /// because no consumer surfaces another agent's non-primary fields — today
  /// they read `.vote`, `.action`, or the agent's own main field. Preserve that
  /// when adding a `lastOutputs` reader.
  ///
  /// Every ingest path normalizes empty (after trimming) to `nil`, so a non-nil
  /// value is non-empty.
  public let secret: String?

  public init(name: String, description: String, secret: String? = nil) {
    self.name = name
    self.description = description
    self.secret = secret
  }
}
