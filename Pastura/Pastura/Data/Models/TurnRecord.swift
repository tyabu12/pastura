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
  /// JSON-encoded `[Int]` identifying the phase's position in the scenario
  /// (top-level K → `"[K]"`, nested sub-phase N inside conditional K → `"[K,N]"`).
  /// `nil` for pre-v6 rows (legacy) where lineage wasn't captured. Consumers
  /// should read the typed `phasePath` accessor rather than decoding this
  /// string directly.
  public var phasePathJSON: String?
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
    phasePathJSON: String? = nil,
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
    self.phasePathJSON = phasePathJSON
    self.createdAt = createdAt
  }

  /// Typed view over `phasePathJSON`. Returns `nil` when the JSON is absent,
  /// empty, or fails to decode — consumers treat all three as "legacy /
  /// unknown path" and fall back to `phaseType`-only grouping.
  public var phasePath: [Int]? {
    guard let json = phasePathJSON, !json.isEmpty else { return nil }
    guard let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode([Int].self, from: data)
  }
}
