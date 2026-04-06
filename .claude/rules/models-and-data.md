# Models & Data Layer Rules

## Key Data Types

### TurnOutput

Dictionary wrapper with typed accessors for common fields:

```swift
public struct TurnOutput: Codable {
    public let fields: [String: String]
    public var statement: String? { fields["statement"] }
    public var vote: String? { fields["vote"] }
    public var action: String? { fields["action"] }
    public var innerThought: String? { fields["inner_thought"] }

    public func require(_ key: String) throws -> String { ... }
}
```

### SimulationState

Must be `Codable` from day one — required for pause/resume serialization to DB.

```swift
public struct SimulationState: Codable {
    var scores: [String: Int]
    var eliminated: [String: Bool]
    var conversationLog: ConversationLog
    var lastOutputs: [String: TurnOutput]
    var voteResults: [String: Int]
    var pairings: [Pairing]
    var variables: [String: String]
    var currentRound: Int
}
```

### ConversationLog

Trims to most recent N entries for prompt injection (prevents context overflow).
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
    updatedAt DATETIME NOT NULL
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
    createdAt DATETIME NOT NULL
)

CREATE INDEX idx_turns_simulation_round ON turns(simulationId, roundNumber);
```
