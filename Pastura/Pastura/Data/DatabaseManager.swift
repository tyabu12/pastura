import Foundation
import GRDB
import OSLog

/// Top-level coordinator for database initialization and migrations.
///
/// `DatabaseManager` owns the `DatabaseWriter` (a `DatabaseQueue` for MVP)
/// and applies schema migrations on creation. Repositories receive the
/// `dbWriter` to perform reads and writes.
nonisolated public final class DatabaseManager: Sendable {
  private static let logger = Logger(subsystem: "app.pastura.Pastura", category: "DatabaseManager")

  /// The underlying database writer. Exposed as `any DatabaseWriter`
  /// so switching from `DatabaseQueue` to `DatabasePool` later requires
  /// only changing the factory method.
  ///
  /// The *factory swap* is one line, but the *migration* is not — a
  /// `DatabasePool` opens the database in WAL journal mode (vs. the current
  /// `DatabaseQueue` rollback-journal default — see `recreateByBackingUp`
  /// for the no-sidecar consequence of that default). Enabling WAL pulls in
  /// two distinct concerns, only one of which is migration-gated:
  ///
  /// 1. **WAL sidecar backup** *(migration-gated)*: WAL adds persistent
  ///    `-wal` / `-shm` files. Exclude those from iCloud backup while
  ///    keeping `pastura.sqlite` itself backed up (ADR-015 D2 / §4). No
  ///    sidecars exist today, so there is nothing to do until WAL is on.
  /// 2. **File-protection / suspension** *(not WAL-specific — a baseline
  ///    posture)*: a DB access that holds a lock while the device is locked
  ///    in the background can hit `SQLITE_IOERR` / `0xdead10cc`. This is a
  ///    background-execution (ADR-003) interaction, not a WAL one, so it
  ///    already applies to today's `DatabaseQueue`. It is currently a
  ///    **non-issue**: the store lives in app-private Application Support
  ///    (no shared-container — the usual `0xdead10cc` trigger) under the
  ///    default `CompleteUntilFirstUserAuthentication` protection (readable
  ///    after first unlock, even while subsequently locked). A WAL
  ///    migration would *sharpen* it (locks/`-shm` mmap held longer), so
  ///    re-validate GRDB's `observesSuspensionNotifications` posture **at**
  ///    that migration — it is not a reason to act now.
  public let dbWriter: any DatabaseWriter

  /// Creates a `DatabaseManager` with the given writer and applies migrations.
  public init(dbWriter: any DatabaseWriter) throws {
    self.dbWriter = dbWriter
    try Self.applyMigrations(to: dbWriter)
  }

  /// Creates an in-memory database for testing.
  public static func inMemory() throws -> DatabaseManager {
    let dbQueue = try DatabaseQueue(configuration: Self.makeConfiguration())
    return try DatabaseManager(dbWriter: dbQueue)
  }

  /// Creates a persistent database at the given file path.
  ///
  /// Failures are mapped to typed `DataError` cases so the App layer can tell
  /// a recoverable migration failure (issue #546) from an open failure:
  /// the open `try` maps to `.databaseOpenFailed`, the migration `try` (via
  /// `init` → `applyMigrations`) to `.migrationFailed`. `init` only throws
  /// from `applyMigrations` today; if future init work adds other throw
  /// sites, revisit this blanket relabel.
  public static func persistent(at path: String) throws -> DatabaseManager {
    let dbQueue: DatabaseQueue
    do {
      dbQueue = try DatabaseQueue(path: path, configuration: Self.makeConfiguration())
    } catch {
      throw DataError.databaseOpenFailed(description: error.localizedDescription)
    }
    do {
      return try DatabaseManager(dbWriter: dbQueue)
    } catch {
      throw DataError.migrationFailed(description: error.localizedDescription)
    }
  }

  /// Moves the database file at `path` aside to a timestamped backup and
  /// returns a fresh `DatabaseManager` with a newly-created schema.
  ///
  /// Used by the App layer's migration-recovery flow (issue #546) when a
  /// schema migration fails deterministically: a plain retry re-runs the
  /// same migration and re-fails forever, so backup-and-recreate is the only
  /// escape that does not require deleting the app.
  ///
  /// The old file is **preserved, not deleted** — recovery requires explicit
  /// user consent at the call site (ADR-015 D1: no silent destruction of run
  /// history) and the backup remains on disk for manual retrieval. The
  /// backup is **non-destructive**: if the fresh DB cannot be created (e.g.
  /// disk full) the original is restored, so a failed recovery never leaves
  /// the user with no database.
  ///
  /// The `.backup-*` file is excluded from iCloud backup — it is a local
  /// safety net, a distinct file class from the live DB which ADR-015 D2
  /// deliberately keeps backed up — and older recovery backups are pruned to
  /// the most recent one to bound disk use. `DatabaseQueue` uses
  /// rollback-journal mode (not WAL), so there are no `-wal` / `-shm` sidecar
  /// files to move alongside.
  ///
  /// - Parameters:
  ///   - path: The live database file path.
  ///   - timestamp: Backup-name timestamp; injectable for deterministic tests.
  public static func recreateByBackingUp(
    at path: String,
    timestamp: Date = Date()
  ) throws -> DatabaseManager {
    try recreateByBackingUp(at: path, timestamp: timestamp, recreate: { try persistent(at: $0) })
  }

  /// Test seam for `recreateByBackingUp(at:timestamp:)` — `recreate` lets a
  /// test inject a failing fresh-DB creation to exercise the restore path.
  static func recreateByBackingUp(
    at path: String,
    timestamp: Date,
    recreate: (String) throws -> DatabaseManager
  ) throws -> DatabaseManager {
    let fileManager = FileManager.default
    var movedBackup: String?
    if fileManager.fileExists(atPath: path) {
      let backup = backupPath(for: path, timestamp: timestamp)
      try fileManager.moveItem(atPath: path, toPath: backup)
      movedBackup = backup
      logger.warning(
        "DB recovery: moved existing database aside to \(backup, privacy: .public)")
    }
    do {
      let manager = try recreate(path)
      if let movedBackup {
        excludeFromBackup(atPath: movedBackup)
        pruneOldBackups(for: path, keeping: movedBackup)
      }
      logger.notice("DB recovery: created fresh database at \(path, privacy: .public)")
      return manager
    } catch {
      // Non-destructive: restore the original so a failed recovery leaves the
      // user's (corrupt-but-present) DB in place rather than nothing.
      if let movedBackup {
        try? fileManager.removeItem(atPath: path)  // discard any partial fresh file
        do {
          try fileManager.moveItem(atPath: movedBackup, toPath: path)
          logger.error("DB recovery failed; restored the original database file")
        } catch {
          // Worst case — the original could neither be recreated nor restored.
          // Surface the backup location so it stays manually recoverable, and
          // distinguish this from the expected (recreate-only) failure above.
          logger.fault(
            "DB recovery failed AND restore failed; backup at \(movedBackup, privacy: .public)")
        }
      } else {
        logger.error("DB recovery failed (no existing database to restore)")
      }
      throw error
    }
  }

  /// Applies all registered migrations to the given database writer.
  ///
  /// Safe to call multiple times — GRDB's `DatabaseMigrator` skips
  /// already-applied migrations.
  public static func applyMigrations(to writer: any DatabaseWriter) throws {
    try makeMigrator().migrate(writer)
  }

  /// Returns the configured `DatabaseMigrator` without applying it.
  ///
  /// Used by tests (via `@testable import`) to migrate up to a specific
  /// version with `migrate(writer, upTo:)` and verify behaviour on seeded
  /// data. Not part of the public API.
  static func makeMigrator() -> DatabaseMigrator {
    var migrator = DatabaseMigrator()
    registerMigrations(&migrator)
    return migrator
  }

  // MARK: - Private

  private static func makeConfiguration() -> Configuration {
    var config = Configuration()
    // Enable foreign key enforcement (SQLite default is OFF)
    config.foreignKeysEnabled = true
    return config
  }

  /// Backup path for a live DB file: `<path>.backup-<yyyyMMdd-HHmmss>` (UTC).
  /// 1-second resolution; two recoveries in the same second would collide on
  /// the rename and surface as a (non-destructive) recovery failure — an
  /// astronomically unlikely real-world event.
  private static func backupPath(for path: String, timestamp: Date) -> String {
    let formatter = DateFormatter()
    // POSIX locale + UTC: locale-independent, lexically-sortable backup names
    // regardless of the device's region / calendar / time zone.
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return "\(path).backup-\(formatter.string(from: timestamp))"
  }

  private static func excludeFromBackup(atPath path: String) {
    var url = URL(fileURLWithPath: path)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? url.setResourceValues(values)
  }

  /// Removes every `<dbName>.backup-*` file except `keepPath`, bounding the
  /// disk footprint of repeated recoveries to the single most-recent backup.
  private static func pruneOldBackups(for path: String, keeping keepPath: String) {
    let fileManager = FileManager.default
    let url = URL(fileURLWithPath: path)
    let dir = url.deletingLastPathComponent()
    let prefix = url.lastPathComponent + ".backup-"
    guard let entries = try? fileManager.contentsOfDirectory(atPath: dir.path) else { return }
    for entry in entries where entry.hasPrefix(prefix) {
      let full = dir.appendingPathComponent(entry).path
      if full != keepPath {
        try? fileManager.removeItem(atPath: full)
      }
    }
  }

  private static func registerMigrations(_ migrator: inout DatabaseMigrator) {
    registerV1(&migrator)

    migrator.registerMigration("v2_addSequenceNumberToTurns") { db in
      try db.alter(table: "turns") { t in
        t.add(column: "sequenceNumber", .integer).notNull().defaults(to: 0)
      }
    }

    migrator.registerMigration("v3_addModelInfoToSimulations") { db in
      try db.alter(table: "simulations") { t in
        t.add(column: "modelIdentifier", .text)
        t.add(column: "llmBackend", .text)
      }
    }

    migrator.registerMigration("v4_addScenarioSourceColumns") { db in
      // Nullable TEXT columns with no default: existing rows stay as NULL
      // (locally authored / bundled preset). Non-nil only for gallery imports.
      try db.alter(table: "scenarios") { t in
        t.add(column: "sourceType", .text)
        t.add(column: "sourceId", .text)
        t.add(column: "sourceHash", .text)
      }
    }

    migrator.registerMigration("v5_createCodePhaseEventsTable") { db in
      try db.create(table: "code_phase_events") { t in
        t.primaryKey("id", .text)
        t.column("simulationId", .text).notNull()
          .references("simulations", onDelete: .cascade)
        t.column("roundNumber", .integer).notNull()
        t.column("phaseType", .text).notNull()
        t.column("sequenceNumber", .integer).notNull()
        t.column("payloadJSON", .text).notNull()
        t.column("createdAt", .datetime).notNull()
      }

      try db.create(
        index: "idx_code_phase_events_simulation_round",
        on: "code_phase_events",
        columns: ["simulationId", "roundNumber"])
    }

    migrator.registerMigration("v6_addPhasePathToTurnsAndCodePhaseEvents") { db in
      // Nullable TEXT with no default: existing rows read as NULL (legacy —
      // lineage wasn't captured pre-v6). Matches `TurnRecord.phasePathJSON`
      // and `CodePhaseEventRecord.phasePathJSON` optionals.
      try db.alter(table: "turns") { t in
        t.add(column: "phasePathJSON", .text)
      }
      try db.alter(table: "code_phase_events") { t in
        t.add(column: "phasePathJSON", .text)
      }
    }

    registerV7(&migrator)
  }

  private static func registerV7(_ migrator: inout DatabaseMigrator) {
    // Snapshot the source scenario into each run + relax the scenario FK so
    // deleting/editing a scenario no longer destroys or drifts past results.
    //
    // SQLite cannot ALTER a column's FK action or nullability in place, so
    // the `simulations` table is rebuilt. The default `.deferred` foreign-key
    // policy runs this body with `PRAGMA foreign_keys = OFF` (GRDB follows the
    // SQLite "other kinds of table schema changes" recipe), so dropping the
    // old table does NOT cascade-delete the child `turns` /
    // `code_phase_events` rows; integrity is re-verified at commit.
    migrator.registerMigration("v7_snapshotScenarioAndRelaxScenarioFK") { db in
      try db.create(table: "new_simulations") { t in
        t.primaryKey("id", .text)
        // Nullable + SET NULL (was NOT NULL + CASCADE): orphan runs on
        // scenario deletion instead of cascade-deleting their history.
        t.column("scenarioId", .text)
          .references("scenarios", onDelete: .setNull)
        t.column("status", .text).notNull().defaults(to: "running")
        t.column("currentRound", .integer).notNull().defaults(to: 0)
        t.column("currentPhaseIndex", .integer).notNull().defaults(to: 0)
        t.column("stateJSON", .text).notNull()
        t.column("configJSON", .text)
        t.column("createdAt", .datetime).notNull()
        t.column("updatedAt", .datetime).notNull()
        t.column("modelIdentifier", .text)
        t.column("llmBackend", .text)
        t.column("scenarioYamlSnapshot", .text)
        t.column("scenarioNameSnapshot", .text)
      }

      // Copy existing rows. Snapshot columns stay NULL for migrated runs —
      // they fall back to the live scenario via `scenarioId` while it exists.
      try db.execute(
        sql: """
          INSERT INTO new_simulations
            (id, scenarioId, status, currentRound, currentPhaseIndex,
             stateJSON, configJSON, createdAt, updatedAt, modelIdentifier, llmBackend)
          SELECT
            id, scenarioId, status, currentRound, currentPhaseIndex,
            stateJSON, configJSON, createdAt, updatedAt, modelIdentifier, llmBackend
          FROM simulations
          """)

      try db.drop(table: "simulations")
      try db.rename(table: "new_simulations", to: "simulations")
    }
  }

  private static func registerV1(_ migrator: inout DatabaseMigrator) {
    migrator.registerMigration("v1_createTables") { db in
      try db.create(table: "scenarios") { t in
        t.primaryKey("id", .text)
        t.column("name", .text).notNull()
        t.column("yamlDefinition", .text).notNull()
        t.column("isPreset", .boolean).notNull().defaults(to: false)
        t.column("createdAt", .datetime).notNull()
        t.column("updatedAt", .datetime).notNull()
      }

      try db.create(table: "simulations") { t in
        t.primaryKey("id", .text)
        t.column("scenarioId", .text).notNull()
          .references("scenarios", onDelete: .cascade)
        t.column("status", .text).notNull().defaults(to: "running")
        t.column("currentRound", .integer).notNull().defaults(to: 0)
        t.column("currentPhaseIndex", .integer).notNull().defaults(to: 0)
        t.column("stateJSON", .text).notNull()
        t.column("configJSON", .text)
        t.column("createdAt", .datetime).notNull()
        t.column("updatedAt", .datetime).notNull()
      }

      try db.create(table: "turns") { t in
        t.primaryKey("id", .text)
        t.column("simulationId", .text).notNull()
          .references("simulations", onDelete: .cascade)
        t.column("roundNumber", .integer).notNull()
        t.column("phaseType", .text).notNull()
        t.column("agentName", .text)
        t.column("rawOutput", .text).notNull()
        t.column("parsedOutputJSON", .text).notNull()
        t.column("createdAt", .datetime).notNull()
      }

      // Index for efficient round-based queries
      try db.create(
        index: "idx_turns_simulation_round",
        on: "turns",
        columns: ["simulationId", "roundNumber"])
    }
  }
}
