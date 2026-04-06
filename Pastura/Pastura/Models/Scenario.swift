import Foundation

/// A complete scenario definition parsed from YAML.
///
/// This is the pure domain model representing a scenario's structure.
/// It does not include persistence metadata (id, isPreset, timestamps) —
/// those belong to `ScenarioRecord` in the Data layer.
///
/// Scenarios are parsed from YAML via `ScenarioLoader` in the Engine layer
/// using manual mapping (`Yams.load()` → `[String: Any]`).
nonisolated public struct Scenario: Codable, Sendable, Equatable {
  /// Unique identifier for the scenario (from YAML `id` field).
  public let id: String

  /// Human-readable scenario name.
  public let name: String

  /// Brief description of what this scenario simulates.
  public let description: String

  /// Expected number of agents. Must match `personas.count`.
  public let agentCount: Int

  /// Number of rounds to execute.
  public let rounds: Int

  /// Shared context injected into every agent's system prompt.
  public let context: String

  /// Agent persona definitions.
  public let personas: [Persona]

  /// Ordered list of phases executed each round.
  public let phases: [Phase]

  /// Scenario-specific data beyond the standard fields.
  ///
  /// Holds arbitrary top-level YAML fields that phase handlers access at runtime.
  /// For example, bokete's `topics` (string array) or word wolf's `words`
  /// (array of dictionaries). The `assign` phase references keys here via its
  /// `source` field. Empty if the scenario has no extra data.
  public let extraData: [String: AnyCodableValue]

  public init(
    id: String,
    name: String,
    description: String,
    agentCount: Int,
    rounds: Int,
    context: String,
    personas: [Persona],
    phases: [Phase],
    extraData: [String: AnyCodableValue] = [:]
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.agentCount = agentCount
    self.rounds = rounds
    self.context = context
    self.personas = personas
    self.phases = phases
    self.extraData = extraData
  }
}
