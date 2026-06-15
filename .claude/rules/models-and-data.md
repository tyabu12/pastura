---
paths:
  - "Pastura/Pastura/Models/**"
  - "Pastura/Pastura/Data/**"
---

# Models & Data Layer Rules

## Key Data Types

### TurnOutput

Dictionary wrapper with typed accessors for common fields:

```swift
nonisolated public struct TurnOutput: Codable, Sendable, Equatable {
    public let fields: [String: String]
    public var statement: String? { fields["statement"] }
    public var vote: String? { fields["vote"] }
    public var action: String? { fields["action"] }
    public var innerThought: String? { fields["inner_thought"] }
    public var reason: String? { fields["reason"] }

    public func require(_ key: String) throws -> String { ... }
}
```

### SimulationState

Must be `Codable` from day one — required for pause/resume serialization to DB.

```swift
nonisolated public struct SimulationState: Codable, Sendable, Equatable {
    public var scores: [String: Int]
    public var eliminated: [String: Bool]
    public var conversationLog: [ConversationEntry]
    public var lastOutputs: [String: TurnOutput]
    public var voteResults: [String: Int]
    public var pairings: [Pairing]
    public var variables: [String: String]
    public var currentRound: Int
}
```

### ConversationEntry

A single entry in the simulation's conversation log:

```swift
nonisolated public struct ConversationEntry: Codable, Sendable, Equatable {
    public let agentName: String
    public let content: String
    public let phaseType: PhaseType
    public let round: Int
}
```

Engine trims to most recent N entries for prompts (prevents context overflow).
Full log is preserved in DB via TurnRecord.

## Database Schema (GRDB)

Three tables. No `agents` table — agent state lives in `SimulationRecord.stateJSON`.

```sql
scenarios (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    yamlDefinition TEXT NOT NULL,
    isPreset BOOLEAN NOT NULL DEFAULT 0,
    createdAt DATETIME NOT NULL,
    updatedAt DATETIME NOT NULL,
    sourceType TEXT,   -- "gallery" for Shared Scenarios imports; NULL for local/preset
    sourceId TEXT,     -- canonical id in the source system (gallery scenario id)
    sourceHash TEXT    -- SHA256 of the fetched YAML (update-detection key)
)

simulations (
    id TEXT PRIMARY KEY,
    scenarioId TEXT REFERENCES scenarios ON DELETE SET NULL,  -- nullable since v7: orphan (not cascade-delete) runs on scenario delete
    status TEXT NOT NULL DEFAULT 'running',  -- running | paused | completed
    currentRound INTEGER NOT NULL DEFAULT 0,
    currentPhaseIndex INTEGER NOT NULL DEFAULT 0,
    stateJSON TEXT NOT NULL,  -- Codable SimulationState
    configJSON TEXT,
    createdAt DATETIME NOT NULL,
    updatedAt DATETIME NOT NULL,
    modelIdentifier TEXT,         -- LLM model label (v3); NULL for pre-v3 rows
    llmBackend TEXT,              -- LLM backend label (v3); NULL for pre-v3 rows
    scenarioYamlSnapshot TEXT,    -- v7: source scenario YAML captured at run-creation; NULL pre-v7
    scenarioNameSnapshot TEXT     -- v7: source scenario name captured at run-creation; NULL pre-v7
)

turns (
    id TEXT PRIMARY KEY,
    simulationId TEXT NOT NULL REFERENCES simulations ON DELETE CASCADE,
    roundNumber INTEGER NOT NULL,
    phaseType TEXT NOT NULL,
    agentName TEXT,  -- NULL for code phases
    rawOutput TEXT NOT NULL,
    parsedOutputJSON TEXT NOT NULL,
    sequenceNumber INTEGER NOT NULL DEFAULT 0,  -- canonical ordering key
    createdAt DATETIME NOT NULL
)

CREATE INDEX idx_turns_simulation_round ON turns(simulationId, roundNumber);
```

## Data Layer Implementation

### DatabaseManager

`DatabaseManager` is the top-level coordinator. Factory methods:
- `DatabaseManager.inMemory()` — for tests
- `DatabaseManager.persistent(at:)` — for production

Exposes `dbWriter: any DatabaseWriter` for repository construction.
Migrations are applied automatically on init via `DatabaseMigrator`.

### Record Types (Data/Models/)

GRDB records conforming to `FetchableRecord` + `PersistableRecord`:
- `ScenarioRecord` — maps to `scenarios` table
- `SimulationRecord` — maps to `simulations` table; `stateJSON` stores serialized `SimulationState`
- `TurnRecord` — maps to `turns` table; `rawOutput` stores unfiltered LLM response

`SimulationRecord` has a `simulationStatus` convenience property for type-safe access.
All records use `var` properties (GRDB convention for mutable persistence).

### Repository Protocols

| Protocol | Implementation | Key Operations |
|----------|---------------|----------------|
| `ScenarioRepository` | `GRDBScenarioRepository` | save (upsert), fetchById, fetchAll, fetchPresets, delete |
| `SimulationRepository` | `GRDBSimulationRepository` | save, fetchById, fetchByScenarioId, fetchOrphaned, updateState, updateStatus, delete |
| `TurnRepository` | `GRDBTurnRepository` | save, saveBatch, fetchBySimulationId, fetchBySimulationAndRound, deleteBySimulationId |

Repositories take `any DatabaseWriter` in their initializer. All methods are synchronous (`throws`).
`updateState` and `updateStatus` throw `DataError.recordNotFound` for missing records.

## GRDB FK & migration traps

### `PRAGMA foreign_keys = OFF` is ignored inside a transaction

SQLite silently ignores `PRAGMA foreign_keys` toggles mid-transaction — no error,
no effect. GRDB's `dbWriter.write { }` wraps the closure in a transaction, so a
pragma inside it is a no-op and the following `INSERT` trips the FK
(`SQLite error 19: FOREIGN KEY constraint failed`). To plant FK-violating orphan
rows in a test (e.g. a "missing-parent contract" pin), use
`writeWithoutTransaction { }` (autocommit mode), toggle the pragma, and restore
`= ON` before the closure exits:

```swift
try await env.db.dbWriter.writeWithoutTransaction { db in
  try db.execute(sql: "PRAGMA foreign_keys = OFF")
  try db.execute(sql: "INSERT INTO simulations (...) VALUES (...)")
  try db.execute(sql: "PRAGMA foreign_keys = ON")  // restore for later ops
}
```

### Changing a column's FK action / nullability needs a table rebuild

SQLite can't `ALTER` an existing column's FK action (`ON DELETE CASCADE` →
`SET NULL`) or nullability in place — rebuild the table (`create new_x` →
`INSERT … SELECT` → `drop x` → `rename new_x → x`). **Don't hand-roll
`PRAGMA foreign_keys = OFF`** around it — that fails inside the migration's
transaction (above). GRDB's `registerMigration` defaults to
`foreignKeyChecks: .deferred`, which already runs the body with FK checks off and
re-verifies via `PRAGMA foreign_key_check` at commit (the SQLite 12-step "Other
Kinds Of Table Schema Changes" recipe). So a plain `registerMigration("vN") { … }`
is safe: dropping the old parent does NOT cascade-delete children. The migration
test must assert **child-row survival** across the rebuild (the thing the deferred
mechanism protects), not just the new columns. First applied:
`DatabaseManager.registerV7` (made `simulations.scenarioId` nullable so a deleted
parent orphans rows rather than cascade-deleting them).

## `Data(contentsOf:)` loads the whole file into RAM

`Data(contentsOf: url)` without options reads the **entire file into memory** — it
does not mmap. For multi-GB files (model downloads) this is a real OOM hazard on
iOS (jetsam ~1.5–2 GB resident, foreground). Use `.mappedIfSafe` for read-only
mmap (the backing file must outlive the `Data`), or stream via
`FileHandle.readData(ofLength:)` + `autoreleasepool` for read-and-process
workflows. Reference idiom: `App/ModelManager.swift` `computeSHA256(of:)` (1 MB
chunks + `autoreleasepool` to bound peak resident memory). Note the idiom and the
live `Data(contentsOf:)` callsites all live in `App/**`, outside this file's
`Models/**` + `Data/**` scope — the persistence/SHA256 flavor is why the trap is
documented here. When reviewing, any `Data(contentsOf:)` on an unbounded-size file
is suspect — small config/metadata is fine; model files / download chunks need
streaming.
