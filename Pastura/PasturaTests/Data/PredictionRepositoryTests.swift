import Foundation
import GRDB
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1))) struct PredictionRepositoryTests {

  /// Builds a repo over an in-memory DB and returns it plus the manager so
  /// tests can plant additional `simulations` rows for the streak cases
  /// (predictions FK-reference a run).
  private func makeEnv() throws -> (repo: GRDBPredictionRepository, manager: DatabaseManager) {
    let manager = try DatabaseManager.inMemory()
    let scenarioRepo = GRDBScenarioRepository(dbWriter: manager.dbWriter)
    try scenarioRepo.save(
      ScenarioRecord(
        id: "s1", name: "Test", yamlDefinition: "yaml",
        isPreset: false, createdAt: Date(), updatedAt: Date()))
    return (GRDBPredictionRepository(dbWriter: manager.dbWriter), manager)
  }

  /// Inserts a `simulations` row so a prediction can FK-reference it.
  private func insertSimulation(_ id: String, in manager: DatabaseManager) throws {
    let simRepo = GRDBSimulationRepository(dbWriter: manager.dbWriter)
    try simRepo.save(
      SimulationRecord(
        id: id, scenarioId: "s1",
        status: "completed", currentRound: 1, currentPhaseIndex: 0,
        stateJSON: "{}", configJSON: nil,
        createdAt: Date(), updatedAt: Date()))
  }

  private func makeRecord(
    id: String,
    simulationId: String,
    questionKind: String = "wolf",
    predictedAgent: String = "Alice",
    actualAgent: String = "Alice",
    isHit: Bool = true,
    createdAt: Date = Date(timeIntervalSince1970: 1000)
  ) -> PredictionRecord {
    PredictionRecord(
      id: id, simulationId: simulationId, questionKind: questionKind,
      predictedAgent: predictedAgent, actualAgent: actualAgent,
      isHit: isHit, createdAt: createdAt)
  }

  @Test func saveAndFetchBySimulationId() throws {
    let env = try makeEnv()
    try insertSimulation("sim1", in: env.manager)
    let record = makeRecord(id: "p1", simulationId: "sim1", isHit: true)
    try env.repo.save(record)

    let fetched = try env.repo.fetchBySimulationId("sim1")
    #expect(fetched == record)
  }

  @Test func fetchBySimulationIdReturnsNilWhenAbsent() throws {
    let env = try makeEnv()
    #expect(try env.repo.fetchBySimulationId("nope") == nil)
  }

  @Test func fetchBySimulationIdsKeysByRun() throws {
    let env = try makeEnv()
    try insertSimulation("sim1", in: env.manager)
    try insertSimulation("sim2", in: env.manager)
    try env.repo.save(makeRecord(id: "p1", simulationId: "sim1"))
    try env.repo.save(makeRecord(id: "p2", simulationId: "sim2", isHit: false))

    let map = try env.repo.fetchBySimulationIds(["sim1", "sim2", "sim3"])
    #expect(map.count == 2)
    #expect(map["sim1"]?.isHit == true)
    #expect(map["sim2"]?.isHit == false)
    #expect(map["sim3"] == nil)
  }

  @Test func fetchBySimulationIdsEmptyInputReturnsEmpty() throws {
    let env = try makeEnv()
    #expect(try env.repo.fetchBySimulationIds([]).isEmpty)
  }

  @Test func currentStreakIsZeroWhenNoRecords() throws {
    let env = try makeEnv()
    #expect(try env.repo.currentStreak() == 0)
  }

  @Test func currentStreakIsZeroWhenLatestIsMiss() throws {
    let env = try makeEnv()
    try insertSimulation("sim1", in: env.manager)
    try insertSimulation("sim2", in: env.manager)
    // Older hit, newest miss → the miss breaks the streak immediately.
    try env.repo.save(
      makeRecord(
        id: "p1", simulationId: "sim1", isHit: true,
        createdAt: Date(timeIntervalSince1970: 1000)))
    try env.repo.save(
      makeRecord(
        id: "p2", simulationId: "sim2", isHit: false,
        createdAt: Date(timeIntervalSince1970: 2000)))

    #expect(try env.repo.currentStreak() == 0)
  }

  @Test func currentStreakCountsLeadingHitsBackwards() throws {
    let env = try makeEnv()
    // createdAt order (oldest→newest): miss, hit, hit → streak of the two
    // most-recent hits, stopping at the older miss.
    struct Row {
      let id: String
      let hit: Bool
      let time: Double
    }
    let rows = [
      Row(id: "p1", hit: false, time: 1000),
      Row(id: "p2", hit: true, time: 2000),
      Row(id: "p3", hit: true, time: 3000)
    ]
    for (i, row) in rows.enumerated() {
      try insertSimulation("sim\(i)", in: env.manager)
      try env.repo.save(
        makeRecord(
          id: row.id, simulationId: "sim\(i)", isHit: row.hit,
          createdAt: Date(timeIntervalSince1970: row.time)))
    }

    #expect(try env.repo.currentStreak() == 2)
  }

  @Test func currentStreakCountsAllWhenEveryPredictionHits() throws {
    let env = try makeEnv()
    for i in 0..<3 {
      try insertSimulation("sim\(i)", in: env.manager)
      try env.repo.save(
        makeRecord(
          id: "p\(i)", simulationId: "sim\(i)", isHit: true,
          createdAt: Date(timeIntervalSince1970: Double(1000 + i * 1000))))
    }

    #expect(try env.repo.currentStreak() == 3)
  }

  @Test func deletingSimulationCascadesPrediction() throws {
    let env = try makeEnv()
    try insertSimulation("sim1", in: env.manager)
    try env.repo.save(makeRecord(id: "p1", simulationId: "sim1"))

    let simRepo = GRDBSimulationRepository(dbWriter: env.manager.dbWriter)
    try simRepo.delete("sim1")

    #expect(try env.repo.fetchBySimulationId("sim1") == nil)
  }
}
