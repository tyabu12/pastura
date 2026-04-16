import Foundation
import Testing

@testable import Pastura

@Suite struct CodePhaseEventRepositoryTests {

  private func makeRepo() throws -> GRDBCodePhaseEventRepository {
    let manager = try DatabaseManager.inMemory()
    let scenarioRepo = GRDBScenarioRepository(dbWriter: manager.dbWriter)
    let simRepo = GRDBSimulationRepository(dbWriter: manager.dbWriter)

    try scenarioRepo.save(
      ScenarioRecord(
        id: "s1", name: "Test", yamlDefinition: "yaml",
        isPreset: false, createdAt: Date(), updatedAt: Date()))
    try simRepo.save(
      SimulationRecord(
        id: "sim1", scenarioId: "s1",
        status: "running", currentRound: 1, currentPhaseIndex: 0,
        stateJSON: "{}", configJSON: nil,
        createdAt: Date(), updatedAt: Date()))

    return GRDBCodePhaseEventRepository(dbWriter: manager.dbWriter)
  }

  private func makeRecord(
    id: String = "c1",
    simulationId: String = "sim1",
    roundNumber: Int = 1,
    phaseType: String = "eliminate",
    sequenceNumber: Int = 1,
    createdAt: Date = Date()
  ) -> CodePhaseEventRecord {
    CodePhaseEventRecord(
      id: id, simulationId: simulationId,
      roundNumber: roundNumber, phaseType: phaseType,
      sequenceNumber: sequenceNumber,
      payloadJSON: #"{"summary":{"text":"hi"}}"#,
      createdAt: createdAt)
  }

  @Test func saveAndFetchBySimulationId() throws {
    let repo = try makeRepo()
    try repo.save(makeRecord(id: "c1"))
    try repo.save(makeRecord(id: "c2", sequenceNumber: 2))

    let records = try repo.fetchBySimulationId("sim1")
    #expect(records.count == 2)
  }

  @Test func fetchBySimulationIdReturnsOrderedBySequenceNumber() throws {
    let repo = try makeRepo()
    // Insert out of order to prove ordering is by sequenceNumber.
    try repo.save(makeRecord(id: "c3", sequenceNumber: 3))
    try repo.save(makeRecord(id: "c1", sequenceNumber: 1))
    try repo.save(makeRecord(id: "c2", sequenceNumber: 2))

    let records = try repo.fetchBySimulationId("sim1")
    #expect(records.map(\.id) == ["c1", "c2", "c3"])
  }

  @Test func fetchBySimulationIdReturnsEmptyForMissing() throws {
    let repo = try makeRepo()
    let records = try repo.fetchBySimulationId("nonexistent")
    #expect(records.isEmpty)
  }

  @Test func saveBatchInsertsMultipleRecords() throws {
    let repo = try makeRepo()
    let records = (1...4).map { i in
      makeRecord(id: "c\(i)", sequenceNumber: i)
    }

    try repo.saveBatch(records)

    let fetched = try repo.fetchBySimulationId("sim1")
    #expect(fetched.count == 4)
  }

  @Test func fetchBySimulationAndRound() throws {
    let repo = try makeRepo()
    try repo.save(makeRecord(id: "c1", roundNumber: 1, sequenceNumber: 1))
    try repo.save(makeRecord(id: "c2", roundNumber: 1, sequenceNumber: 2))
    try repo.save(makeRecord(id: "c3", roundNumber: 2, sequenceNumber: 3))

    let round1 = try repo.fetchBySimulationAndRound("sim1", round: 1)
    #expect(round1.count == 2)

    let round2 = try repo.fetchBySimulationAndRound("sim1", round: 2)
    #expect(round2.count == 1)

    let round3 = try repo.fetchBySimulationAndRound("sim1", round: 3)
    #expect(round3.isEmpty)
  }

  @Test func deleteBySimulationIdRemovesAllRecords() throws {
    let repo = try makeRepo()
    try repo.saveBatch([
      makeRecord(id: "c1", sequenceNumber: 1),
      makeRecord(id: "c2", sequenceNumber: 2),
      makeRecord(id: "c3", sequenceNumber: 3)
    ])

    try repo.deleteBySimulationId("sim1")

    let records = try repo.fetchBySimulationId("sim1")
    #expect(records.isEmpty)
  }
}
