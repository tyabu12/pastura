import Foundation
import Testing

@testable import Pastura

@Suite struct TurnRepositoryTests {

  /// Returns a TurnRepository backed by an in-memory DB with seeded scenario and simulation.
  private func makeTurnRepo() throws -> GRDBTurnRepository {
    let manager = try DatabaseManager.inMemory()
    let scenarioRepo = GRDBScenarioRepository(dbWriter: manager.dbWriter)
    let simRepo = GRDBSimulationRepository(dbWriter: manager.dbWriter)

    // Seed scenario and simulation for FK constraints
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

    return GRDBTurnRepository(dbWriter: manager.dbWriter)
  }

  private func makeTurn(
    id: String = "t1",
    simulationId: String = "sim1",
    roundNumber: Int = 1,
    phaseType: String = "speak_all",
    agentName: String? = "Alice"
  ) -> TurnRecord {
    TurnRecord(
      id: id, simulationId: simulationId,
      roundNumber: roundNumber, phaseType: phaseType,
      agentName: agentName, rawOutput: "raw output",
      parsedOutputJSON: #"{"statement":"hello"}"#,
      createdAt: Date())
  }

  @Test func saveAndFetchBySimulationId() throws {
    let turnRepo = try makeTurnRepo()
    try turnRepo.save(makeTurn(id: "t1", agentName: "Alice"))
    try turnRepo.save(makeTurn(id: "t2", agentName: "Bob"))

    let turns = try turnRepo.fetchBySimulationId("sim1")
    #expect(turns.count == 2)
  }

  @Test func fetchBySimulationIdReturnsOrderedBySequenceNumber() throws {
    let turnRepo = try makeTurnRepo()
    // sequenceNumber order intentionally differs from createdAt order
    // to prove sequenceNumber takes priority.
    let early = Date(timeIntervalSince1970: 1000)
    let late = Date(timeIntervalSince1970: 2000)

    try turnRepo.save(
      TurnRecord(
        id: "t2", simulationId: "sim1",
        roundNumber: 1, phaseType: "speak_all",
        agentName: "Bob", rawOutput: "raw",
        parsedOutputJSON: "{}",
        sequenceNumber: 2, createdAt: early))
    try turnRepo.save(
      TurnRecord(
        id: "t1", simulationId: "sim1",
        roundNumber: 1, phaseType: "speak_all",
        agentName: "Alice", rawOutput: "raw",
        parsedOutputJSON: "{}",
        sequenceNumber: 1, createdAt: late))

    let turns = try turnRepo.fetchBySimulationId("sim1")
    #expect(turns.first?.id == "t1")
    #expect(turns.last?.id == "t2")
  }

  @Test func fetchBySimulationIdFallsBackToCreatedAtWhenSequenceNumberEqual() throws {
    let turnRepo = try makeTurnRepo()
    // Both have sequenceNumber 0 (pre-migration data) — should fall back to createdAt.
    let early = Date(timeIntervalSince1970: 1000)
    let late = Date(timeIntervalSince1970: 2000)

    try turnRepo.save(
      TurnRecord(
        id: "t2", simulationId: "sim1",
        roundNumber: 1, phaseType: "speak_all",
        agentName: "Bob", rawOutput: "raw",
        parsedOutputJSON: "{}", createdAt: late))
    try turnRepo.save(
      TurnRecord(
        id: "t1", simulationId: "sim1",
        roundNumber: 1, phaseType: "speak_all",
        agentName: "Alice", rawOutput: "raw",
        parsedOutputJSON: "{}", createdAt: early))

    let turns = try turnRepo.fetchBySimulationId("sim1")
    #expect(turns.first?.id == "t1")
    #expect(turns.last?.id == "t2")
  }

  @Test func fetchBySimulationIdReturnsEmptyForMissing() throws {
    let turnRepo = try makeTurnRepo()
    let turns = try turnRepo.fetchBySimulationId("nonexistent")
    #expect(turns.isEmpty)
  }

  @Test func saveBatchInsertsMultipleRecords() throws {
    let turnRepo = try makeTurnRepo()
    let records = (1...5).map { i in
      makeTurn(id: "t\(i)", agentName: "Agent\(i)")
    }

    try turnRepo.saveBatch(records)

    let turns = try turnRepo.fetchBySimulationId("sim1")
    #expect(turns.count == 5)
  }

  @Test func fetchBySimulationAndRound() throws {
    let turnRepo = try makeTurnRepo()
    // Round 1
    try turnRepo.save(makeTurn(id: "t1", roundNumber: 1, agentName: "Alice"))
    try turnRepo.save(makeTurn(id: "t2", roundNumber: 1, agentName: "Bob"))
    // Round 2
    try turnRepo.save(makeTurn(id: "t3", roundNumber: 2, agentName: "Alice"))

    let round1 = try turnRepo.fetchBySimulationAndRound("sim1", round: 1)
    #expect(round1.count == 2)

    let round2 = try turnRepo.fetchBySimulationAndRound("sim1", round: 2)
    #expect(round2.count == 1)

    let round3 = try turnRepo.fetchBySimulationAndRound("sim1", round: 3)
    #expect(round3.isEmpty)
  }

  @Test func deleteBySimulationIdRemovesAllTurns() throws {
    let turnRepo = try makeTurnRepo()
    try turnRepo.saveBatch([
      makeTurn(id: "t1"),
      makeTurn(id: "t2"),
      makeTurn(id: "t3")
    ])

    try turnRepo.deleteBySimulationId("sim1")

    let turns = try turnRepo.fetchBySimulationId("sim1")
    #expect(turns.isEmpty)
  }
}
