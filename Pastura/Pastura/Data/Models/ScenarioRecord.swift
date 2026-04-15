import Foundation
import GRDB

/// Database record type for the `scenarios` table.
///
/// Maps to the domain `Scenario` model. Stores the full YAML definition
/// as text for re-parsing, plus metadata for listing and preset detection.
///
/// ### Source provenance
///
/// `sourceType` / `sourceId` / `sourceHash` record where a scenario came from
/// when it is not locally authored. In MVP, the only non-nil value for
/// `sourceType` is `"gallery"` (Share Board). `NULL` means user-created or
/// a bundled preset. `sourceHash` is the SHA256 of the YAML at fetch time,
/// used for update detection against the remote gallery.
nonisolated public struct ScenarioRecord: Codable, Sendable, Equatable,
  FetchableRecord, PersistableRecord {
  public static let databaseTableName = "scenarios"

  public var id: String
  public var name: String
  public var yamlDefinition: String
  public var isPreset: Bool
  public var createdAt: Date
  public var updatedAt: Date

  /// Provenance tag. `"gallery"` for Share Board imports, `nil` for local scenarios.
  public var sourceType: String?

  /// Canonical id in the source system (e.g. the original gallery scenario id).
  ///
  /// Distinct from `id` so that future namespacing schemes or multi-source
  /// provenance won't require touching the primary key.
  public var sourceId: String?

  /// SHA256 hex of the YAML at the moment it was fetched. `nil` for local scenarios.
  public var sourceHash: String?

  public init(
    id: String,
    name: String,
    yamlDefinition: String,
    isPreset: Bool,
    createdAt: Date,
    updatedAt: Date,
    sourceType: String? = nil,
    sourceId: String? = nil,
    sourceHash: String? = nil
  ) {
    self.id = id
    self.name = name
    self.yamlDefinition = yamlDefinition
    self.isPreset = isPreset
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.sourceType = sourceType
    self.sourceId = sourceId
    self.sourceHash = sourceHash
  }
}
