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

  /// Optional topic data referenced by `assign` phases via `source` field.
  /// For example, bokete scenario uses this for photo descriptions.
  public let topics: [String]?

  public init(
    id: String,
    name: String,
    description: String,
    agentCount: Int,
    rounds: Int,
    context: String,
    personas: [Persona],
    phases: [Phase],
    topics: [String]? = nil
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.agentCount = agentCount
    self.rounds = rounds
    self.context = context
    self.personas = personas
    self.phases = phases
    self.topics = topics
  }
}
