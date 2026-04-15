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
    public var declaration: String? { fields["declaration"] }
    public var boke: String? { fields["boke"] }
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
    sourceType TEXT,   -- "gallery" for Share Board imports; NULL for local/preset
    sourceId TEXT,     -- canonical id in the source system (gallery scenario id)
    sourceHash TEXT    -- SHA256 of the fetched YAML (update-detection key)
)

simulations (
    id TEXT PRIMARY KEY,
    scenarioId TEXT NOT NULL REFERENCES scenarios ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'running',  -- running | paused | completed
    currentRound INTEGER NOT NULL DEFAULT 0,
    currentPhaseIndex INTEGER NOT NULL DEFAULT 0,
    stateJSON TEXT NOT NULL,  -- Codable SimulationState
    configJSON TEXT,
    createdAt DATETIME NOT NULL,
    updatedAt DATETIME NOT NULL
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
| `SimulationRepository` | `GRDBSimulationRepository` | save, fetchById, fetchByScenarioId, updateState, updateStatus, delete |
| `TurnRepository` | `GRDBTurnRepository` | save, saveBatch, fetchBySimulationId, fetchBySimulationAndRound, deleteBySimulationId |

Repositories take `any DatabaseWriter` in their initializer. All methods are synchronous (`throws`).
`updateState` and `updateStatus` throw `DataError.recordNotFound` for missing records.
