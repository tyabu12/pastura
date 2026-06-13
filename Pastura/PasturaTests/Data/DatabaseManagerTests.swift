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

  // MARK: - recreateByBackingUp recovery (issue #546)

  /// Fixed timestamp → backup name `…backup-20231114-221320` (UTC).
  private static let backupTS1 = Date(timeIntervalSince1970: 1_700_000_000)
  private static let backupName1 = "backup-20231114-221320"
  /// `backupTS1 + 1 day` → `…backup-20231115-221320` (UTC).
  private static let backupTS2 = Date(timeIntervalSince1970: 1_700_086_400)
  private static let backupName2 = "backup-20231115-221320"

  private func seedScenarioRow(at path: String, id: String) throws {
    let manager = try DatabaseManager.persistent(at: path)
    try manager.dbWriter.write { db in
      try db.execute(
        sql: """
          INSERT INTO scenarios (id, name, yamlDefinition, isPreset, createdAt, updatedAt)
          VALUES (?, ?, ?, ?, ?, ?)
          """,
        arguments: [id, "Seed", "yaml: x", false, Date(), Date()])
    }
  }

  private func scenarioCount(at path: String) throws -> Int {
    let queue = try DatabaseQueue(path: path)
    return try queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM scenarios") ?? -1 }
  }

  private func backupFiles(for path: String) -> [String] {
    let url = URL(fileURLWithPath: path)
    let prefix = url.lastPathComponent + ".backup-"
    let dir = url.deletingLastPathComponent().path
    let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
    return entries.filter { $0.hasPrefix(prefix) }
  }

  private func cleanup(_ path: String) {
    let fileManager = FileManager.default
    try? fileManager.removeItem(atPath: path)
    let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
    for name in backupFiles(for: path) {
      try? fileManager.removeItem(atPath: dir.appendingPathComponent(name).path)
    }
  }

  @Test func recreateByBackingUpMovesOldFileAsideAndCreatesFresh() throws {
    let path = makeTempDBPath()
    defer { cleanup(path) }
    try seedScenarioRow(at: path, id: "old-row")

    let manager = try DatabaseManager.recreateByBackingUp(at: path, timestamp: Self.backupTS1)

    // Fresh DB at the live path is empty and usable.
    let freshCount = try manager.dbWriter.read {
      try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM scenarios") ?? -1
    }
    #expect(freshCount == 0)

    // The old file moved aside under the timestamped name, row preserved.
    let backup = "\(path).\(Self.backupName1)"
    #expect(FileManager.default.fileExists(atPath: backup))
    #expect(try scenarioCount(at: backup) == 1)
  }

  @Test func recreateByBackingUpExcludesBackupFromiCloud() throws {
    let path = makeTempDBPath()
    defer { cleanup(path) }
    try seedScenarioRow(at: path, id: "x")

    _ = try DatabaseManager.recreateByBackingUp(at: path, timestamp: Self.backupTS1)

    let backup = "\(path).\(Self.backupName1)"
    let values = try URL(fileURLWithPath: backup)
      .resourceValues(forKeys: [.isExcludedFromBackupKey])
    #expect(values.isExcludedFromBackup == true)
  }

  @Test func recreateByBackingUpPrunesOlderBackups() throws {
    let path = makeTempDBPath()
    defer { cleanup(path) }
    try seedScenarioRow(at: path, id: "gen0")

    _ = try DatabaseManager.recreateByBackingUp(at: path, timestamp: Self.backupTS1)
    _ = try DatabaseManager.recreateByBackingUp(at: path, timestamp: Self.backupTS2)

    // Only the most recent backup is retained.
    let backups = backupFiles(for: path)
    #expect(backups.count == 1)
    let expected = "\(URL(fileURLWithPath: path).lastPathComponent).\(Self.backupName2)"
    #expect(backups.first == expected)
  }

  @Test func recreateByBackingUpRestoresOriginalOnFailure() throws {
    let path = makeTempDBPath()
    defer { cleanup(path) }
    try seedScenarioRow(at: path, id: "precious")

    do {
      _ = try DatabaseManager.recreateByBackingUp(at: path, timestamp: Self.backupTS1) { _ in
        throw DataError.migrationFailed(description: "simulated recreate failure")
      }
      Issue.record("expected recreateByBackingUp to rethrow the recreate failure")
    } catch {
      // Non-destructive: the original DB is restored, openable, row intact,
      // and no orphaned backup is left behind.
      #expect(FileManager.default.fileExists(atPath: path))
      #expect(try scenarioCount(at: path) == 1)
      #expect(backupFiles(for: path).isEmpty)
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
