import Foundation

/// A single entry in the simulation's conversation log.
///
/// The conversation log accumulates entries as the simulation progresses.
/// When building LLM prompts, the Engine trims to the most recent N entries
/// to prevent context overflow. The full log is preserved in the DB via `TurnRecord`.
public struct ConversationEntry: Codable, Sendable, Equatable {
  /// The name of the agent who produced this entry.
  public let agentName: String

  /// The visible content of this entry (e.g., the agent's spoken statement).
  public let content: String

  /// The phase type during which this entry was produced.
  public let phaseType: PhaseType

  /// The round number (1-based) when this entry was produced.
  public let round: Int

  public init(agentName: String, content: String, phaseType: PhaseType, round: Int) {
    self.agentName = agentName
    self.content = content
    self.phaseType = phaseType
    self.round = round
  }
}
