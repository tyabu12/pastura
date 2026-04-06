import Foundation

/// A pair of agents matched for a phase interaction (e.g., `choose` with round-robin).
nonisolated public struct Pairing: Codable, Sendable, Equatable {
  /// The name of the first agent in the pair.
  public let agent1: String

  /// The name of the second agent in the pair.
  public let agent2: String

  public init(agent1: String, agent2: String) {
    self.agent1 = agent1
    self.agent2 = agent2
  }
}

/// Strategy for generating agent pairings in phases that require matchups.
nonisolated public enum PairingStrategy: String, Codable, Sendable {
  /// Each agent plays against every other agent exactly once per round.
  case roundRobin = "round_robin"
}
