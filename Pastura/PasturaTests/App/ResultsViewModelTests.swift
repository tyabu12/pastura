import Foundation
import GRDB
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ResultsViewModelTests {

  // MARK: - Test Helpers (internal — siblings in `+CrossLanguageAggregation` call these)

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

    let sut = ResultsViewModel(
      scenarioRepository: scenarioRepo,
      simulationRepository: simRepo,
      turnRepository: turnRepo
    )
    return ResultsSUT(
      db: db, sut: sut,
      scenarioRepo: scenarioRepo, simRepo: simRepo, turnRepo: turnRepo)
  }

  /// Seeds a scenario and a completed simulation for it. YAML defaults
  /// to a single-language `ja` definition so `ScenarioYAMLLanguage.parse`
  /// returns `"ja"` for the variant.
  func seedScenarioWithSimulation(
    scenarioRepo: GRDBScenarioRepository,
    simRepo: GRDBSimulationRepository,
    scenarioId: String,
    scenarioName: String,
    simulationId: String,
    language: String = "ja",
    sourceId: String? = nil
  ) throws {
    try scenarioRepo.save(
      ScenarioRecord(
        id: scenarioId, name: scenarioName,
        yamlDefinition: "id: \(scenarioId)\nlanguage: \(language)\nname: \(scenarioName)\n",
        isPreset: false, createdAt: Date(), updatedAt: Date(),
        sourceType: nil, sourceId: sourceId, sourceHash: nil
      ))
    try simRepo.save(
      SimulationRecord(
        id: simulationId, scenarioId: scenarioId,
        status: SimulationStatus.completed.rawValue,
        currentRound: 1, currentPhaseIndex: 0,
        stateJSON: "{}", configJSON: nil,
        createdAt: Date(), updatedAt: Date()
      ))
  }

  // MARK: - Load All Scenarios (non-aggregated path)

  @Test func loadAllSurfacesScenariosWithSimulationsAsSeparateGroups() async throws {
    let env = try makeResultsSUT()

    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "s1", scenarioName: "Prisoner's Dilemma", simulationId: "sim1"
    )
    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "s2", scenarioName: "Word Wolf", simulationId: "sim2"
    )

    await env.sut.load(scope: .aggregate, deviceLanguage: "ja")

    #expect(env.sut.groups.count == 2)
    #expect(env.sut.isLoading == false)
    #expect(env.sut.errorMessage == nil)

    let names = Set(env.sut.groups.map(\.sectionName))
    #expect(names == ["Prisoner's Dilemma", "Word Wolf"])
  }

  @Test func loadAllExcludesScenariosWithNoSimulations() async throws {
    let env = try makeResultsSUT()

    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "s1", scenarioName: "Has Results", simulationId: "sim1"
    )
    // Scenario with no simulations
    try env.scenarioRepo.save(
      ScenarioRecord(
        id: "s2", name: "Empty",
        yamlDefinition: "id: s2\nlanguage: ja\nname: Empty\n",
        isPreset: false, createdAt: Date(), updatedAt: Date()
      ))
    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "s3", scenarioName: "Also Has Results", simulationId: "sim2"
    )

    await env.sut.load(scope: .aggregate, deviceLanguage: "ja")

    #expect(env.sut.groups.count == 2)
    let names = Set(env.sut.groups.map(\.sectionName))
    #expect(!names.contains("Empty"))
  }

  // MARK: - Load Specific Scenario (Detail entry-point)

  @Test func loadSpecificScenarioFiltersCorrectly() async throws {
    let env = try makeResultsSUT()

    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "s1", scenarioName: "Target", simulationId: "sim1"
    )
    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "s2", scenarioName: "Other", simulationId: "sim2"
    )

    await env.sut.load(scope: .scenario("s1"))

    #expect(env.sut.groups.count == 1)
    #expect(env.sut.groups.first?.sectionName == "Target")
    #expect(env.sut.groups.first?.rows.count == 1)
    #expect(env.sut.groups.first?.rows.first?.variantName == "Target")
  }

  @Test func loadSpecificScenarioMissingReturnsEmpty() async throws {
    let env = try makeResultsSUT()

    await env.sut.load(scope: .scenario("nonexistent"))

    #expect(env.sut.groups.isEmpty)
    #expect(env.sut.errorMessage == nil)
  }

  // MARK: - Silent refresh (reappear-after-delete contract)

  @Test func silentRefreshUpdatesGroupsWithoutLoadingFlash() async throws {
    let env = try makeResultsSUT()

    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "s1", scenarioName: "Target", simulationId: "sim1"
    )

    // First load establishes the group and settles isLoading to false.
    await env.sut.load(scope: .scenario("s1"))
    #expect(env.sut.groups.first?.rows.count == 1)
    #expect(env.sut.isLoading == false)

    // A second run is recorded for the same scenario, then a silent refresh.
    try env.simRepo.save(
      SimulationRecord(
        id: "sim2", scenarioId: "s1",
        status: SimulationStatus.completed.rawValue,
        currentRound: 1, currentPhaseIndex: 0,
        stateJSON: "{}", configJSON: nil,
        createdAt: Date(), updatedAt: Date()
      ))

    await env.sut.load(scope: .scenario("s1"), showLoading: false)

    // The silent refresh picked up the new run (it actually ran)...
    #expect(env.sut.groups.first?.rows.count == 2)
    // ...without flipping the spinner on (the no-flash contract).
    #expect(env.sut.isLoading == false)
  }

  // MARK: - Load Turns

  @Test func loadTurnsReturnsTurnRecords() async throws {
    let env = try makeResultsSUT()

    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "s1", scenarioName: "Test", simulationId: "sim1"
    )
    let turns = (1...3).map { i in
      TurnRecord(
        id: "t\(i)", simulationId: "sim1",
        roundNumber: 1, phaseType: "speak_all",
        agentName: "Agent\(i)",
        rawOutput: #"{"statement": "hello"}"#,
        parsedOutputJSON: #"{"statement":"hello"}"#,
        createdAt: Date()
      )
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

  // MARK: - Decode State

  @Test func decodeStateFromValidJSON() throws {
    let state = SimulationState(
      scores: ["Alice": 10, "Bob": 5],
      eliminated: ["Alice": false, "Bob": false],
      conversationLog: [],
      lastOutputs: [:],
      voteResults: [:],
      pairings: [],
      variables: [:],
      currentRound: 2
    )
    let stateJSON = String(data: try JSONEncoder().encode(state), encoding: .utf8)!

    let record = SimulationRecord(
      id: "sim1", scenarioId: "s1",
      status: "completed", currentRound: 2, currentPhaseIndex: 0,
      stateJSON: stateJSON, configJSON: nil,
      createdAt: Date(), updatedAt: Date()
    )

    let env = try makeResultsSUT()
    let decoded = env.sut.decodeState(from: record)

    #expect(decoded != nil)
    #expect(decoded?.scores["Alice"] == 10)
    #expect(decoded?.scores["Bob"] == 5)
    #expect(decoded?.currentRound == 2)
  }

  @Test func decodeStateReturnsNilForInvalidJSON() throws {
    let record = SimulationRecord(
      id: "sim1", scenarioId: "s1",
      status: "completed", currentRound: 1, currentPhaseIndex: 0,
      stateJSON: "not valid json", configJSON: nil,
      createdAt: Date(), updatedAt: Date()
    )

    let env = try makeResultsSUT()
    let decoded = env.sut.decodeState(from: record)

    #expect(decoded == nil)
  }

  // MARK: - Orphaned runs (deleted scenario) — v7 history preservation

  @Test func homeAggregationSurfacesOrphanedRunWithoutMergingLiveGroups() async throws {
    let env = try makeResultsSUT()

    // A live scenario + run that stays.
    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "s2", scenarioName: "Word Wolf", simulationId: "sim2")

    // A scenario + run carrying a snapshot, which we then delete to orphan
    // the run (regression: deleting a scenario must NOT erase its history).
    try env.scenarioRepo.save(
      ScenarioRecord(
        id: "s1", name: "Prisoner's Dilemma",
        yamlDefinition: "id: s1\nlanguage: ja\nname: Prisoner's Dilemma\n",
        isPreset: false, createdAt: Date(), updatedAt: Date()))
    try env.simRepo.save(
      SimulationRecord(
        id: "sim1", scenarioId: "s1",
        status: SimulationStatus.completed.rawValue,
        currentRound: 1, currentPhaseIndex: 0, stateJSON: "{}", configJSON: nil,
        createdAt: Date(), updatedAt: Date(),
        scenarioYamlSnapshot: "id: s1\nlanguage: ja\nname: Prisoner's Dilemma\n",
        scenarioNameSnapshot: "Prisoner's Dilemma"))

    try env.scenarioRepo.delete("s1")  // orphan sim1 (SET NULL)

    await env.sut.load(scope: .aggregate, deviceLanguage: "ja")

    // Both the live group and the orphaned group are present — the deleted
    // scenario's run survives and remains browsable.
    let names = env.sut.groups.map(\.sectionName)
    #expect(env.sut.groups.count == 2)
    #expect(names.contains("Word Wolf"))
    #expect(names.contains("Prisoner's Dilemma"))

    // The orphaned group did not merge into a live group: its canonical key
    // is reserved (≠ the former scenario id), and it sorts last.
    let orphanGroup = try #require(
      env.sut.groups.first { $0.sectionName == "Prisoner's Dilemma" })
    #expect(orphanGroup.rows.map(\.id) == ["sim1"])
    #expect(orphanGroup.canonicalKey != "s1")
    #expect(env.sut.groups.last?.canonicalKey == orphanGroup.canonicalKey)
  }
}
