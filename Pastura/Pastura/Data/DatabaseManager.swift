import Foundation
import GRDB

/// Top-level coordinator for database initialization and migrations.
///
/// `DatabaseManager` owns the `DatabaseWriter` (a `DatabaseQueue` for MVP)
/// and applies schema migrations on creation. Repositories receive the
/// `dbWriter` to perform reads and writes.
nonisolated public final class DatabaseManager: Sendable {
  /// The underlying database writer. Exposed as `any DatabaseWriter`
  /// so switching from `DatabaseQueue` to `DatabasePool` later requires
  /// only changing the factory method.
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
  public static func persistent(at path: String) throws -> DatabaseManager {
    let dbQueue = try DatabaseQueue(path: path, configuration: Self.makeConfiguration())
    return try DatabaseManager(dbWriter: dbQueue)
  }

  /// Applies all registered migrations to the given database writer.
  ///
  /// Safe to call multiple times — GRDB's `DatabaseMigrator` skips
  /// already-applied migrations.
  public static func applyMigrations(to writer: any DatabaseWriter) throws {
    var migrator = DatabaseMigrator()
    registerMigrations(&migrator)
    try migrator.migrate(writer)
  }

  // MARK: - Private

  private static func makeConfiguration() -> Configuration {
    var config = Configuration()
    // Enable foreign key enforcement (SQLite default is OFF)
    config.foreignKeysEnabled = true
    return config
  }

  private static func registerMigrations(_ migrator: inout DatabaseMigrator) {
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
  }
}
