import Foundation
import GRDB

/// Database record type for the `turns` table.
///
/// Each record represents one agent's output from a single phase execution.
/// `rawOutput` stores the unfiltered LLM response; `parsedOutputJSON` stores
/// the parsed `TurnOutput` fields as JSON. `agentName` is `nil` for code
/// phases (e.g., `score_calc`, `eliminate`).
nonisolated public struct TurnRecord: Codable, Sendable, Equatable,
  FetchableRecord, PersistableRecord {
  public static let databaseTableName = "turns"

  public var id: String
  public var simulationId: String
  public var roundNumber: Int
  public var phaseType: String
  /// `nil` for code phases (score_calc, eliminate, assign, summarize).
  public var agentName: String?
  /// Unfiltered LLM response. ContentFilter is applied in the App layer.
  public var rawOutput: String
  /// Parsed `TurnOutput.fields` serialized as JSON.
  public var parsedOutputJSON: String
  /// Monotonically increasing per simulation — the canonical ordering key.
  /// Pre-migration rows default to `0` and fall back to `createdAt` ordering.
  public var sequenceNumber: Int
  public var createdAt: Date

  public init(
    id: String,
    simulationId: String,
    roundNumber: Int,
    phaseType: String,
    agentName: String?,
    rawOutput: String,
    parsedOutputJSON: String,
    sequenceNumber: Int = 0,
    createdAt: Date
  ) {
    self.id = id
    self.simulationId = simulationId
    self.roundNumber = roundNumber
    self.phaseType = phaseType
    self.agentName = agentName
    self.rawOutput = rawOutput
    self.parsedOutputJSON = parsedOutputJSON
    self.sequenceNumber = sequenceNumber
    self.createdAt = createdAt
  }
}
