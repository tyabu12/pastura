import Foundation
import GRDB

// Migration registrations for `DatabaseManager`, extracted from the main file
// to keep it within SwiftLint's 400-line `file_length` budget — migrations are
// append-only and grow unboundedly, so they live here where new versions can
// be added freely. `nonisolated` on the extension is required because the type
// is a `nonisolated` Data-layer class (see `.claude/rules/swift-isolation.md`
// Pattern 3) and the bodies build escaping `registerMigration` closures.
nonisolated extension DatabaseManager {

  // Internal (not `private`) so `makeMigrator()` in the main file can call it
  // across the file boundary; the per-version helpers stay `private` here.
  static func registerMigrations(_ migrator: inout DatabaseMigrator) {
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
    registerV8(&migrator)
    registerV9(&migrator)
    registerV10(&migrator)
    registerV11(&migrator)
  }

  private static func registerV11(_ migrator: inout DatabaseMigrator) {
    // Viewer-prediction outcomes (#915). One row per *answered* prediction,
    // keyed to its run; skipped predictions leave no row (see
    // `PredictionRecord`). Cascade-delete with the parent run so purging a
    // simulation drops its prediction. The `simulations` row is created at
    // run-start (before the first vote), so the FK is satisfied at insert.
    migrator.registerMigration("v11_createPredictionRecordsTable") { db in
      try db.create(table: "prediction_records") { t in
        t.primaryKey("id", .text)
        t.column("simulationId", .text).notNull()
          .references("simulations", onDelete: .cascade)
        t.column("questionKind", .text).notNull()
        t.column("predictedAgent", .text).notNull()
        t.column("actualAgent", .text).notNull()
        t.column("isHit", .boolean).notNull()
        t.column("createdAt", .datetime).notNull()
      }

      try db.create(
        index: "idx_prediction_records_simulation",
        on: "prediction_records",
        columns: ["simulationId"])
    }
  }

  private static func registerV9(_ migrator: inout DatabaseMigrator) {
    // Denormalize the gallery category onto scenarios for Home / Past Results
    // (#748). Nullable TEXT (v8 `language` pattern); existing rows stay NULL,
    // no backfill — see `ScenarioRecord.category` for the no-backfill rationale.
    migrator.registerMigration("v9_addCategoryToScenarios") { db in
      try db.alter(table: "scenarios") { t in
        t.add(column: "category", .text)
      }
    }
  }

  private static func registerV10(_ migrator: inout DatabaseMigrator) {
    // Snapshot the gallery category onto each run so Past Results keeps it even
    // after the source scenario is edited / deleted (#748). Nullable TEXT,
    // additive alter (no table rebuild); NULL for pre-v10 runs and runs of
    // local scenarios — see `SimulationRecord.scenarioCategorySnapshot`.
    migrator.registerMigration("v10_addScenarioCategorySnapshotToSimulations") { db in
      try db.alter(table: "simulations") { t in
        t.add(column: "scenarioCategorySnapshot", .text)
      }
    }
  }

  private static func registerV8(_ migrator: inout DatabaseMigrator) {
    // Denormalize ADR-010 D1's mandatory YAML `language` field into a column
    // so Home / Past Results cross-language variant grouping (D4/D6) collapses
    // by `sourceId` + language without loading + parsing `yamlDefinition` for
    // every row (the residual unbounded load from #586 / PR #674).
    migrator.registerMigration("v8_addLanguageToScenarios") { db in
      // Nullable TEXT (mirrors the v4 source columns). Existing rows stay NULL
      // and consumers fall back to `"ja"`; new/re-saved rows carry the value
      // from `ScenarioRecord`. Pre-existing rows are intentionally NOT
      // backfilled — per ADR-010 D11 the install base is effectively zero and
      // testers reinstall (a fresh install loads presets with the column set),
      // so a content-parsing backfill would only ever touch a developer's own
      // pre-v8 DB. Keeping Data free of any YAML interpretation.
      try db.alter(table: "scenarios") { t in
        t.add(column: "language", .text)
      }
    }
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
