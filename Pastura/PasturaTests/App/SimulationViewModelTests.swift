import Foundation
import Testing

@testable import Pastura

// MARK: - Test Helpers

/// Creates a configured SimulationViewModel for testing with in-memory DB.
@MainActor
private func makeSUT(
  contentFilter: ContentFilter = ContentFilter(blockedPatterns: ["badword"])
) throws -> (sut: SimulationViewModel, scenario: Scenario) {
  let db = try DatabaseManager.inMemory()
  let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
  let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)

  // Seed a ScenarioRecord to satisfy FK constraints when persistence is triggered.
  let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
  try scenarioRepo.save(
    ScenarioRecord(
      id: "test", name: "Test", yamlDefinition: "",
      isPreset: false, createdAt: Date(), updatedAt: Date()
    ))

  let scenario = makeTestScenario(agentNames: ["Alice", "Bob"], rounds: 3)
  let sut = SimulationViewModel(
    contentFilter: contentFilter,
    simulationRepository: simRepo,
    turnRepository: turnRepo
  )
  return (sut, scenario)
}

// MARK: - Event Handling Tests

@MainActor
struct SimulationViewModelTests {

  @Test func handleEventRoundStartedUpdatesState() throws {
    let (sut, scenario) = try makeSUT()

    sut.handleEvent(.roundStarted(round: 1, totalRounds: 3), scenario: scenario)

    #expect(sut.currentRound == 1)
    #expect(sut.totalRounds == 3)
    #expect(sut.logEntries.count == 1)
    if case .roundStarted(let round, let total) = sut.logEntries.first?.kind {
      #expect(round == 1)
      #expect(total == 3)
    } else {
      Issue.record("Expected .roundStarted log entry")
    }
  }

  @Test func handleEventSimulationCompletedSetsFlag() throws {
    let (sut, scenario) = try makeSUT()

    sut.handleEvent(.simulationCompleted, scenario: scenario)

    #expect(sut.isCompleted == true)
  }
}
