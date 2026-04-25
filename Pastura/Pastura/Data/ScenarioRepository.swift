import Foundation
import GRDB

/// Repository for persisting and retrieving scenario records.
nonisolated public protocol ScenarioRepository: Sendable {
  /// Saves a scenario record (full-row upsert).
  ///
  /// Inserts if new; replaces **all** columns if the ID already exists.
  ///
  /// Refuses to overwrite a gallery-sourced row and throws
  /// `DataError.readonly` unless the incoming payload is also a gallery
  /// payload carrying the **same** `sourceId`. The gallery Try/Update flow
  /// satisfies this; every other caller does not.
  func save(_ record: ScenarioRecord) throws

  /// Fetches a scenario by its unique ID. Returns `nil` if not found.
  func fetchById(_ id: String) throws -> ScenarioRecord?

  /// Fetches a scenario by its (`sourceType`, `sourceId`) pair.
  ///
  /// Used to resolve a gallery scenario to its locally-installed record
  /// independently of the primary key. Returns `nil` if no matching row.
  func fetchBySource(type: String, id: String) throws -> ScenarioRecord?

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
      // Repository-level readonly guard. A gallery-sourced row can only
      // be overwritten by a gallery payload that targets the same source
      // identity (same sourceId). This blocks both (a) local payloads
      // clobbering gallery rows and (b) a gallery payload that somehow
      // claims a different sourceId from the row it would replace.
      if let existing = try ScenarioRecord.fetchOne(db, key: record.id),
        existing.sourceType == ScenarioSourceType.gallery {
        let sameGallerySource =
          record.sourceType == ScenarioSourceType.gallery
          && record.sourceId != nil
          && record.sourceId == existing.sourceId
        if !sameGallerySource {
          throw DataError.readonly(id: record.id)
        }
      }
      let mutable = record
      try mutable.save(db)
    }
  }

  public func fetchById(_ id: String) throws -> ScenarioRecord? {
    try dbWriter.read { db in
      try ScenarioRecord.fetchOne(db, key: id)
    }
  }

  public func fetchBySource(type: String, id: String) throws -> ScenarioRecord? {
    try dbWriter.read { db in
      try ScenarioRecord
        .filter(Column("sourceType") == type)
        .filter(Column("sourceId") == id)
        .fetchOne(db)
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
