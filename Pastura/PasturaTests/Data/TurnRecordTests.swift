import Foundation
import GRDB
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1))) struct TurnRecordTests {

  /// Creates an in-memory DB with a scenario and simulation already inserted.
  private func makeManagerWithSimulation() throws -> DatabaseManager {
    let manager = try DatabaseManager.inMemory()
    let now = Date()
    try manager.dbWriter.write { db in
      var scenario = ScenarioRecord(
        id: "s1", name: "Test", yamlDefinition: "yaml",
        isPreset: false, createdAt: now, updatedAt: now)
      try scenario.insert(db)

      var sim = SimulationRecord(
        id: "sim1", scenarioId: "s1",
        status: "running", currentRound: 1, currentPhaseIndex: 0,
        stateJSON: "{}", configJSON: nil,
        createdAt: now, updatedAt: now)
      try sim.insert(db)
    }
    return manager
  }

  @Test func insertAndFetchBySimulationId() throws {
    let manager = try makeManagerWithSimulation()
    let now = Date()

    try manager.dbWriter.write { db in
      var turn = TurnRecord(
        id: "t1", simulationId: "sim1",
        roundNumber: 1, phaseType: "speak_all",
        agentName: "Alice", rawOutput: "raw response",
        parsedOutputJSON: #"{"statement":"hello"}"#,
        createdAt: now)
      try turn.insert(db)
    }

    let turns = try manager.dbWriter.read { db in
      try TurnRecord.filter(Column("simulationId") == "sim1").fetchAll(db)
    }

    #expect(turns.count == 1)
    #expect(turns.first?.agentName == "Alice")
    #expect(turns.first?.rawOutput == "raw response")
    #expect(turns.first?.parsedOutputJSON == #"{"statement":"hello"}"#)
  }

  @Test func nullableAgentNameForCodePhases() throws {
    let manager = try makeManagerWithSimulation()
    let now = Date()

    try manager.dbWriter.write { db in
      var turn = TurnRecord(
        id: "t1", simulationId: "sim1",
        roundNumber: 1, phaseType: "score_calc",
        agentName: nil, rawOutput: "",
        parsedOutputJSON: "{}",
        createdAt: now)
      try turn.insert(db)
    }

    let fetched = try manager.dbWriter.read { db in
      try TurnRecord.fetchOne(db, key: "t1")
    }

    #expect(fetched?.agentName == nil)
    #expect(fetched?.phaseType == "score_calc")
  }

  @Test func fetchBySimulationAndRound() throws {
    let manager = try makeManagerWithSimulation()
    let now = Date()

    try manager.dbWriter.write { db in
      // Round 1 turns
      for (i, name) in ["Alice", "Bob"].enumerated() {
        var turn = TurnRecord(
          id: "t\(i)", simulationId: "sim1",
          roundNumber: 1, phaseType: "speak_all",
          agentName: name, rawOutput: "raw",
          parsedOutputJSON: "{}", createdAt: now)
        try turn.insert(db)
      }
      // Round 2 turn
      var turn = TurnRecord(
        id: "t2", simulationId: "sim1",
        roundNumber: 2, phaseType: "vote",
        agentName: "Alice", rawOutput: "raw",
        parsedOutputJSON: "{}", createdAt: now)
      try turn.insert(db)
    }

    let round1 = try manager.dbWriter.read { db in
      try TurnRecord
        .filter(Column("simulationId") == "sim1" && Column("roundNumber") == 1)
        .fetchAll(db)
    }

    #expect(round1.count == 2)
  }

  @Test func cascadeDeleteFromSimulation() throws {
    let manager = try makeManagerWithSimulation()
    let now = Date()

    try manager.dbWriter.write { db in
      var turn = TurnRecord(
        id: "t1", simulationId: "sim1",
        roundNumber: 1, phaseType: "speak_all",
        agentName: "Alice", rawOutput: "raw",
        parsedOutputJSON: "{}", createdAt: now)
      try turn.insert(db)

      // Delete the simulation
      try db.execute(sql: "DELETE FROM simulations WHERE id = ?", arguments: ["sim1"])

      let count = try TurnRecord.fetchCount(db)
      #expect(count == 0)
    }
  }
}
