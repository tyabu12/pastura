import Foundation
import GRDB
import Testing

@testable import Pastura

@Suite struct SimulationRecordTests {

  private func makeManagerWithScenario() throws -> DatabaseManager {
    let manager = try DatabaseManager.inMemory()
    let now = Date()
    try manager.dbWriter.write { db in
      var scenario = ScenarioRecord(
        id: "s1", name: "Test", yamlDefinition: "yaml",
        isPreset: false, createdAt: now, updatedAt: now)
      try scenario.insert(db)
    }
    return manager
  }

  @Test func insertAndFetchById() throws {
    let manager = try makeManagerWithScenario()
    let now = Date()
    var record = SimulationRecord(
      id: "sim1",
      scenarioId: "s1",
      status: SimulationStatus.running.rawValue,
      currentRound: 0,
      currentPhaseIndex: 0,
      stateJSON: "{}",
      configJSON: nil,
      createdAt: now,
      updatedAt: now
    )

    try manager.dbWriter.write { db in
      try record.insert(db)
    }

    let fetched = try manager.dbWriter.read { db in
      try SimulationRecord.fetchOne(db, key: "sim1")
    }

    #expect(fetched != nil)
    #expect(fetched?.scenarioId == "s1")
    #expect(fetched?.status == "running")
    #expect(fetched?.currentRound == 0)
    #expect(fetched?.stateJSON == "{}")
    #expect(fetched?.configJSON == nil)
  }

  @Test func simulationStatusConvenience() throws {
    let manager = try makeManagerWithScenario()
    let now = Date()
    var record = SimulationRecord(
      id: "sim1", scenarioId: "s1",
      status: SimulationStatus.paused.rawValue,
      currentRound: 3, currentPhaseIndex: 1,
      stateJSON: "{}", configJSON: nil,
      createdAt: now, updatedAt: now)

    try manager.dbWriter.write { db in
      try record.insert(db)
    }

    let fetched = try manager.dbWriter.read { db in
      try SimulationRecord.fetchOne(db, key: "sim1")
    }

    #expect(fetched?.simulationStatus == .paused)
  }

  @Test func modelIdentifierAndLLMBackendRoundTrip() throws {
    let manager = try makeManagerWithScenario()
    let now = Date()
    var record = SimulationRecord(
      id: "sim1", scenarioId: "s1",
      status: SimulationStatus.completed.rawValue,
      currentRound: 5, currentPhaseIndex: 0,
      stateJSON: "{}", configJSON: nil,
      createdAt: now, updatedAt: now,
      modelIdentifier: "Gemma 4 E2B (Q4_K_M)",
      llmBackend: "llama.cpp")

    try manager.dbWriter.write { db in
      try record.insert(db)
    }

    let fetched = try manager.dbWriter.read { db in
      try SimulationRecord.fetchOne(db, key: "sim1")
    }

    #expect(fetched?.modelIdentifier == "Gemma 4 E2B (Q4_K_M)")
    #expect(fetched?.llmBackend == "llama.cpp")
  }

  @Test func modelIdentifierAndLLMBackendDefaultToNil() throws {
    // Rows inserted without explicit model metadata (e.g., created before the v3 migration
    // on TestFlight devices) decode with nil for both new fields and round-trip cleanly.
    let manager = try makeManagerWithScenario()
    let now = Date()
    var record = SimulationRecord(
      id: "sim1", scenarioId: "s1",
      status: SimulationStatus.completed.rawValue,
      currentRound: 0, currentPhaseIndex: 0,
      stateJSON: "{}", configJSON: nil,
      createdAt: now, updatedAt: now)

    try manager.dbWriter.write { db in
      try record.insert(db)
    }

    let fetched = try manager.dbWriter.read { db in
      try SimulationRecord.fetchOne(db, key: "sim1")
    }

    #expect(fetched?.modelIdentifier == nil)
    #expect(fetched?.llmBackend == nil)
  }

  @Test func cascadeDeleteFromScenario() throws {
    let manager = try makeManagerWithScenario()
    let now = Date()

    try manager.dbWriter.write { db in
      var sim = SimulationRecord(
        id: "sim1", scenarioId: "s1",
        status: "running", currentRound: 0, currentPhaseIndex: 0,
        stateJSON: "{}", configJSON: nil,
        createdAt: now, updatedAt: now)
      try sim.insert(db)

      try db.execute(sql: "DELETE FROM scenarios WHERE id = ?", arguments: ["s1"])

      let count = try SimulationRecord.fetchCount(db)
      #expect(count == 0)
    }
  }

  @Test func fetchByScenarioId() throws {
    let manager = try makeManagerWithScenario()
    let now = Date()

    try manager.dbWriter.write { db in
      for i in 1...3 {
        var sim = SimulationRecord(
          id: "sim\(i)", scenarioId: "s1",
          status: "completed", currentRound: 5, currentPhaseIndex: 0,
          stateJSON: "{}", configJSON: nil,
          createdAt: now, updatedAt: now)
        try sim.insert(db)
      }
    }

    let results = try manager.dbWriter.read { db in
      try SimulationRecord.filter(Column("scenarioId") == "s1").fetchAll(db)
    }

    #expect(results.count == 3)
  }

  @Test func updateFields() throws {
    let manager = try makeManagerWithScenario()
    let now = Date()
    var record = SimulationRecord(
      id: "sim1", scenarioId: "s1",
      status: "running", currentRound: 0, currentPhaseIndex: 0,
      stateJSON: "{}", configJSON: nil,
      createdAt: now, updatedAt: now)

    try manager.dbWriter.write { db in
      try record.insert(db)

      record.status = SimulationStatus.paused.rawValue
      record.currentRound = 3
      record.currentPhaseIndex = 2
      record.stateJSON = #"{"scores":{"Alice":5}}"#
      record.updatedAt = Date()
      try record.update(db)
    }

    let fetched = try manager.dbWriter.read { db in
      try SimulationRecord.fetchOne(db, key: "sim1")
    }

    #expect(fetched?.status == "paused")
    #expect(fetched?.currentRound == 3)
    #expect(fetched?.currentPhaseIndex == 2)
    #expect(fetched?.stateJSON == #"{"scores":{"Alice":5}}"#)
  }
}
