import Foundation

/// A pair of agents matched for a phase interaction (e.g., `choose` with round-robin).
///
/// `action1` and `action2` are populated by `ChooseHandler` after LLM inference
/// and read by `ScoreCalcHandler` and `SummarizeHandler` for scoring and display.
nonisolated public struct Pairing: Codable, Sendable, Equatable {
  /// The name of the first agent in the pair.
  public let agent1: String

  /// The name of the second agent in the pair.
  public let agent2: String

  /// The action chosen by the first agent (e.g., "cooperate", "betray").
  /// Populated by `ChooseHandler` after LLM inference; `nil` before execution.
  public var action1: String?

  /// The action chosen by the second agent.
  /// Populated by `ChooseHandler` after LLM inference; `nil` before execution.
  public var action2: String?

  public init(agent1: String, agent2: String, action1: String? = nil, action2: String? = nil) {
    self.agent1 = agent1
    self.agent2 = agent2
    self.action1 = action1
    self.action2 = action2
  }
}

/// Strategy for generating agent pairings in phases that require matchups.
nonisolated public enum PairingStrategy: String, Codable, Sendable {
  /// Each agent plays against every other agent exactly once per round.
  case roundRobin = "round_robin"
}
