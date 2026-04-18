import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1))) struct SimulationRepositoryTests {

  private func makeRepos() throws -> (
    scenario: GRDBScenarioRepository, simulation: GRDBSimulationRepository
  ) {
    let manager = try DatabaseManager.inMemory()
    let scenarioRepo = GRDBScenarioRepository(dbWriter: manager.dbWriter)
    let simRepo = GRDBSimulationRepository(dbWriter: manager.dbWriter)

    // Seed a scenario for FK constraint
    try scenarioRepo.save(
      ScenarioRecord(
        id: "s1", name: "Test", yamlDefinition: "yaml",
        isPreset: false, createdAt: Date(), updatedAt: Date()))

    return (scenarioRepo, simRepo)
  }

  private func makeSimRecord(
    id: String = "sim1",
    status: SimulationStatus = .running,
    currentRound: Int = 0,
    currentPhaseIndex: Int = 0,
    stateJSON: String = "{}"
  ) -> SimulationRecord {
    SimulationRecord(
      id: id, scenarioId: "s1",
      status: status.rawValue,
      currentRound: currentRound,
      currentPhaseIndex: currentPhaseIndex,
      stateJSON: stateJSON, configJSON: nil,
      createdAt: Date(), updatedAt: Date())
  }

  @Test func saveAndFetchById() throws {
    let (_, simRepo) = try makeRepos()
    let record = makeSimRecord()

    try simRepo.save(record)
    let fetched = try simRepo.fetchById("sim1")

    #expect(fetched != nil)
    #expect(fetched?.scenarioId == "s1")
    #expect(fetched?.simulationStatus == .running)
  }

  @Test func fetchByIdReturnsNilForMissing() throws {
    let (_, simRepo) = try makeRepos()
    let fetched = try simRepo.fetchById("nonexistent")
    #expect(fetched == nil)
  }

  @Test func fetchByScenarioId() throws {
    let (_, simRepo) = try makeRepos()
    for i in 1...3 {
      try simRepo.save(makeSimRecord(id: "sim\(i)"))
    }

    let results = try simRepo.fetchByScenarioId("s1")
    #expect(results.count == 3)
  }

  @Test func fetchByScenarioIdReturnsEmptyForMissing() throws {
    let (_, simRepo) = try makeRepos()
    let results = try simRepo.fetchByScenarioId("nonexistent")
    #expect(results.isEmpty)
  }

  @Test func updateStateModifiesTargetFields() throws {
    let (_, simRepo) = try makeRepos()
    try simRepo.save(makeSimRecord())

    try simRepo.updateState(
      "sim1",
      stateJSON: #"{"scores":{"Alice":5}}"#,
      currentRound: 3,
      currentPhaseIndex: 2)

    let fetched = try simRepo.fetchById("sim1")
    #expect(fetched?.stateJSON == #"{"scores":{"Alice":5}}"#)
    #expect(fetched?.currentRound == 3)
    #expect(fetched?.currentPhaseIndex == 2)
    // Status should remain unchanged
    #expect(fetched?.status == "running")
  }

  @Test func updateStateThrowsForMissingRecord() throws {
    let (_, simRepo) = try makeRepos()
    #expect(throws: DataError.self) {
      try simRepo.updateState(
        "nonexistent", stateJSON: "{}",
        currentRound: 0, currentPhaseIndex: 0)
    }
  }

  @Test func updateStatusChangesOnlyStatus() throws {
    let (_, simRepo) = try makeRepos()
    try simRepo.save(makeSimRecord(stateJSON: #"{"scores":{}}"#))

    try simRepo.updateStatus("sim1", status: .completed)

    let fetched = try simRepo.fetchById("sim1")
    #expect(fetched?.simulationStatus == .completed)
    // State should remain unchanged
    #expect(fetched?.stateJSON == #"{"scores":{}}"#)
  }

  @Test func updateStatusThrowsForMissingRecord() throws {
    let (_, simRepo) = try makeRepos()
    #expect(throws: DataError.self) {
      try simRepo.updateStatus("nonexistent", status: .paused)
    }
  }

  @Test func deleteRemovesRecord() throws {
    let (_, simRepo) = try makeRepos()
    try simRepo.save(makeSimRecord())

    try simRepo.delete("sim1")
    let fetched = try simRepo.fetchById("sim1")
    #expect(fetched == nil)
  }
}
