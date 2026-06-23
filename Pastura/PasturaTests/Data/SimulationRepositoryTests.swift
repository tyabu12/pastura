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

  @Test func fetchByStatusReturnsOnlyMatchingStatus() throws {
    let (_, simRepo) = try makeRepos()
    try simRepo.save(makeSimRecord(id: "run1", status: .running))
    try simRepo.save(makeSimRecord(id: "paused1", status: .paused))
    try simRepo.save(makeSimRecord(id: "done1", status: .completed))

    let paused = try simRepo.fetchByStatus(.paused)
    #expect(paused.map(\.id) == ["paused1"])
    #expect(paused.first?.simulationStatus == .paused)
  }

  @Test func fetchByStatusReturnsEmptyWhenNoneMatch() throws {
    let (_, simRepo) = try makeRepos()
    try simRepo.save(makeSimRecord(id: "run1", status: .running))
    #expect(try simRepo.fetchByStatus(.paused).isEmpty)
  }

  @Test func fetchByStatusOrdersNewestFirst() throws {
    let (_, simRepo) = try makeRepos()
    // Distinct createdAt so the desc ordering is observable.
    for (id, offset) in [("old", 0.0), ("mid", 100.0), ("new", 200.0)] {
      var record = makeSimRecord(id: id, status: .paused)
      record.createdAt = Date(timeIntervalSince1970: offset)
      try simRepo.save(record)
    }
    #expect(try simRepo.fetchByStatus(.paused).map(\.id) == ["new", "mid", "old"])
  }

  @Test func completedRunCountsGroupByScenarioExcludingPausedAndOrphaned() throws {
    let (scenarioRepo, simRepo) = try makeRepos()  // seeds s1
    try scenarioRepo.save(
      ScenarioRecord(
        id: "s2", name: "Two", yamlDefinition: "yaml",
        isPreset: false, createdAt: Date(), updatedAt: Date()))
    try scenarioRepo.save(
      ScenarioRecord(
        id: "s3", name: "Three", yamlDefinition: "yaml",
        isPreset: false, createdAt: Date(), updatedAt: Date()))

    // s1: 2 completed + 1 paused (paused must be excluded).
    try simRepo.save(makeSimRecord(id: "c1", status: .completed))
    try simRepo.save(makeSimRecord(id: "c2", status: .completed))
    try simRepo.save(makeSimRecord(id: "p1", status: .paused))
    // s2: 1 completed.
    var s2Run = makeSimRecord(id: "c3", status: .completed)
    s2Run.scenarioId = "s2"
    try simRepo.save(s2Run)
    // s3: 1 completed, then s3 deleted → run orphaned (scenarioId NULL),
    // which must be excluded from the per-scenario count.
    var orphan = makeSimRecord(id: "orph", status: .completed)
    orphan.scenarioId = "s3"
    try simRepo.save(orphan)
    try scenarioRepo.delete("s3")

    let counts = try simRepo.completedRunCountsByScenarioId()
    #expect(counts == ["s1": 2, "s2": 1])
  }

  @Test func completedRunCountsEmptyWhenNoCompletedRuns() throws {
    let (_, simRepo) = try makeRepos()
    try simRepo.save(makeSimRecord(id: "run1", status: .running))
    try simRepo.save(makeSimRecord(id: "paused1", status: .paused))
    #expect(try simRepo.completedRunCountsByScenarioId().isEmpty)
  }

  @Test func fetchOrphanedReturnsOnlyRunsWhoseScenarioWasDeleted() throws {
    let (scenarioRepo, simRepo) = try makeRepos()
    try scenarioRepo.save(
      ScenarioRecord(
        id: "s2", name: "Other", yamlDefinition: "yaml",
        isPreset: false, createdAt: Date(), updatedAt: Date()))
    try simRepo.save(makeSimRecord(id: "sim1"))  // references s1
    var sim2 = makeSimRecord(id: "sim2")
    sim2.scenarioId = "s2"
    try simRepo.save(sim2)

    // No orphans while both scenarios exist.
    #expect(try simRepo.fetchOrphaned().isEmpty)

    // Deleting s1 orphans sim1 (SET NULL); sim2 keeps its FK.
    try scenarioRepo.delete("s1")
    let orphans = try simRepo.fetchOrphaned()
    #expect(orphans.map(\.id) == ["sim1"])
    #expect(orphans.first?.scenarioId == nil)
    #expect(try simRepo.fetchById("sim2")?.scenarioId == "s2")
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

  @Test func deleteAllRemovesEveryRunAndCascades() throws {
    // Inline setup so we can share the same DatabaseManager across repos
    // without touching makeRepos() and its existing call sites.
    let manager = try DatabaseManager.inMemory()
    let scenarioRepo = GRDBScenarioRepository(dbWriter: manager.dbWriter)
    let simRepo = GRDBSimulationRepository(dbWriter: manager.dbWriter)
    let turnRepo = GRDBTurnRepository(dbWriter: manager.dbWriter)

    try scenarioRepo.save(
      ScenarioRecord(
        id: "s1", name: "Test", yamlDefinition: "yaml",
        isPreset: false, createdAt: Date(), updatedAt: Date()))

    try simRepo.save(makeSimRecord(id: "sim1"))
    try simRepo.save(makeSimRecord(id: "sim2"))

    try turnRepo.save(
      TurnRecord(
        id: "t1", simulationId: "sim1",
        roundNumber: 1, phaseType: "speak_all",
        agentName: "Alice", rawOutput: "raw",
        parsedOutputJSON: #"{"statement":"hello"}"#,
        createdAt: Date()))

    try simRepo.deleteAll()

    #expect(try simRepo.fetchById("sim1") == nil)
    #expect(try simRepo.fetchById("sim2") == nil)
    #expect(try turnRepo.fetchBySimulationId("sim1").isEmpty)
  }

  @Test func pastResultsByteCountIsZeroForEmptyDatabase() throws {
    let (_, simRepo) = try makeRepos()
    // The measure sums result-table content only — not the SQLite schema
    // pages. A migrated-but-empty DB has zero runs, so the size is exactly
    // 0 (the #770 fix: "Storage used" reaches 0 once results are cleared,
    // unlike the old whole-DB `page_count * page_size` measure).
    #expect(try simRepo.pastResultsByteCount() == 0)
  }

  @Test func pastResultsByteCountGrowsAfterHeavyInserts() throws {
    let (_, simRepo) = try makeRepos()
    let before = try simRepo.pastResultsByteCount()

    // Insert large-`stateJSON` rows. `stateJSON` is one of the two heavy
    // columns the advisory cap exists to bound (ADR-015 §2), and is summed
    // by the content measure, so the count strictly increases.
    let bulkyState = "{\"pad\":\"\(String(repeating: "x", count: 8_000))\"}"
    for index in 0..<40 {
      try simRepo.save(makeSimRecord(id: "sim\(index)", stateJSON: bulkyState))
    }

    #expect(try simRepo.pastResultsByteCount() > before)
  }

  @Test func pastResultsByteCountExcludesScenarios() throws {
    let (scenarioRepo, simRepo) = try makeRepos()
    // Save a scenario with a deliberately large `yamlDefinition` and no
    // simulation runs. The measure must ignore the `scenarios` table
    // entirely (the #770 root cause: scenarios — incl. re-seeded presets —
    // survive clear-all but are not "results"), so the size stays 0.
    try scenarioRepo.save(
      ScenarioRecord(
        id: "big", name: "Big",
        yamlDefinition: String(repeating: "y", count: 20_000),
        isPreset: true, createdAt: Date(), updatedAt: Date()))

    #expect(try simRepo.pastResultsByteCount() == 0)
  }

  @Test func pastResultsByteCountIsZeroAfterDeleteAllWithScenariosPresent() throws {
    let manager = try DatabaseManager.inMemory()
    let scenarioRepo = GRDBScenarioRepository(dbWriter: manager.dbWriter)
    let simRepo = GRDBSimulationRepository(dbWriter: manager.dbWriter)
    let turnRepo = GRDBTurnRepository(dbWriter: manager.dbWriter)

    try scenarioRepo.save(
      ScenarioRecord(
        id: "s1", name: "Test", yamlDefinition: "yaml",
        isPreset: false, createdAt: Date(), updatedAt: Date()))
    try simRepo.save(makeSimRecord(id: "sim1", stateJSON: "{\"pad\":\"data\"}"))
    try turnRepo.save(
      TurnRecord(
        id: "t1", simulationId: "sim1",
        roundNumber: 1, phaseType: "speak_all",
        agentName: "Alice", rawOutput: "raw",
        parsedOutputJSON: #"{"statement":"hello"}"#,
        createdAt: Date()))
    #expect(try simRepo.pastResultsByteCount() > 0)

    try simRepo.deleteAll()

    // Runs are gone → size is 0, even though the scenario row survives
    // (clear-all never touches `scenarios`).
    #expect(try simRepo.pastResultsByteCount() == 0)
    #expect(try scenarioRepo.fetchById("s1") != nil)
  }
}
