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

  public init(name: String, description: String) {
    self.name = name
    self.description = description
  }
}
