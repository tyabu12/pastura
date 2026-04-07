import Foundation
import GRDB
import Testing

@testable import Pastura

@Suite struct DatabaseManagerTests {

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

  @Test func cascadeDeleteScenarioRemovesSimulations() throws {
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

      // Delete scenario
      try db.execute(sql: "DELETE FROM scenarios WHERE id = ?", arguments: ["s1"])

      // Simulation should be gone
      let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM simulations")
      #expect(count == 0)
    }
  }
}

@Suite struct DataErrorTests {

  @Test func casesAreEquatable() {
    let a = DataError.databaseOpenFailed(description: "fail")
    let b = DataError.databaseOpenFailed(description: "fail")
    #expect(a == b)

    let c = DataError.recordNotFound(type: "Scenario", id: "123")
    let d = DataError.recordNotFound(type: "Scenario", id: "456")
    #expect(c != d)
  }

  @Test func conformsToError() {
    let error: any Error = DataError.encodingFailed(description: "bad json")
    #expect(error is DataError)
  }
}
