import Foundation
import GRDB

/// Database record type for the `scenarios` table.
///
/// Maps to the domain `Scenario` model. Stores the full YAML definition
/// as text for re-parsing, plus metadata for listing and preset detection.
nonisolated public struct ScenarioRecord: Codable, Sendable, Equatable,
  FetchableRecord, PersistableRecord {
  public static let databaseTableName = "scenarios"

  public var id: String
  public var name: String
  public var yamlDefinition: String
  public var isPreset: Bool
  public var createdAt: Date
  public var updatedAt: Date

  public init(
    id: String,
    name: String,
    yamlDefinition: String,
    isPreset: Bool,
    createdAt: Date,
    updatedAt: Date
  ) {
    self.id = id
    self.name = name
    self.yamlDefinition = yamlDefinition
    self.isPreset = isPreset
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}
