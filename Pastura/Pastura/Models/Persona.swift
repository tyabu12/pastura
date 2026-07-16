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
  /// **Secrecy invariant (load-bearing):** secret text must never enter the
  /// conversation log, `lastOutputs`, or any shared/`assigned_*` state
  /// variable — it exists ONLY in the owning agent's system prompt. Every
  /// ingest path normalizes empty to `nil`, so a non-nil value is non-empty.
  public let secret: String?

  public init(name: String, description: String, secret: String? = nil) {
    self.name = name
    self.description = description
    self.secret = secret
  }
}
