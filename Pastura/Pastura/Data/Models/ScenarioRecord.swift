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
/// `sourceType` is `"gallery"` (Shared Scenarios). `NULL` means user-created or
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

  /// Provenance tag. `"gallery"` for Shared Scenarios imports, `nil` for local scenarios.
  public var sourceType: String?

  /// Canonical id in the source system (e.g. the original gallery scenario id).
  ///
  /// Distinct from `id` so that future namespacing schemes or multi-source
  /// provenance won't require touching the primary key.
  public var sourceId: String?

  /// SHA256 hex of the YAML at the moment it was fetched. `nil` for local scenarios.
  public var sourceHash: String?

  /// ISO 639-1 lowercase language code (`"ja"` / `"en"`) denormalized from the
  /// YAML's mandatory top-level `language:` field (ADR-010 D1).
  ///
  /// Stored as a column so cross-language variant grouping (Home / Past
  /// Results, ADR-010 D4/D6) can collapse by `sourceId` + language without
  /// loading and parsing `yamlDefinition` for every row. Populated at the
  /// persisted construction sites from `Scenario.language`. `nil` for rows
  /// written before the v8 column (not backfilled — ADR-010 D11: reinstall,
  /// don't migrate) or transient/DEBUG records never round-tripped through the
  /// repository — consumers fall back to `"ja"` (matching
  /// ``ScenarioYAMLLanguage``'s convention).
  public var language: String?

  public init(
    id: String,
    name: String,
    yamlDefinition: String,
    isPreset: Bool,
    createdAt: Date,
    updatedAt: Date,
    sourceType: String? = nil,
    sourceId: String? = nil,
    sourceHash: String? = nil,
    language: String? = nil
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
    self.language = language
  }
}
