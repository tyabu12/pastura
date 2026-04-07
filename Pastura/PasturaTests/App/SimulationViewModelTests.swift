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

  // MARK: - Round / Phase Lifecycle

  @Test func handleEventRoundCompletedUpdatesScores() throws {
    let (sut, scenario) = try makeSUT()
    let newScores = ["Alice": 5, "Bob": 3]

    sut.handleEvent(.roundCompleted(round: 1, scores: newScores), scenario: scenario)

    #expect(sut.scores == newScores)
    #expect(sut.logEntries.count == 1)
    if case .roundCompleted(let round, let scores) = sut.logEntries.first?.kind {
      #expect(round == 1)
      #expect(scores == newScores)
    } else {
      Issue.record("Expected .roundCompleted log entry")
    }
  }

  @Test func handleEventPhaseStartedAppendsLogEntry() throws {
    let (sut, scenario) = try makeSUT()

    sut.handleEvent(.phaseStarted(phaseType: .speakAll, phaseIndex: 0), scenario: scenario)

    #expect(sut.logEntries.count == 1)
    if case .phaseStarted(let phaseType) = sut.logEntries.first?.kind {
      #expect(phaseType == .speakAll)
    } else {
      Issue.record("Expected .phaseStarted log entry")
    }
  }

  @Test func handleEventPhaseCompletedIsIgnored() throws {
    let (sut, scenario) = try makeSUT()

    sut.handleEvent(.phaseCompleted(phaseType: .speakAll, phaseIndex: 0), scenario: scenario)

    #expect(sut.logEntries.isEmpty)
  }

  @Test func handleEventSimulationPausedIsIgnored() throws {
    let (sut, scenario) = try makeSUT()

    sut.handleEvent(.simulationPaused(round: 1, phaseIndex: 0), scenario: scenario)

    #expect(sut.logEntries.isEmpty)
  }

  @Test func handleEventErrorSetsErrorMessageAndAppendsLog() throws {
    let (sut, scenario) = try makeSUT()

    sut.handleEvent(.error(.retriesExhausted), scenario: scenario)

    #expect(sut.errorMessage != nil)
    #expect(sut.logEntries.count == 1)
    if case .error = sut.logEntries.first?.kind {
      // OK
    } else {
      Issue.record("Expected .error log entry")
    }
  }

  @Test func handleEventMultipleRoundsProgressesState() throws {
    let (sut, scenario) = try makeSUT()

    sut.handleEvent(.roundStarted(round: 1, totalRounds: 3), scenario: scenario)
    sut.handleEvent(
      .roundCompleted(round: 1, scores: ["Alice": 2, "Bob": 1]), scenario: scenario)
    sut.handleEvent(.roundStarted(round: 2, totalRounds: 3), scenario: scenario)

    #expect(sut.currentRound == 2)
    #expect(sut.scores == ["Alice": 2, "Bob": 1])
    #expect(sut.logEntries.count == 3)
  }
}
