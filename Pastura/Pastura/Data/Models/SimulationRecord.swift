import Foundation
import GRDB

/// Database record type for the `simulations` table.
///
/// Stores simulation execution state including the serialized `SimulationState`
/// as JSON text. The `status` field uses raw `String` values matching
/// `SimulationStatus.rawValue`; use the `simulationStatus` convenience
/// property for type-safe access.
nonisolated public struct SimulationRecord: Codable, Sendable, Equatable,
  FetchableRecord, PersistableRecord {
  public static let databaseTableName = "simulations"

  public var id: String
  /// Foreign key into `scenarios`. Nullable since v7: the FK is
  /// `ON DELETE SET NULL`, so removing a scenario orphans its runs (sets
  /// this to nil) rather than cascade-deleting them — past results survive
  /// scenario deletion. Read paths fall back to the `scenario*Snapshot`
  /// fields below when this is nil.
  public var scenarioId: String?
  public var status: String
  public var currentRound: Int
  public var currentPhaseIndex: Int
  /// Serialized `SimulationState` (JSON via `Codable`).
  public var stateJSON: String
  /// Optional runtime parameter overrides (JSON).
  public var configJSON: String?
  public var createdAt: Date
  public var updatedAt: Date
  /// Human-readable label for the LLM model that ran this simulation (e.g.
  /// `"Gemma 4 E2B (Q4_K_M)"`). Nil for rows created before the v3 migration.
  public var modelIdentifier: String?
  /// Human-readable label for the LLM backend runtime (e.g. `"llama.cpp"`,
  /// `"Ollama"`). Nil for rows created before the v3 migration.
  public var llmBackend: String?
  /// Snapshot of the source scenario's raw YAML, captured at run-creation
  /// time. Keeps past-results / export self-contained so editing or deleting
  /// the source scenario does not drift or destroy historical runs. Nil for
  /// rows created before the v7 migration (those fall back to the live
  /// scenario via `scenarioId` while it still exists).
  public var scenarioYamlSnapshot: String?
  /// Snapshot of the source scenario's display name, captured at
  /// run-creation time. Used as the section/label for orphaned runs whose
  /// `scenarioId` is nil. Nil for rows created before the v7 migration.
  public var scenarioNameSnapshot: String?

  public init(
    id: String,
    scenarioId: String?,
    status: String,
    currentRound: Int,
    currentPhaseIndex: Int,
    stateJSON: String,
    configJSON: String?,
    createdAt: Date,
    updatedAt: Date,
    modelIdentifier: String? = nil,
    llmBackend: String? = nil,
    scenarioYamlSnapshot: String? = nil,
    scenarioNameSnapshot: String? = nil
  ) {
    self.id = id
    self.scenarioId = scenarioId
    self.status = status
    self.currentRound = currentRound
    self.currentPhaseIndex = currentPhaseIndex
    self.stateJSON = stateJSON
    self.configJSON = configJSON
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.modelIdentifier = modelIdentifier
    self.llmBackend = llmBackend
    self.scenarioYamlSnapshot = scenarioYamlSnapshot
    self.scenarioNameSnapshot = scenarioNameSnapshot
  }

  /// Type-safe accessor for the simulation status.
  public var simulationStatus: SimulationStatus? {
    SimulationStatus(rawValue: status)
  }
}
