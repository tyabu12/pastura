import Foundation
import GRDB

/// Repository for persisting and retrieving simulation records.
nonisolated public protocol SimulationRepository: Sendable {
  /// Saves a simulation record (full-row upsert).
  /// Inserts if new; replaces **all** columns if the ID already exists.
  func save(_ record: SimulationRecord) throws

  /// Fetches a simulation by its unique ID. Returns `nil` if not found.
  func fetchById(_ id: String) throws -> SimulationRecord?

  /// Fetches all simulations for a given scenario.
  func fetchByScenarioId(_ scenarioId: String) throws -> [SimulationRecord]

  /// Updates state-related fields (stateJSON, currentRound, currentPhaseIndex)
  /// without touching other columns. Used for pause/resume.
  ///
  /// - Throws: `DataError.recordNotFound` if no record with the given ID exists.
  func updateState(
    _ id: String, stateJSON: String,
    currentRound: Int, currentPhaseIndex: Int
  ) throws

  /// Updates only the status field.
  ///
  /// - Throws: `DataError.recordNotFound` if no record with the given ID exists.
  func updateStatus(_ id: String, status: SimulationStatus) throws

  /// Deletes a simulation by ID. No-op if the record does not exist.
  func delete(_ id: String) throws
}

/// GRDB-backed implementation of `SimulationRepository`.
nonisolated public final class GRDBSimulationRepository: SimulationRepository, Sendable {
  private let dbWriter: any DatabaseWriter

  public init(dbWriter: any DatabaseWriter) {
    self.dbWriter = dbWriter
  }

  public func save(_ record: SimulationRecord) throws {
    try dbWriter.write { db in
      var mutable = record
      try mutable.save(db)
    }
  }

  public func fetchById(_ id: String) throws -> SimulationRecord? {
    try dbWriter.read { db in
      try SimulationRecord.fetchOne(db, key: id)
    }
  }

  public func fetchByScenarioId(_ scenarioId: String) throws -> [SimulationRecord] {
    try dbWriter.read { db in
      try SimulationRecord
        .filter(Column("scenarioId") == scenarioId)
        .order(Column("createdAt").desc)
        .fetchAll(db)
    }
  }

  public func updateState(
    _ id: String, stateJSON: String,
    currentRound: Int, currentPhaseIndex: Int
  ) throws {
    try dbWriter.write { db in
      guard var record = try SimulationRecord.fetchOne(db, key: id) else {
        throw DataError.recordNotFound(type: "SimulationRecord", id: id)
      }
      record.stateJSON = stateJSON
      record.currentRound = currentRound
      record.currentPhaseIndex = currentPhaseIndex
      record.updatedAt = Date()
      try record.update(db)
    }
  }

  public func updateStatus(_ id: String, status: SimulationStatus) throws {
    try dbWriter.write { db in
      guard var record = try SimulationRecord.fetchOne(db, key: id) else {
        throw DataError.recordNotFound(type: "SimulationRecord", id: id)
      }
      record.status = status.rawValue
      record.updatedAt = Date()
      try record.update(db)
    }
  }

  public func delete(_ id: String) throws {
    try dbWriter.write { db in
      _ = try SimulationRecord.deleteOne(db, key: id)
    }
  }
}
