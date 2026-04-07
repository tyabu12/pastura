import Foundation
import GRDB

/// Repository for persisting and retrieving turn records.
nonisolated public protocol TurnRepository: Sendable {
  /// Saves a single turn record.
  func save(_ record: TurnRecord) throws

  /// Saves multiple turn records in a single transaction.
  func saveBatch(_ records: [TurnRecord]) throws

  /// Fetches all turns for a simulation, ordered by `sequenceNumber` ascending
  /// with `createdAt` as fallback (for pre-migration rows where all are `0`).
  func fetchBySimulationId(_ simulationId: String) throws -> [TurnRecord]

  /// Fetches turns for a specific simulation and round number, ordered by
  /// `sequenceNumber` ascending with `createdAt` as fallback.
  /// Leverages the `idx_turns_simulation_round` index.
  func fetchBySimulationAndRound(
    _ simulationId: String, round: Int
  ) throws -> [TurnRecord]

  /// Deletes all turns for a given simulation.
  func deleteBySimulationId(_ simulationId: String) throws
}

/// GRDB-backed implementation of `TurnRepository`.
nonisolated public final class GRDBTurnRepository: TurnRepository, Sendable {
  private let dbWriter: any DatabaseWriter

  public init(dbWriter: any DatabaseWriter) {
    self.dbWriter = dbWriter
  }

  public func save(_ record: TurnRecord) throws {
    try dbWriter.write { db in
      var mutable = record
      try mutable.insert(db)
    }
  }

  public func saveBatch(_ records: [TurnRecord]) throws {
    try dbWriter.write { db in
      for var record in records {
        try record.insert(db)
      }
    }
  }

  public func fetchBySimulationId(_ simulationId: String) throws -> [TurnRecord] {
    try dbWriter.read { db in
      try TurnRecord
        .filter(Column("simulationId") == simulationId)
        .order(Column("sequenceNumber").asc, Column("createdAt").asc)
        .fetchAll(db)
    }
  }

  public func fetchBySimulationAndRound(
    _ simulationId: String, round: Int
  ) throws -> [TurnRecord] {
    try dbWriter.read { db in
      try TurnRecord
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
        try TurnRecord
        .filter(Column("simulationId") == simulationId)
        .deleteAll(db)
    }
  }
}
