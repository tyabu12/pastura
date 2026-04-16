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

  // MARK: - Agent Output & Content Filter

  @Test func handleEventAgentOutputAppliesContentFilter() throws {
    let (sut, scenario) = try makeSUT()
    let rawOutput = TurnOutput(fields: ["statement": "this is badword content"])

    sut.handleEvent(
      .agentOutput(agent: "Alice", output: rawOutput, phaseType: .speakAll),
      scenario: scenario
    )

    #expect(sut.logEntries.count == 1)
    if case .agentOutput(_, let output, _) = sut.logEntries.first?.kind {
      #expect(output.statement == "this is *** content")
    } else {
      Issue.record("Expected .agentOutput log entry")
    }
  }

  @Test func handleEventAgentOutputRemovesFromThinkingAgents() throws {
    let (sut, scenario) = try makeSUT()

    sut.handleEvent(.inferenceStarted(agent: "Alice"), scenario: scenario)
    #expect(sut.thinkingAgents.contains("Alice"))

    sut.handleEvent(
      .agentOutput(
        agent: "Alice",
        output: TurnOutput(fields: ["statement": "hello"]),
        phaseType: .speakAll
      ),
      scenario: scenario
    )

    #expect(!sut.thinkingAgents.contains("Alice"))
  }

  // MARK: - Thinking Agents

  @Test func handleEventInferenceStartedAddsToThinkingAgents() throws {
    let (sut, scenario) = try makeSUT()

    sut.handleEvent(.inferenceStarted(agent: "Alice"), scenario: scenario)

    #expect(sut.thinkingAgents.contains("Alice"))
  }

  @Test func handleEventInferenceCompletedRemovesFromThinkingAgents() throws {
    let (sut, scenario) = try makeSUT()

    sut.handleEvent(.inferenceStarted(agent: "Alice"), scenario: scenario)
    sut.handleEvent(
      .inferenceCompleted(agent: "Alice", durationSeconds: 1.5), scenario: scenario)

    #expect(sut.thinkingAgents.isEmpty)
  }

  // MARK: - Score & Elimination

  @Test func handleEventScoreUpdateUpdatesScoresAndAppendsLog() throws {
    let (sut, scenario) = try makeSUT()
    let newScores = ["Alice": 10, "Bob": 5]

    sut.handleEvent(.scoreUpdate(scores: newScores), scenario: scenario)

    #expect(sut.scores == newScores)
    #expect(sut.logEntries.count == 1)
    if case .scoreUpdate(let scores) = sut.logEntries.first?.kind {
      #expect(scores == newScores)
    } else {
      Issue.record("Expected .scoreUpdate log entry")
    }
  }

  @Test func handleEventEliminationMarksAgentAndAppendsLog() throws {
    let (sut, scenario) = try makeSUT()

    sut.handleEvent(.elimination(agent: "Bob", voteCount: 2), scenario: scenario)

    #expect(sut.eliminated["Bob"] == true)
    #expect(sut.logEntries.count == 1)
    if case .elimination(let agent, let voteCount) = sut.logEntries.first?.kind {
      #expect(agent == "Bob")
      #expect(voteCount == 2)
    } else {
      Issue.record("Expected .elimination log entry")
    }
  }

  // MARK: - Output Events (Log-only)

  @Test func handleEventAssignmentAppendsLog() throws {
    let (sut, scenario) = try makeSUT()

    sut.handleEvent(.assignment(agent: "Alice", value: "wolf"), scenario: scenario)

    #expect(sut.logEntries.count == 1)
    if case .assignment(let agent, let value) = sut.logEntries.first?.kind {
      #expect(agent == "Alice")
      #expect(value == "wolf")
    } else {
      Issue.record("Expected .assignment log entry")
    }
  }

  @Test func handleEventSummaryAppendsLog() throws {
    let (sut, scenario) = try makeSUT()

    sut.handleEvent(.summary(text: "Round over"), scenario: scenario)

    #expect(sut.logEntries.count == 1)
    if case .summary(let text) = sut.logEntries.first?.kind {
      #expect(text == "Round over")
    } else {
      Issue.record("Expected .summary log entry")
    }
  }

  @Test func handleEventVoteResultsAppendsLog() throws {
    let (sut, scenario) = try makeSUT()
    let votes = ["Alice": "Bob"]
    let tallies = ["Bob": 1]

    sut.handleEvent(.voteResults(votes: votes, tallies: tallies), scenario: scenario)

    #expect(sut.logEntries.count == 1)
    if case .voteResults(let resultVotes, let resultTallies) = sut.logEntries.first?.kind {
      #expect(resultVotes == votes)
      #expect(resultTallies == tallies)
    } else {
      Issue.record("Expected .voteResults log entry")
    }
  }

  @Test func handleEventPairingResultAppendsLog() throws {
    let (sut, scenario) = try makeSUT()

    sut.handleEvent(
      .pairingResult(
        agent1: "Alice", action1: "cooperate",
        agent2: "Bob", action2: "betray"
      ),
      scenario: scenario
    )

    #expect(sut.logEntries.count == 1)
    if case .pairingResult(let agent1, let action1, let agent2, let action2) = sut.logEntries
      .first?.kind {
      #expect(agent1 == "Alice")
      #expect(action1 == "cooperate")
      #expect(agent2 == "Bob")
      #expect(action2 == "betray")
    } else {
      Issue.record("Expected .pairingResult log entry")
    }
  }

  // MARK: - Pause Delegation

  /// `pauseSimulation` carries a defensive `isRunning` guard so the BG-task
  /// expiration callback (which may fire after run() has exited — e.g., user
  /// cancelled then iOS expired) doesn't leave a stale paused state or
  /// append spurious log entries. The positive path (pause/resume during an
  /// active run) is covered by `pauseAndResumeMidRunCompletesNormally` in
  /// `SimulationViewModelLifecycleTests`.
  @Test func pauseSimulationIgnoredWhenNotRunning() throws {
    let (sut, _) = try makeSUT()
    #expect(sut.isPaused == false)
    #expect(sut.isRunning == false)

    sut.pauseSimulation(reason: "should not appear")

    #expect(sut.isPaused == false, "Guard should prevent isPaused mutation")
    #expect(sut.logEntries.isEmpty, "Guard should prevent reason from being logged")
  }
}
