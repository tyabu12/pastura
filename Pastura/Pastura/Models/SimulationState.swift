import Foundation

/// The complete mutable state of a running simulation.
///
/// `SimulationState` is `Codable` from day one — it is serialized to JSON
/// for pause/resume persistence in the `simulations.stateJSON` DB column.
/// Agent state (scores, elimination) lives here rather than in a separate
/// agents table (see ADR-001 §4).
public struct SimulationState: Codable, Sendable, Equatable {
  /// Current scores indexed by agent name.
  public var scores: [String: Int]

  /// Elimination status indexed by agent name. `true` means eliminated.
  public var eliminated: [String: Bool]

  /// Accumulated conversation log. Engine trims to recent entries for prompts;
  /// full log is preserved in DB via TurnRecord.
  public var conversationLog: [ConversationEntry]

  /// Most recent output per agent, indexed by agent name.
  /// Used for template variable expansion in subsequent phases.
  public var lastOutputs: [String: TurnOutput]

  /// Vote tallies from the most recent vote phase, indexed by agent name.
  public var voteResults: [String: Int]

  /// Current pairings for choose phases with round-robin strategy.
  public var pairings: [Pairing]

  /// Arbitrary key-value variables for template expansion
  /// (e.g., `assigned_topic` from assign phases).
  public var variables: [String: String]

  /// The current round number (1-based). Updated by SimulationRunner.
  public var currentRound: Int

  public init(
    scores: [String: Int] = [:],
    eliminated: [String: Bool] = [:],
    conversationLog: [ConversationEntry] = [],
    lastOutputs: [String: TurnOutput] = [:],
    voteResults: [String: Int] = [:],
    pairings: [Pairing] = [],
    variables: [String: String] = [:],
    currentRound: Int = 0
  ) {
    self.scores = scores
    self.eliminated = eliminated
    self.conversationLog = conversationLog
    self.lastOutputs = lastOutputs
    self.voteResults = voteResults
    self.pairings = pairings
    self.variables = variables
    self.currentRound = currentRound
  }

  /// Creates an initial state for the given scenario with all agents at score 0.
  public static func initial(for scenario: Scenario) -> SimulationState {
    let agentNames = scenario.personas.map(\.name)
    return SimulationState(
      scores: Dictionary(uniqueKeysWithValues: agentNames.map { ($0, 0) }),
      eliminated: Dictionary(uniqueKeysWithValues: agentNames.map { ($0, false) })
    )
  }
}
