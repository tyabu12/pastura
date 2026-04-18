import Foundation
import GRDB
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1))) struct CodePhaseEventRecordTests {
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
    let payloadJSON = String(
      data: try JSONEncoder().encode(
        CodePhaseEventPayload.elimination(agent: "Alice", voteCount: 2)),
      encoding: .utf8)!

    try manager.dbWriter.write { db in
      var record = CodePhaseEventRecord(
        id: "c1", simulationId: "sim1",
        roundNumber: 1, phaseType: "eliminate",
        sequenceNumber: 5,
        payloadJSON: payloadJSON,
        createdAt: now)
      try record.insert(db)
    }

    let records = try manager.dbWriter.read { db in
      try CodePhaseEventRecord
        .filter(Column("simulationId") == "sim1")
        .fetchAll(db)
    }

    #expect(records.count == 1)
    #expect(records.first?.phaseType == "eliminate")
    #expect(records.first?.sequenceNumber == 5)
    #expect(records.first?.payloadJSON == payloadJSON)
  }

  @Test func fetchBySimulationAndRound() throws {
    let manager = try makeManagerWithSimulation()
    let now = Date()

    try manager.dbWriter.write { db in
      for (i, round) in [1, 1, 2].enumerated() {
        var record = CodePhaseEventRecord(
          id: "c\(i)", simulationId: "sim1",
          roundNumber: round, phaseType: "score_calc",
          sequenceNumber: i + 1,
          payloadJSON: #"{"scoreUpdate":{"scores":{"Alice":1}}}"#,
          createdAt: now)
        try record.insert(db)
      }
    }

    let round1 = try manager.dbWriter.read { db in
      try CodePhaseEventRecord
        .filter(Column("simulationId") == "sim1" && Column("roundNumber") == 1)
        .fetchAll(db)
    }

    #expect(round1.count == 2)
  }

  @Test func cascadeDeleteFromSimulation() throws {
    let manager = try makeManagerWithSimulation()
    let now = Date()

    try manager.dbWriter.write { db in
      var record = CodePhaseEventRecord(
        id: "c1", simulationId: "sim1",
        roundNumber: 1, phaseType: "eliminate",
        sequenceNumber: 1,
        payloadJSON: "{}",
        createdAt: now)
      try record.insert(db)

      try db.execute(sql: "DELETE FROM simulations WHERE id = ?", arguments: ["sim1"])

      let count = try CodePhaseEventRecord.fetchCount(db)
      #expect(count == 0)
    }
  }

  @Test func orderingBySequenceNumber() throws {
    let manager = try makeManagerWithSimulation()
    let now = Date()

    try manager.dbWriter.write { db in
      for (id, seq) in [("c3", 3), ("c1", 1), ("c2", 2)] {
        var record = CodePhaseEventRecord(
          id: id, simulationId: "sim1",
          roundNumber: 1, phaseType: "score_calc",
          sequenceNumber: seq,
          payloadJSON: "{}", createdAt: now)
        try record.insert(db)
      }
    }

    let sorted = try manager.dbWriter.read { db in
      try CodePhaseEventRecord
        .filter(Column("simulationId") == "sim1")
        .order(Column("sequenceNumber"))
        .fetchAll(db)
    }

    #expect(sorted.map { $0.id } == ["c1", "c2", "c3"])
  }
}
