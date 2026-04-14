import Foundation
import GRDB
import Testing

@testable import Pastura

/// Tests for incremental schema migrations.
///
/// Exercises `DatabaseManager.makeMigrator()` by migrating up to a specific
/// version, seeding realistic data, then applying the next migration and
/// asserting existing rows survive.
@Suite struct DatabaseMigrationTests {

  private func makeQueue() throws -> DatabaseQueue {
    var config = Configuration()
    config.foreignKeysEnabled = true
    return try DatabaseQueue(configuration: config)
  }

  @Test func v3AddsNullableSourceColumnsPreservingExistingRows() throws {
    let queue = try makeQueue()
    let migrator = DatabaseManager.makeMigrator()

    // Migrate only up to v2 — mimics a TestFlight user's on-device DB.
    try migrator.migrate(queue, upTo: "v2_addSequenceNumberToTurns")

    // Seed both a preset and a user-created row.
    //
    // Use raw SQL rather than `ScenarioRecord.insert()` because the struct
    // now knows about v3 columns; GRDB's Codable path would try to insert
    // them and SQLite would reject the unknown columns under the v2 schema.
    let now = Date()
    try queue.write { db in
      try db.execute(
        sql: """
          INSERT INTO scenarios (id, name, yamlDefinition, isPreset, createdAt, updatedAt)
          VALUES (?, ?, ?, ?, ?, ?)
          """,
        arguments: ["prisoners_dilemma", "Preset", "yaml: preset", true, now, now])
      try db.execute(
        sql: """
          INSERT INTO scenarios (id, name, yamlDefinition, isPreset, createdAt, updatedAt)
          VALUES (?, ?, ?, ?, ?, ?)
          """,
        arguments: ["my_custom", "Mine", "yaml: mine", false, now, now])
    }

    // Apply remaining migrations (v3+).
    try migrator.migrate(queue)

    // Existing rows survive and decode with nil source fields.
    let rows = try queue.read { db in
      try ScenarioRecord.order(Column("id")).fetchAll(db)
    }
    #expect(rows.count == 2)
    #expect(rows.allSatisfy { $0.sourceType == nil })
    #expect(rows.allSatisfy { $0.sourceId == nil })
    #expect(rows.allSatisfy { $0.sourceHash == nil })
    #expect(rows.map(\.id) == ["my_custom", "prisoners_dilemma"])

    // New rows can set source columns.
    try queue.write { db in
      var gallery = ScenarioRecord(
        id: "asch_v1", name: "Asch", yamlDefinition: "yaml: asch",
        isPreset: false, createdAt: now, updatedAt: now,
        sourceType: ScenarioSourceType.gallery, sourceId: "asch_v1", sourceHash: "abc")
      try gallery.insert(db)
    }
    let gallery = try queue.read { db in
      try ScenarioRecord.fetchOne(db, key: "asch_v1")
    }
    #expect(gallery?.sourceType == ScenarioSourceType.gallery)
  }

  @Test func allMigrationsApplyIdempotently() throws {
    // Applying the full migrator twice must not fail and must not duplicate work.
    let queue = try makeQueue()
    let migrator = DatabaseManager.makeMigrator()

    try migrator.migrate(queue)
    let firstRun = try queue.read { db in
      try migrator.appliedIdentifiers(db)
    }

    try migrator.migrate(queue)  // no-op second run
    let secondRun = try queue.read { db in
      try migrator.appliedIdentifiers(db)
    }

    #expect(firstRun == secondRun)
    #expect(!firstRun.isEmpty)  // sanity: at least one migration registered
  }
}
