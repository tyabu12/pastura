import Foundation
import GRDB
import Testing

@testable import Pastura

/// Tests for incremental schema migrations.
///
/// Exercises `DatabaseManager.makeMigrator()` by migrating up to a specific
/// version, seeding realistic data, then applying the next migration and
/// asserting existing rows survive.
@Suite(.timeLimit(.minutes(1))) struct DatabaseMigrationTests {

  private func makeQueue() throws -> DatabaseQueue {
    var config = Configuration()
    config.foreignKeysEnabled = true
    return try DatabaseQueue(configuration: config)
  }

  @Test func v4AddsNullableSourceColumnsPreservingExistingRows() throws {
    let queue = try makeQueue()
    let migrator = DatabaseManager.makeMigrator()

    // Migrate only up to v2 — mimics a TestFlight user's on-device DB
    // before either v3 (model info) or v4 (gallery source) shipped.
    try migrator.migrate(queue, upTo: "v2_addSequenceNumberToTurns")

    // Seed both a preset and a user-created row.
    //
    // Use raw SQL rather than `ScenarioRecord.insert()` because the struct
    // now knows about v4 columns; GRDB's Codable path would try to insert
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

    // Apply remaining migrations (v3 + v4).
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

  @Test func v7PreservesChildRowsAndAddsNullableSnapshotColumns() throws {
    let queue = try makeQueue()
    let migrator = DatabaseManager.makeMigrator()

    // Migrate only up to v6 — mimics an on-device DB before the
    // scenario-snapshot rebuild (v7) shipped.
    try migrator.migrate(queue, upTo: "v6_addPhasePathToTurnsAndCodePhaseEvents")

    // Seed a scenario, a completed run referencing it, and child rows in
    // both `turns` and `code_phase_events`. Raw SQL: the struct now knows
    // about v7 columns the v6 schema lacks.
    let now = Date()
    try queue.write { db in
      try db.execute(
        sql: """
          INSERT INTO scenarios (id, name, yamlDefinition, isPreset, createdAt, updatedAt)
          VALUES (?, ?, ?, ?, ?, ?)
          """,
        arguments: ["sc1", "Scenario One", "yaml: one", false, now, now])
      try db.execute(
        sql: """
          INSERT INTO simulations
            (id, scenarioId, status, currentRound, currentPhaseIndex,
             stateJSON, configJSON, createdAt, updatedAt, modelIdentifier, llmBackend)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: ["sim1", "sc1", "completed", 2, 0, "{}", nil, now, now, "Gemma", "llama.cpp"])
      try db.execute(
        sql: """
          INSERT INTO turns
            (id, simulationId, roundNumber, phaseType, agentName,
             rawOutput, parsedOutputJSON, sequenceNumber, createdAt)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: ["t1", "sim1", 1, "speak", "Alice", "raw", "{}", 0, now])
      try db.execute(
        sql: """
          INSERT INTO code_phase_events
            (id, simulationId, roundNumber, phaseType, sequenceNumber, payloadJSON, createdAt)
          VALUES (?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: ["e1", "sim1", 1, "score_calc", 0, "{}", now])
    }

    // Apply v7 — rebuilds the `simulations` table. The deferred-FK
    // migration must NOT cascade-delete the child rows during the rebuild.
    try migrator.migrate(queue)

    let counts = try queue.read { db in
      (
        turns: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM turns") ?? -1,
        events: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM code_phase_events") ?? -1
      )
    }
    #expect(counts.turns == 1)
    #expect(counts.events == 1)

    // The simulation row survives with its existing data intact and the
    // new snapshot columns defaulting to nil for migrated rows.
    let sim = try queue.read { db in try SimulationRecord.fetchOne(db, key: "sim1") }
    #expect(sim?.scenarioId == "sc1")
    #expect(sim?.modelIdentifier == "Gemma")
    #expect(sim?.llmBackend == "llama.cpp")
    #expect(sim?.scenarioYamlSnapshot == nil)
    #expect(sim?.scenarioNameSnapshot == nil)
  }

  @Test func v7ChangesScenarioFKToSetNullSoScenarioDeletePreservesHistory() throws {
    let queue = try makeQueue()
    try DatabaseManager.makeMigrator().migrate(queue)  // full schema incl. v7

    let now = Date()
    try queue.write { db in
      try db.execute(
        sql: """
          INSERT INTO scenarios (id, name, yamlDefinition, isPreset, createdAt, updatedAt)
          VALUES (?, ?, ?, ?, ?, ?)
          """,
        arguments: ["sc1", "Scenario One", "yaml: one", false, now, now])
      var sim = SimulationRecord(
        id: "sim1", scenarioId: "sc1", status: "completed",
        currentRound: 1, currentPhaseIndex: 0, stateJSON: "{}", configJSON: nil,
        createdAt: now, updatedAt: now,
        scenarioYamlSnapshot: "yaml: one", scenarioNameSnapshot: "Scenario One")
      try sim.insert(db)
      try db.execute(
        sql: """
          INSERT INTO turns
            (id, simulationId, roundNumber, phaseType, agentName,
             rawOutput, parsedOutputJSON, sequenceNumber, createdAt)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: ["t1", "sim1", 1, "speak", "Alice", "raw", "{}", 0, now])
    }

    // Deleting the scenario must NOT cascade-delete the run; the FK is now
    // ON DELETE SET NULL, so the run is orphaned but history is preserved.
    try queue.write { db in
      _ = try ScenarioRecord.deleteOne(db, key: "sc1")
    }

    let sim = try queue.read { db in try SimulationRecord.fetchOne(db, key: "sim1") }
    #expect(sim != nil)
    #expect(sim?.scenarioId == nil)
    #expect(sim?.scenarioNameSnapshot == "Scenario One")
    #expect(sim?.scenarioYamlSnapshot == "yaml: one")
    let turnCount = try queue.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM turns WHERE simulationId = 'sim1'") ?? -1
    }
    #expect(turnCount == 1)
  }

  @Test func v8BackfillsLanguageColumnFromStoredYAML() throws {
    let queue = try makeQueue()
    let migrator = DatabaseManager.makeMigrator()

    // Migrate up to v7 — mimics an on-device DB before the language column.
    try migrator.migrate(queue, upTo: "v7_snapshotScenarioAndRelaxScenarioFK")

    // Seed rows covering each backfill branch. Raw SQL: the struct now knows
    // about the v8 `language` column the v7 schema lacks.
    let now = Date()
    let seeds: [(id: String, yaml: String)] = [
      ("ja_row", "name: 人狼\nlanguage: ja"),
      ("en_row", "name: Word Wolf\nlanguage: en"),
      // Prefix-collision: simulation_language must NOT be read as language.
      ("cross_row", "simulation_language: en\nlanguage: ja"),
      // No top-level language → "ja" fallback.
      ("legacy_row", "name: Legacy\nrounds: 1")
    ]
    try queue.write { db in
      for seed in seeds {
        try db.execute(
          sql: """
            INSERT INTO scenarios (id, name, yamlDefinition, isPreset, createdAt, updatedAt)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
          arguments: [seed.id, seed.id, seed.yaml, false, now, now])
      }
    }

    // Apply v8 — adds the column and backfills every row.
    try migrator.migrate(queue)

    let byId = try queue.read { db in
      Dictionary(
        uniqueKeysWithValues: try ScenarioRecord.fetchAll(db).map { ($0.id, $0.language) })
    }
    #expect(byId["ja_row"] == "ja")
    #expect(byId["en_row"] == "en")
    #expect(byId["cross_row"] == "ja")  // not "en" — prefix-collision skipped
    #expect(byId["legacy_row"] == "ja")  // fallback

    // New rows persist the column from the struct.
    try queue.write { db in
      var record = ScenarioRecord(
        id: "new_en", name: "New", yamlDefinition: "language: en",
        isPreset: false, createdAt: now, updatedAt: now, language: "en")
      try record.insert(db)
    }
    let fetched = try queue.read { db in try ScenarioRecord.fetchOne(db, key: "new_en") }
    #expect(fetched?.language == "en")
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
