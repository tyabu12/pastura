import Foundation
import GRDB

// Split out of `SimulationRepository.swift` to keep it under the
// file_length cap (#992). `nonisolated` on the extension is load-bearing:
// `GRDBSimulationRepository` is a `nonisolated` Data-layer type, but a
// plain sibling-file extension inherits the project's default MainActor
// isolation and would break `nonisolated` callers (see
// `.claude/rules/swift-isolation.md` Pattern 3).
//
// Single-column, read-modify-write update mutators. Each fetches the full
// row, mutates one field + `updatedAt`, and writes it back — throwing
// `DataError.recordNotFound` when the id is absent.
nonisolated extension GRDBSimulationRepository {
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

  public func updateDegradedTurnCount(_ id: String, count: Int) throws {
    try dbWriter.write { db in
      guard var record = try SimulationRecord.fetchOne(db, key: id) else {
        throw DataError.recordNotFound(type: "SimulationRecord", id: id)
      }
      record.degradedTurnCount = count
      record.updatedAt = Date()
      try record.update(db)
    }
  }
}
