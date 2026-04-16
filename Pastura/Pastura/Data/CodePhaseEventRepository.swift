import Foundation
import GRDB

/// Repository for persisting and retrieving code-phase event records.
///
/// Mirrors `TurnRepository` in shape so callers can treat the two tables
/// symmetrically when merging events for export rendering.
nonisolated public protocol CodePhaseEventRepository: Sendable {
  /// Saves a single record.
  func save(_ record: CodePhaseEventRecord) throws

  /// Saves multiple records in a single transaction.
  func saveBatch(_ records: [CodePhaseEventRecord]) throws

  /// Fetches all records for a simulation, ordered by `sequenceNumber`
  /// ascending (with `createdAt` as a stable tiebreaker).
  func fetchBySimulationId(_ simulationId: String) throws -> [CodePhaseEventRecord]

  /// Fetches records for a specific simulation and round number, ordered by
  /// `sequenceNumber` ascending. Leverages `idx_code_phase_events_simulation_round`.
  func fetchBySimulationAndRound(
    _ simulationId: String, round: Int
  ) throws -> [CodePhaseEventRecord]

  /// Deletes all records for a given simulation.
  func deleteBySimulationId(_ simulationId: String) throws
}

/// GRDB-backed implementation of `CodePhaseEventRepository`.
nonisolated public final class GRDBCodePhaseEventRepository: CodePhaseEventRepository, Sendable {
  private let dbWriter: any DatabaseWriter

  public init(dbWriter: any DatabaseWriter) {
    self.dbWriter = dbWriter
  }

  public func save(_ record: CodePhaseEventRecord) throws {
    try dbWriter.write { db in
      try record.insert(db)
    }
  }

  public func saveBatch(_ records: [CodePhaseEventRecord]) throws {
    try dbWriter.write { db in
      for record in records {
        try record.insert(db)
      }
    }
  }

  public func fetchBySimulationId(
    _ simulationId: String
  ) throws -> [CodePhaseEventRecord] {
    try dbWriter.read { db in
      try CodePhaseEventRecord
        .filter(Column("simulationId") == simulationId)
        .order(Column("sequenceNumber").asc, Column("createdAt").asc)
        .fetchAll(db)
    }
  }

  public func fetchBySimulationAndRound(
    _ simulationId: String, round: Int
  ) throws -> [CodePhaseEventRecord] {
    try dbWriter.read { db in
      try CodePhaseEventRecord
        .filter(
          Column("simulationId") == simulationId
            && Column("roundNumber") == round
        )
        .order(Column("sequenceNumber").asc, Column("createdAt").asc)
        .fetchAll(db)
    }
  }

  public func deleteBySimulationId(_ simulationId: String) throws {
    try dbWriter.write { db in
      _ =
        try CodePhaseEventRecord
        .filter(Column("simulationId") == simulationId)
        .deleteAll(db)
    }
  }
}
