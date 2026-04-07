import Foundation
import GRDB

/// Repository for persisting and retrieving scenario records.
nonisolated public protocol ScenarioRepository: Sendable {
  /// Saves a scenario record (full-row upsert).
  /// Inserts if new; replaces **all** columns if the ID already exists.
  func save(_ record: ScenarioRecord) throws

  /// Fetches a scenario by its unique ID. Returns `nil` if not found.
  func fetchById(_ id: String) throws -> ScenarioRecord?

  /// Fetches all scenarios.
  func fetchAll() throws -> [ScenarioRecord]

  /// Fetches only preset (bundled) scenarios.
  func fetchPresets() throws -> [ScenarioRecord]

  /// Deletes a scenario by ID. No-op if the record does not exist.
  func delete(_ id: String) throws
}

/// GRDB-backed implementation of `ScenarioRepository`.
nonisolated public final class GRDBScenarioRepository: ScenarioRepository, Sendable {
  private let dbWriter: any DatabaseWriter

  public init(dbWriter: any DatabaseWriter) {
    self.dbWriter = dbWriter
  }

  public func save(_ record: ScenarioRecord) throws {
    try dbWriter.write { db in
      // save = insert or replace (upsert)
      var mutable = record
      try mutable.save(db)
    }
  }

  public func fetchById(_ id: String) throws -> ScenarioRecord? {
    try dbWriter.read { db in
      try ScenarioRecord.fetchOne(db, key: id)
    }
  }

  public func fetchAll() throws -> [ScenarioRecord] {
    try dbWriter.read { db in
      try ScenarioRecord.order(Column("createdAt").desc).fetchAll(db)
    }
  }

  public func fetchPresets() throws -> [ScenarioRecord] {
    try dbWriter.read { db in
      try ScenarioRecord
        .filter(Column("isPreset") == true)
        .order(Column("name").asc)
        .fetchAll(db)
    }
  }

  public func delete(_ id: String) throws {
    try dbWriter.write { db in
      _ = try ScenarioRecord.deleteOne(db, key: id)
    }
  }
}
