import Foundation
import GRDB

/// Database record type for the `code_phase_events` table.
///
/// Each record represents one code-phase result (elimination, score update,
/// summary, vote tally, pairing outcome, or assignment) persisted as
/// `CodePhaseEventPayload` JSON. Unlike `TurnRecord`, these rows are not
/// tied to an agent's LLM output — they capture deterministic outcomes
/// emitted by phase handlers so exports and analyses can reconstruct the
/// round-by-round narrative without replaying events.
///
/// `sequenceNumber` is shared with `TurnRecord` within a simulation:
/// `SimulationViewModel` increments a single counter per event and routes
/// the record to the appropriate table. This guarantees a strict total
/// order across both tables for merge-sort at export time.
nonisolated public struct CodePhaseEventRecord: Codable, Sendable, Equatable,
  FetchableRecord, PersistableRecord {
  public static let databaseTableName = "code_phase_events"

  public var id: String
  public var simulationId: String
  public var roundNumber: Int
  /// The originating phase type (e.g., "eliminate", "score_calc", "summarize",
  /// "vote", "choose", "assign"). Stored as raw string for forward compat.
  public var phaseType: String
  /// Canonical ordering key, shared with `TurnRecord.sequenceNumber`
  /// across the same `simulationId`.
  public var sequenceNumber: Int
  /// Serialized `CodePhaseEventPayload` as JSON.
  public var payloadJSON: String
  public var createdAt: Date

  public init(
    id: String,
    simulationId: String,
    roundNumber: Int,
    phaseType: String,
    sequenceNumber: Int,
    payloadJSON: String,
    createdAt: Date
  ) {
    self.id = id
    self.simulationId = simulationId
    self.roundNumber = roundNumber
    self.phaseType = phaseType
    self.sequenceNumber = sequenceNumber
    self.payloadJSON = payloadJSON
    self.createdAt = createdAt
  }
}
