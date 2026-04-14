// swiftlint:disable file_length
import Foundation
import Testing

@testable import Pastura

// MARK: - Test Helpers

/// Creates a configured SimulationViewModel for lifecycle testing with in-memory DB.
@MainActor
private func makeLifecycleSUT(
  contentFilter: ContentFilter = ContentFilter(blockedPatterns: ["badword"])
) throws -> (sut: SimulationViewModel, scenario: Scenario) {
  let db = try DatabaseManager.inMemory()
  let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
  let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)

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

/// LLM service that always fails on loadModel, for testing error paths.
nonisolated struct FailingLLMService: LLMService, Sendable {
  var isModelLoaded: Bool { false }
  var modelIdentifier: String { "failing-mock" }
  var backendIdentifier: String { "mock" }
  func loadModel() async throws { throw LLMError.notLoaded }
  func unloadModel() async throws {}
  func generate(system: String, user: String) async throws -> String {
    throw LLMError.notLoaded
  }
}

// MARK: - Lifecycle Integration Tests

/// Lifecycle tests use real SimulationRunner + MockLLMService, requiring serialized execution.
@Suite(.serialized)
@MainActor
// swiftlint:disable:next type_body_length
struct SimulationViewModelLifecycleTests {

  @Test func runResetsStateAndCompletesSuccessfully() async throws {
    let (sut, _) = try makeLifecycleSUT()
    sut.speed = .fastest

    sut.handleEvent(.error(.retriesExhausted), scenario: makeTestScenario())

    let mock = MockLLMService(responses: [
      #"{"statement": "hi from Alice"}"#,
      #"{"statement": "hi from Bob"}"#
    ])
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])]
    )

    await sut.run(scenario: scenario, llm: mock)

    #expect(sut.isRunning == false)
    #expect(sut.isCompleted == true)
    #expect(sut.errorMessage == nil)
    #expect(!sut.logEntries.isEmpty)
    #expect(sut.scores.keys.contains("Alice"))
    #expect(sut.scores.keys.contains("Bob"))
  }

  @Test func runPersistsTurnRecordsInEventOrder() async throws {
    let agents = ["Alice", "Bob", "Charlie", "Diana"]
    let db = try DatabaseManager.inMemory()
    let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
    let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
    let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    try scenarioRepo.save(
      ScenarioRecord(
        id: "test", name: "Test", yamlDefinition: "",
        isPreset: false, createdAt: Date(), updatedAt: Date()
      ))

    let sut = SimulationViewModel(
      simulationRepository: simRepo,
      turnRepository: turnRepo
    )
    sut.speed = .fastest

    // 2 rounds × 4 agents = 8 responses, consumed in order by MockLLMService.
    let responses = (1...2).flatMap { round in
      agents.map { #"{"statement": "R\#(round) from \#($0)"}"# }
    }
    let mock = MockLLMService(responses: responses)
    let scenario = makeTestScenario(
      agentNames: agents,
      rounds: 2,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])]
    )

    await sut.run(scenario: scenario, llm: mock)

    // run() drains the persistence queue before returning.
    let simId = try #require(try simRepo.fetchByScenarioId("test").first?.id)
    let allTurns = try turnRepo.fetchBySimulationId(simId)
    #expect(allTurns.count == 8)
    // sequenceNumber must be monotonically increasing (1, 2, 3, ...)
    for (i, turn) in allTurns.enumerated() {
      #expect(
        turn.sequenceNumber == i + 1,
        "Turn \(i) (\(turn.agentName ?? "?")) should have sequenceNumber \(i + 1), got \(turn.sequenceNumber)"
      )
    }
  }

  @Test func runResetsStaleStateBeforeExecution() async throws {
    let (sut, _) = try makeLifecycleSUT()
    sut.speed = .fastest

    sut.handleEvent(.error(.retriesExhausted), scenario: makeTestScenario())
    sut.handleEvent(.roundStarted(round: 2, totalRounds: 5), scenario: makeTestScenario())
    sut.handleEvent(
      .scoreUpdate(scores: ["Alice": 99, "Bob": 42]), scenario: makeTestScenario())
    sut.handleEvent(
      .elimination(agent: "Bob", voteCount: 3), scenario: makeTestScenario())

    #expect(sut.errorMessage != nil)
    #expect(sut.logEntries.count == 4)

    let mock = MockLLMService(responses: [
      #"{"statement": "fresh Alice"}"#,
      #"{"statement": "fresh Bob"}"#
    ])
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])]
    )

    await sut.run(scenario: scenario, llm: mock)

    #expect(sut.errorMessage == nil)
    #expect(sut.isCompleted == true)
    #expect(sut.scores["Alice"] == 0)
    #expect(sut.scores["Bob"] == 0)
    #expect(sut.eliminated["Bob"] == false)
    let hasStaleError = sut.logEntries.contains { entry in
      if case .error = entry.kind { return true }
      return false
    }
    #expect(!hasStaleError)
  }

  @Test func runSetsErrorWhenLLMLoadFails() async throws {
    let (sut, _) = try makeLifecycleSUT()
    sut.speed = .fastest

    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"], rounds: 1)

    await sut.run(scenario: scenario, llm: FailingLLMService())

    #expect(sut.isRunning == false)
    #expect(sut.isCompleted == false)
    #expect(sut.errorMessage != nil)
    #expect(sut.errorMessage?.contains("Failed to load LLM") == true)
  }

  // MARK: - Persistence Tests

  @Test func runCreatesSimulationRecordInDB() async throws {
    let db = try DatabaseManager.inMemory()
    let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
    let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
    let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    try scenarioRepo.save(
      ScenarioRecord(
        id: "test", name: "Test", yamlDefinition: "",
        isPreset: false, createdAt: Date(), updatedAt: Date()
      ))

    let sut = SimulationViewModel(
      simulationRepository: simRepo, turnRepository: turnRepo)
    sut.speed = .fastest

    let mock = MockLLMService(responses: [
      #"{"statement": "hello from Alice"}"#,
      #"{"statement": "hello from Bob"}"#
    ])
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])]
    )

    await sut.run(scenario: scenario, llm: mock)

    let sims = try simRepo.fetchByScenarioId("test")
    #expect(sims.count == 1)
    #expect(sims.first?.simulationStatus == .completed)
  }

  @Test func runMarksStatusFailedOnEngineError() async throws {
    let db = try DatabaseManager.inMemory()
    let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
    let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
    let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    try scenarioRepo.save(
      ScenarioRecord(
        id: "test", name: "Test", yamlDefinition: "",
        isPreset: false, createdAt: Date(), updatedAt: Date()
      ))

    let sut = SimulationViewModel(
      simulationRepository: simRepo, turnRepository: turnRepo)
    sut.speed = .fastest

    let mock = MockLLMService(responses: [])
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])]
    )

    await sut.run(scenario: scenario, llm: mock)

    #expect(sut.errorMessage != nil)
    let sims = try simRepo.fetchByScenarioId("test")
    #expect(sims.count == 1)
    #expect(sims.first?.simulationStatus == .failed)
  }

  @Test func runMarksStatusFailedOnLLMLoadFailure() async throws {
    let db = try DatabaseManager.inMemory()
    let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
    let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
    let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    try scenarioRepo.save(
      ScenarioRecord(
        id: "test", name: "Test", yamlDefinition: "",
        isPreset: false, createdAt: Date(), updatedAt: Date()
      ))

    let sut = SimulationViewModel(
      simulationRepository: simRepo, turnRepository: turnRepo)
    sut.speed = .fastest

    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"], rounds: 1)
    await sut.run(scenario: scenario, llm: FailingLLMService())

    #expect(sut.errorMessage != nil)
    let sims = try simRepo.fetchByScenarioId("test")
    #expect(sims.count == 1)
    #expect(sims.first?.simulationStatus == .failed)
  }

  // MARK: - Multi-Phase E2E Tests

  @Test func runMultiPhaseScenarioProducesCorrectLogSequence() async throws {
    let (sut, _) = try makeLifecycleSUT()
    sut.speed = .fastest

    let mock = MockLLMService(responses: [
      #"{"statement": "Alice speaks"}"#,
      #"{"statement": "Bob speaks"}"#
    ])
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [
        Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"]),
        Phase(type: .summarize, template: "Round {current_round} done")
      ]
    )

    await sut.run(scenario: scenario, llm: mock)

    #expect(sut.isCompleted == true)
    #expect(sut.errorMessage == nil)

    let kinds = sut.logEntries.map(\.kind)
    #expect(kinds.count >= 6, "Expected at least 6 log entries, got \(kinds.count)")

    if case .roundStarted(let round, let total) = kinds[0] {
      #expect(round == 1)
      #expect(total == 1)
    } else {
      Issue.record("Expected .roundStarted as first entry")
    }

    if case .phaseStarted(let phaseType) = kinds[1] {
      #expect(phaseType == .speakAll)
    } else {
      Issue.record("Expected .phaseStarted(.speakAll) as second entry")
    }

    let agentOutputCount = kinds.filter {
      if case .agentOutput = $0 { return true }
      return false
    }.count
    #expect(agentOutputCount == 2)

    let hasSummary = kinds.contains {
      if case .summary(let text) = $0 { return text.contains("done") }
      return false
    }
    #expect(hasSummary, "Expected summary entry with 'done'")
  }

  @Test func runMultiRoundScenarioUpdatesState() async throws {
    let (sut, _) = try makeLifecycleSUT()
    sut.speed = .fastest

    let mock = MockLLMService(responses: [
      #"{"statement": "Alice r1"}"#,
      #"{"statement": "Bob r1"}"#,
      #"{"statement": "Alice r2"}"#,
      #"{"statement": "Bob r2"}"#
    ])
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 2,
      phases: [
        Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])
      ]
    )

    await sut.run(scenario: scenario, llm: mock)

    #expect(sut.isCompleted == true)
    #expect(sut.errorMessage == nil)

    let roundStarts = sut.logEntries.filter {
      if case .roundStarted = $0.kind { return true }
      return false
    }
    #expect(roundStarts.count == 2)

    let agentOutputs = sut.logEntries.filter {
      if case .agentOutput = $0.kind { return true }
      return false
    }
    #expect(agentOutputs.count == 4)
  }

  @Test func runAppliesContentFilterEndToEnd() async throws {
    let db = try DatabaseManager.inMemory()
    let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
    let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
    let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    try scenarioRepo.save(
      ScenarioRecord(
        id: "test", name: "Test", yamlDefinition: "",
        isPreset: false, createdAt: Date(), updatedAt: Date()
      ))

    let sut = SimulationViewModel(
      contentFilter: ContentFilter(blockedPatterns: ["forbidden"]),
      simulationRepository: simRepo,
      turnRepository: turnRepo
    )
    sut.speed = .fastest

    let mock = MockLLMService(responses: [
      #"{"statement": "this is forbidden content"}"#,
      #"{"statement": "clean message"}"#
    ])
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [
        Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])
      ]
    )

    await sut.run(scenario: scenario, llm: mock)

    #expect(sut.isCompleted == true)

    let aliceOutput = sut.logEntries.first { entry in
      if case .agentOutput(let agent, _, _) = entry.kind { return agent == "Alice" }
      return false
    }
    if case .agentOutput(_, let output, _) = aliceOutput?.kind {
      let statement = output.statement ?? ""
      #expect(!statement.contains("forbidden"), "Content filter should mask 'forbidden'")
      #expect(statement.contains("***"), "Masked word should be replaced with '***'")
    } else {
      Issue.record("Expected Alice's agent output")
    }

    let bobOutput = sut.logEntries.first { entry in
      if case .agentOutput(let agent, _, _) = entry.kind { return agent == "Bob" }
      return false
    }
    if case .agentOutput(_, let output, _) = bobOutput?.kind {
      #expect(output.statement == "clean message")
    } else {
      Issue.record("Expected Bob's agent output")
    }
  }
}
