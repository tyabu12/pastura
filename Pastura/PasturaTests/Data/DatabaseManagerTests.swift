import Foundation
import GRDB
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1))) struct DatabaseManagerTests {

  @Test func inMemoryCreatesWithoutError() throws {
    // Verifies that inMemory() doesn't throw and returns a usable manager
    let manager = try DatabaseManager.inMemory()
    _ = manager.dbWriter  // Ensure dbWriter is accessible
  }

  @Test func migrationCreatesAllTables() throws {
    let manager = try DatabaseManager.inMemory()
    // Verify all 3 tables exist by inserting into each
    try manager.dbWriter.write { db in
      try db.execute(
        sql: """
          INSERT INTO scenarios (id, name, yamlDefinition, isPreset, createdAt, updatedAt)
          VALUES (?, ?, ?, ?, ?, ?)
          """,
        arguments: ["s1", "Test", "yaml: true", false, Date(), Date()])

      try db.execute(
        sql: """
          INSERT INTO simulations (id, scenarioId, status, currentRound, currentPhaseIndex, stateJSON, createdAt, updatedAt)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: ["sim1", "s1", "running", 0, 0, "{}", Date(), Date()])

      try db.execute(
        sql: """
          INSERT INTO turns (id, simulationId, roundNumber, phaseType, rawOutput, parsedOutputJSON, createdAt)
          VALUES (?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: ["t1", "sim1", 1, "speak_all", "raw", "{}", Date()])
    }
  }

  @Test func migrationIsIdempotent() throws {
    // Creating two managers on the same DB should not error
    let manager = try DatabaseManager.inMemory()
    // Running migrate again should be safe
    try DatabaseManager.applyMigrations(to: manager.dbWriter)
  }

  @Test func foreignKeyConstraintEnforced() throws {
    let manager = try DatabaseManager.inMemory()
    // Insert simulation with nonexistent scenarioId should fail
    #expect(throws: (any Error).self) {
      try manager.dbWriter.write { db in
        try db.execute(
          sql: """
            INSERT INTO simulations (id, scenarioId, status, currentRound, currentPhaseIndex, stateJSON, createdAt, updatedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
          arguments: [
            "sim1", "nonexistent", "running", 0, 0, "{}", Date(), Date()
          ])
      }
    }
  }

  // MARK: - persistent(at:) failure mapping (issue #546)

  private func makeTempDBPath() -> String {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("dbmgr-\(UUID().uuidString).sqlite").path
  }

  /// Seeds a file that opens fine as SQLite but whose pre-existing
  /// `scenarios` table collides with v1's `CREATE TABLE scenarios`, so the
  /// next `applyMigrations` fails from inside `migrate()`. The queue is
  /// scoped to this call so it deallocs (releasing the file) before reopen.
  private func seedConflictingScenariosTable(at path: String) throws {
    let seed = try DatabaseQueue(path: path)
    try seed.write { db in
      try db.execute(sql: "CREATE TABLE scenarios (foo TEXT)")
    }
  }

  @Test func persistentMigrationFailureSurfacesAsMigrationFailed() throws {
    let path = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: path) }
    try seedConflictingScenariosTable(at: path)

    do {
      _ = try DatabaseManager.persistent(at: path)
      Issue.record("expected persistent(at:) to throw on migration conflict")
    } catch let error as DataError {
      guard case .migrationFailed = error else {
        Issue.record("expected .migrationFailed, got \(error)")
        return
      }
    }
  }

  @Test func persistentOpenFailureSurfacesAsDatabaseOpenFailed() {
    // A path whose parent directory does not exist cannot be opened/created
    // by SQLite — the failure originates at the open `try` site.
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent("no-such-dir-\(UUID().uuidString)/db.sqlite").path

    do {
      _ = try DatabaseManager.persistent(at: path)
      Issue.record("expected persistent(at:) to throw on un-openable path")
    } catch let error as DataError {
      guard case .databaseOpenFailed = error else {
        Issue.record("expected .databaseOpenFailed, got \(error)")
        return
      }
    } catch {
      Issue.record("expected DataError, got \(error)")
    }
  }

  @Test func deletingScenarioOrphansSimulationsViaSetNull() throws {
    let manager = try DatabaseManager.inMemory()
    try manager.dbWriter.write { db in
      try db.execute(
        sql: """
          INSERT INTO scenarios (id, name, yamlDefinition, isPreset, createdAt, updatedAt)
          VALUES (?, ?, ?, ?, ?, ?)
          """,
        arguments: ["s1", "Test", "yaml: true", false, Date(), Date()])

      try db.execute(
        sql: """
          INSERT INTO simulations (id, scenarioId, status, currentRound, currentPhaseIndex, stateJSON, createdAt, updatedAt)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: ["sim1", "s1", "running", 0, 0, "{}", Date(), Date()])

      // Delete the scenario.
      try db.execute(sql: "DELETE FROM scenarios WHERE id = ?", arguments: ["s1"])

      // Since v7 the FK is ON DELETE SET NULL: the simulation survives
      // (history preserved) with its scenarioId cleared — it is NOT
      // cascade-deleted.
      let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM simulations")
      #expect(count == 1)
      let scenarioId = try String.fetchOne(
        db, sql: "SELECT scenarioId FROM simulations WHERE id = 'sim1'")
      #expect(scenarioId == nil)
    }
  }
}
