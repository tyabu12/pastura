import Foundation
import GRDB
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ResultsViewModelTests {

  // MARK: - Test Helpers (internal — siblings in `+Pagination` reuse these)

  struct ResultsSUT {
    let db: DatabaseManager
    let sut: ResultsViewModel
    let scenarioRepo: GRDBScenarioRepository
    let simRepo: GRDBSimulationRepository
    let turnRepo: GRDBTurnRepository
  }

  func makeResultsSUT() throws -> ResultsSUT {
    let db = try DatabaseManager.inMemory()
    let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
    let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)

    // Fixed clock + calendar so date bucketing is deterministic.
    let sut = ResultsViewModel(
      scenarioRepository: scenarioRepo,
      simulationRepository: simRepo,
      turnRepository: turnRepo,
      now: { resultsTestNow },
      calendar: resultsTestCalendar
    )
    return ResultsSUT(
      db: db, sut: sut,
      scenarioRepo: scenarioRepo, simRepo: simRepo, turnRepo: turnRepo)
  }

  /// Seeds a scenario and a completed simulation for it. `createdAt` defaults
  /// to a fixed timestamp inside "today" relative to ``resultsTestNow`` so the
  /// run lands in the Today date bucket unless a test overrides it.
  func seedScenarioWithSimulation(
    scenarioRepo: GRDBScenarioRepository,
    simRepo: GRDBSimulationRepository,
    scenarioId: String,
    scenarioName: String,
    simulationId: String,
    createdAt: Date = resultsTestToday
  ) throws {
    try scenarioRepo.save(
      ScenarioRecord(
        id: scenarioId, name: scenarioName,
        yamlDefinition: "id: \(scenarioId)\nname: \(scenarioName)\n",
        isPreset: false, createdAt: Date(), updatedAt: Date()
      ))
    try simRepo.save(
      SimulationRecord(
        id: simulationId, scenarioId: scenarioId,
        status: SimulationStatus.completed.rawValue,
        currentRound: 1, currentPhaseIndex: 0,
        stateJSON: "{}", configJSON: nil,
        createdAt: createdAt, updatedAt: createdAt
      ))
  }

  // MARK: - Aggregate date grouping

  @Test func aggregateGroupsSameDayRunsIntoOneTodaySection() async throws {
    let env = try makeResultsSUT()

    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "s1", scenarioName: "Prisoner's Dilemma", simulationId: "sim1")
    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "s2", scenarioName: "Word Wolf", simulationId: "sim2")

    await env.sut.load(scope: .aggregate)

    // Both runs are "today" → one date section holding both runs as rows.
    #expect(env.sut.sections.count == 1)
    #expect(env.sut.sections.first?.key == "today")
    #expect(env.sut.isLoading == false)
    #expect(env.sut.errorMessage == nil)

    let variantNames = Set(env.sut.sections.flatMap { $0.rows.map(\.variantName) })
    #expect(variantNames == ["Prisoner's Dilemma", "Word Wolf"])
  }

  @Test func aggregateGroupsRunsAcrossDateBucketsInRecencyOrder() async throws {
    let env = try makeResultsSUT()

    // One run in each of three buckets relative to resultsTestNow (2026-06-17):
    // today, earlier this week, a prior month.
    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "s1", scenarioName: "Today Run", simulationId: "today",
      createdAt: resultsTestToday)
    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "s2", scenarioName: "Week Run", simulationId: "week",
      createdAt: resultsTestDate(2026, 6, 15))
    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "s3", scenarioName: "Month Run", simulationId: "lastmonth",
      createdAt: resultsTestDate(2026, 5, 20))

    await env.sut.load(scope: .aggregate)

    // Sections appear newest-bucket-first (loadedRuns is newest-first).
    #expect(env.sut.sections.map(\.key) == ["today", "week", "ym-2026-5"])
    #expect(env.sut.sections.map { $0.rows.map(\.id) } == [["today"], ["week"], ["lastmonth"]])
  }

  @Test func aggregateExcludesScenariosWithNoRuns() async throws {
    let env = try makeResultsSUT()

    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "s1", scenarioName: "Has Results", simulationId: "sim1")
    // Scenario with no simulations — contributes no row.
    try env.scenarioRepo.save(
      ScenarioRecord(
        id: "s2", name: "Empty",
        yamlDefinition: "id: s2\nname: Empty\n",
        isPreset: false, createdAt: Date(), updatedAt: Date()))
    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "s3", scenarioName: "Also Has Results", simulationId: "sim2")

    await env.sut.load(scope: .aggregate)

    let variantNames = Set(env.sut.sections.flatMap { $0.rows.map(\.variantName) })
    #expect(variantNames == ["Has Results", "Also Has Results"])
    #expect(!variantNames.contains("Empty"))
  }

  // MARK: - Record count (screen-title subtitle)

  @Test func aggregateTotalRunCountReflectsAllAndFilteredRuns() async throws {
    let env = try makeResultsSUT()

    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "p", scenarioName: "Prisoner", simulationId: "p1")
    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "p", scenarioName: "Prisoner", simulationId: "p2")
    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "w", scenarioName: "Word Wolf", simulationId: "w1")

    await env.sut.load(scope: .aggregate)
    #expect(env.sut.totalRunCount == 3)

    await env.sut.applyFilter("prisoner")
    #expect(env.sut.totalRunCount == 2)

    await env.sut.applyFilter("")
    #expect(env.sut.totalRunCount == 3)
  }

  // MARK: - Detail entry-point (per-scenario push)

  @Test func loadSpecificScenarioShowsSingleSection() async throws {
    let env = try makeResultsSUT()

    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "s1", scenarioName: "Target", simulationId: "sim1")
    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "s2", scenarioName: "Other", simulationId: "sim2")

    await env.sut.load(scope: .scenario("s1"))

    #expect(env.sut.sections.count == 1)
    #expect(env.sut.sections.first?.title == "Target")
    #expect(env.sut.sections.first?.rows.count == 1)
    #expect(env.sut.sections.first?.rows.first?.variantName == "Target")
  }

  @Test func loadSpecificScenarioMissingReturnsEmpty() async throws {
    let env = try makeResultsSUT()

    await env.sut.load(scope: .scenario("nonexistent"))

    #expect(env.sut.sections.isEmpty)
    #expect(env.sut.errorMessage == nil)
  }

  // MARK: - Silent refresh (reappear-after-delete contract)

  @Test func silentRefreshUpdatesSectionsWithoutLoadingFlash() async throws {
    let env = try makeResultsSUT()

    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "s1", scenarioName: "Target", simulationId: "sim1")

    // First load establishes the section and settles isLoading to false.
    await env.sut.load(scope: .scenario("s1"))
    #expect(env.sut.sections.first?.rows.count == 1)
    #expect(env.sut.isLoading == false)

    // A second run is recorded for the same scenario, then a silent refresh.
    try env.simRepo.save(
      SimulationRecord(
        id: "sim2", scenarioId: "s1",
        status: SimulationStatus.completed.rawValue,
        currentRound: 1, currentPhaseIndex: 0,
        stateJSON: "{}", configJSON: nil,
        createdAt: Date(), updatedAt: Date()))

    await env.sut.load(scope: .scenario("s1"), showLoading: false)

    // The silent refresh picked up the new run (it actually ran)...
    #expect(env.sut.sections.first?.rows.count == 2)
    // ...without flipping the spinner on (the no-flash contract).
    #expect(env.sut.isLoading == false)
  }

  // MARK: - Load Turns

  @Test func loadTurnsReturnsTurnRecords() async throws {
    let env = try makeResultsSUT()

    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "s1", scenarioName: "Test", simulationId: "sim1")
    let turns = (1...3).map { index in
      TurnRecord(
        id: "t\(index)", simulationId: "sim1",
        roundNumber: 1, phaseType: "speak_all",
        agentName: "Agent\(index)",
        rawOutput: #"{"statement": "hello"}"#,
        parsedOutputJSON: #"{"statement":"hello"}"#,
        createdAt: Date())
    }
    try env.turnRepo.saveBatch(turns)

    let result = await env.sut.loadTurns(simulationId: "sim1")

    #expect(result.count == 3)
    #expect(env.sut.errorMessage == nil)
  }

  @Test func loadTurnsReturnsEmptyForMissing() async throws {
    let env = try makeResultsSUT()

    let result = await env.sut.loadTurns(simulationId: "nonexistent")

    #expect(result.isEmpty)
    #expect(env.sut.errorMessage == nil)
  }

  // MARK: - Orphaned runs (deleted scenario) — v7 history preservation

  @Test func orphanedRunSurfacesWithSnapshotLabel() async throws {
    let env = try makeResultsSUT()

    // A live scenario + run that stays.
    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "s2", scenarioName: "Word Wolf", simulationId: "sim2")

    // A scenario + run carrying a snapshot, which we then delete to orphan the
    // run (regression: deleting a scenario must NOT erase its history).
    try env.scenarioRepo.save(
      ScenarioRecord(
        id: "s1", name: "Prisoner's Dilemma",
        yamlDefinition: "id: s1\nname: Prisoner's Dilemma\n",
        isPreset: false, createdAt: Date(), updatedAt: Date()))
    try env.simRepo.save(
      SimulationRecord(
        id: "sim1", scenarioId: "s1",
        status: SimulationStatus.completed.rawValue,
        currentRound: 1, currentPhaseIndex: 0, stateJSON: "{}", configJSON: nil,
        createdAt: resultsTestToday, updatedAt: resultsTestToday,
        scenarioYamlSnapshot: "id: s1\nname: Prisoner's Dilemma\n",
        scenarioNameSnapshot: "Prisoner's Dilemma"))

    try env.scenarioRepo.delete("s1")  // orphan sim1 (SET NULL)

    await env.sut.load(scope: .aggregate)

    // Both runs are "today" and both surface — the orphan's row label falls
    // back to its captured snapshot (P5 retired the prior dangling-hide).
    let rows = env.sut.sections.flatMap { $0.rows }
    let labelById = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.variantName) })
    #expect(labelById["sim1"] == "Prisoner's Dilemma")
    #expect(labelById["sim2"] == "Word Wolf")
  }

  // MARK: - Filter index reuse (#678)

  /// Regression for #678: the scenario index
  /// (`scenarioRepository.fetchAllSummaries()`) must NOT be rebuilt on every
  /// filter keystroke. The scenario set is invariant while the user types, so
  /// the filter path reuses the already-built index.
  ///
  /// `CountingScenarioRepository` pins it via `fetchAllSummaries()` count: with the fix
  /// the count stays at 1 (the initial load's build); reverting the fix
  /// (re-fetch per keystroke) would raise it to 5 (1 load + 3 distinct filters
  /// + 1 clear). The distinct, non-empty queries matter — a repeated query
  /// would hit `applyFilter`'s no-op guard and short-circuit before
  /// `reloadAggregate`, passing for the wrong reason.
  @Test func filterReusesScenarioIndexAcrossKeystrokes() async throws {
    let db = try DatabaseManager.inMemory()
    let realScenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    let countingRepo = CountingScenarioRepository(wrapping: realScenarioRepo)
    let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
    let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
    let sut = ResultsViewModel(
      scenarioRepository: countingRepo,
      simulationRepository: simRepo,
      turnRepository: turnRepo,
      now: { resultsTestNow },
      calendar: resultsTestCalendar)

    try seedScenarioWithSimulation(
      scenarioRepo: realScenarioRepo, simRepo: simRepo,
      scenarioId: "s1", scenarioName: "Prisoner's Dilemma", simulationId: "sim1")
    try seedScenarioWithSimulation(
      scenarioRepo: realScenarioRepo, simRepo: simRepo,
      scenarioId: "s2", scenarioName: "Word Wolf", simulationId: "sim2")

    await sut.load(scope: .aggregate)
    #expect(sut.sections.flatMap { $0.rows }.count == 2)
    #expect(countingRepo.fetchAllCount == 1)  // initial index build

    // Three distinct, non-empty keystrokes — each a substring LIKE that narrows
    // to "Prisoner's Dilemma" only — then a clear.
    await sut.applyFilter("Pri")
    #expect(sut.sections.flatMap { $0.rows.map(\.variantName) } == ["Prisoner's Dilemma"])
    await sut.applyFilter("Pris")
    #expect(sut.sections.flatMap { $0.rows }.count == 1)
    await sut.applyFilter("Priso")
    #expect(sut.sections.flatMap { $0.rows }.count == 1)

    // Clearing restores the full window.
    await sut.applyFilter("")
    #expect(sut.sections.flatMap { $0.rows }.count == 2)

    // The index was reused throughout — never rebuilt per keystroke.
    #expect(countingRepo.fetchAllCount == 1)
  }
}
