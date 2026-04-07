import Foundation
import Testing

@testable import Pastura

// MARK: - Test Helpers

/// Bundle returned by `makeResultsSUT` to avoid large-tuple lint violations.
private struct ResultsSUT {
  let sut: ResultsViewModel
  let scenarioRepo: GRDBScenarioRepository
  let simRepo: GRDBSimulationRepository
  let turnRepo: GRDBTurnRepository
}

@MainActor
private func makeResultsSUT() throws -> ResultsSUT {
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
    sut: sut, scenarioRepo: scenarioRepo, simRepo: simRepo, turnRepo: turnRepo)
}

/// Seeds a scenario and a completed simulation for it.
private func seedScenarioWithSimulation(
  scenarioRepo: GRDBScenarioRepository,
  simRepo: GRDBSimulationRepository,
  scenarioId: String,
  scenarioName: String,
  simulationId: String
) throws {
  try scenarioRepo.save(
    ScenarioRecord(
      id: scenarioId, name: scenarioName, yamlDefinition: "",
      isPreset: false, createdAt: Date(), updatedAt: Date()
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

// MARK: - Tests

@MainActor
struct ResultsViewModelTests {

  // MARK: - Load All Scenarios

  @Test func loadAllGroupsByScenarioName() async throws {
    let env = try makeResultsSUT()

    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "s1", scenarioName: "Prisoner's Dilemma", simulationId: "sim1"
    )
    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "s2", scenarioName: "Word Wolf", simulationId: "sim2"
    )

    await env.sut.load(scenarioId: "")

    #expect(env.sut.groups.count == 2)
    #expect(env.sut.isLoading == false)
    #expect(env.sut.errorMessage == nil)

    let names = Set(env.sut.groups.map(\.scenarioName))
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
        id: "s2", name: "Empty", yamlDefinition: "",
        isPreset: false, createdAt: Date(), updatedAt: Date()
      ))
    try seedScenarioWithSimulation(
      scenarioRepo: env.scenarioRepo, simRepo: env.simRepo,
      scenarioId: "s3", scenarioName: "Also Has Results", simulationId: "sim2"
    )

    await env.sut.load(scenarioId: "")

    #expect(env.sut.groups.count == 2)
    let names = Set(env.sut.groups.map(\.scenarioName))
    #expect(!names.contains("Empty"))
  }

  // MARK: - Load Specific Scenario

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

    await env.sut.load(scenarioId: "s1")

    #expect(env.sut.groups.count == 1)
    #expect(env.sut.groups.first?.scenarioName == "Target")
    #expect(env.sut.groups.first?.simulations.count == 1)
  }

  @Test func loadSpecificScenarioMissingReturnsEmpty() async throws {
    let env = try makeResultsSUT()

    await env.sut.load(scenarioId: "nonexistent")

    #expect(env.sut.groups.isEmpty)
    #expect(env.sut.errorMessage == nil)
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
}
