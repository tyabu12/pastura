import Foundation

/// The complete mutable state of a running simulation.
///
/// `SimulationState` is `Codable` from day one — it is serialized to JSON
/// for pause/resume persistence in the `simulations.stateJSON` DB column.
/// Agent state (scores, elimination) lives here rather than in a separate
/// agents table (see ADR-001 §4).
nonisolated public struct SimulationState: Codable, Sendable, Equatable {
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

  /// Per-event-variable set of already-drawn event strings, tracked only for
  /// `event_inject` phases opted into `no_repeat` (draw-without-replacement).
  /// Keyed by the event variable name (`current_event` or the phase's `as:`);
  /// the value is the set of chosen `text` values drawn so far this run.
  /// Persisted so a pause/resume mid-run preserves the no-repeat pool. Empty
  /// for every other scenario. See #1006 and ``Phase/noRepeat``.
  public var drawnEvents: [String: Set<String>]

  public init(
    scores: [String: Int] = [:],
    eliminated: [String: Bool] = [:],
    conversationLog: [ConversationEntry] = [],
    lastOutputs: [String: TurnOutput] = [:],
    voteResults: [String: Int] = [:],
    pairings: [Pairing] = [],
    variables: [String: String] = [:],
    currentRound: Int = 0,
    drawnEvents: [String: Set<String>] = [:]
  ) {
    self.scores = scores
    self.eliminated = eliminated
    self.conversationLog = conversationLog
    self.lastOutputs = lastOutputs
    self.voteResults = voteResults
    self.pairings = pairings
    self.variables = variables
    self.currentRound = currentRound
    self.drawnEvents = drawnEvents
  }

  /// Custom decoder so a `drawnEvents`-less `stateJSON` — any run persisted
  /// before #1006 shipped — still resumes instead of throwing `keyNotFound`.
  /// Pause/resume across an app update is a real path (ADR-003 background
  /// execution, ADR-021 D8 resume), so the new field must decode leniently.
  ///
  /// Only `drawnEvents` is optional-on-decode; the eight original fields keep
  /// required `decode` so a genuinely-corrupt blob still fails loudly rather
  /// than silently resuming with zeroed state. Encoding stays synthesized
  /// (the synthesized `CodingKeys` covers all nine fields, so the round-trip
  /// is symmetric).
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    scores = try container.decode([String: Int].self, forKey: .scores)
    eliminated = try container.decode([String: Bool].self, forKey: .eliminated)
    conversationLog = try container.decode([ConversationEntry].self, forKey: .conversationLog)
    lastOutputs = try container.decode([String: TurnOutput].self, forKey: .lastOutputs)
    voteResults = try container.decode([String: Int].self, forKey: .voteResults)
    pairings = try container.decode([Pairing].self, forKey: .pairings)
    variables = try container.decode([String: String].self, forKey: .variables)
    currentRound = try container.decode(Int.self, forKey: .currentRound)
    drawnEvents =
      try container.decodeIfPresent([String: Set<String>].self, forKey: .drawnEvents) ?? [:]
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
