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

  /// Fetches all "orphaned" simulations — runs whose source scenario was
  /// deleted, leaving `scenarioId` NULL (the FK is `ON DELETE SET NULL`
  /// since v7). Their display data lives in the `scenario*Snapshot` columns.
  /// Ordered newest-first.
  func fetchOrphaned() throws -> [SimulationRecord]

  /// Fetches all simulations with the given status, ordered newest-first.
  ///
  /// Used by the Home redesign's resume-from-paused surface (ADR-016 P3),
  /// which queries `.paused` runs; the P3 resume logic itself is not wired
  /// here.
  func fetchByStatus(_ status: SimulationStatus) throws -> [SimulationRecord]

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

  /// Deletes **all** simulation runs and reclaims freed disk pages.
  ///
  /// Child `turns` / `code_phase_events` rows cascade away via their
  /// `ON DELETE CASCADE` foreign keys. A post-purge `VACUUM` reclaims
  /// the freed pages (ADR-015 §4.1 — opt-in, post-purge only; the
  /// per-run ``delete(_:)`` deliberately skips `VACUUM`).
  func deleteAll() throws

  /// Returns the logical size of the database in bytes, computed as
  /// `page_count * page_size` (SQLite `PRAGMA`s).
  ///
  /// This is the SQLite-allocated size: it counts every page the file
  /// still holds (deletes free pages but only `VACUUM` shrinks the file)
  /// and excludes the transient rollback journal. It reads off a single
  /// connection, so it works for in-memory databases (tests) as well as
  /// the on-disk store — no file-path dependency, keeping the measure
  /// inside the Data layer.
  ///
  /// Powers the App layer's advisory growth cap (ADR-015 D1 / §3) — a
  /// non-deleting safety stop surfaced when the store grows large.
  func databaseByteCount() throws -> Int64
}

/// GRDB-backed implementation of `SimulationRepository`.
nonisolated public final class GRDBSimulationRepository: SimulationRepository, Sendable {
  private let dbWriter: any DatabaseWriter

  public init(dbWriter: any DatabaseWriter) {
    self.dbWriter = dbWriter
  }

  public func save(_ record: SimulationRecord) throws {
    try dbWriter.write { db in
      let mutable = record
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

  public func fetchOrphaned() throws -> [SimulationRecord] {
    try dbWriter.read { db in
      // `== nil` compiles to `IS NULL` in GRDB.
      try SimulationRecord
        .filter(Column("scenarioId") == nil)
        .order(Column("createdAt").desc)
        .fetchAll(db)
    }
  }

  public func fetchByStatus(_ status: SimulationStatus) throws -> [SimulationRecord] {
    try dbWriter.read { db in
      try SimulationRecord
        .filter(Column("status") == status.rawValue)
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

  public func deleteAll() throws {
    // `VACUUM` cannot run inside a transaction (SQLite), so use
    // `writeWithoutTransaction`. The `ON DELETE CASCADE` FKs on
    // `turns` / `code_phase_events` still fire under the enabled
    // `foreignKeysEnabled` config, so the bulk delete cascades.
    try dbWriter.writeWithoutTransaction { db in
      _ = try SimulationRecord.deleteAll(db)
      try db.execute(sql: "VACUUM")
    }
  }

  public func databaseByteCount() throws -> Int64 {
    try dbWriter.read { db in
      // `PRAGMA` results come back as rows; read each as a scalar. `?? 0`
      // is a safe floor: these PRAGMAs always return a row, but if one ever
      // didn't, reporting 0 fails soft (suppresses the advisory) rather than
      // throwing — matching the informational, never-deleting posture.
      let pageCount = try Int64.fetchOne(db, sql: "PRAGMA page_count") ?? 0
      let pageSize = try Int64.fetchOne(db, sql: "PRAGMA page_size") ?? 0
      return pageCount * pageSize
    }
  }
}
