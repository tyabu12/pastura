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

/// One-shot boolean flag safely settable from `withObservationTracking`'s
/// `@Sendable` onChange closure and readable from MainActor test code.
/// Used only by `pauseSimulationInvalidatesIsPausedObservation`.
final class FiredFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var fired = false
  var value: Bool {
    lock.lock()
    defer { lock.unlock() }
    return fired
  }
  func fire() {
    lock.lock()
    fired = true
    lock.unlock()
  }
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
@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
// swiftlint:disable:next type_body_length
struct SimulationViewModelLifecycleTests {

  @Test func runResetsStateAndCompletesSuccessfully() async throws {
    let (sut, _) = try makeLifecycleSUT()
    sut.speed = .instant

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
    sut.speed = .instant

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
    sut.speed = .instant

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
    sut.speed = .instant

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
    sut.speed = .instant

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
    #expect(sims.first?.modelIdentifier == "mock")
    #expect(sims.first?.llmBackend == "mock")
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
    sut.speed = .instant

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
    sut.speed = .instant

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
    sut.speed = .instant

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
    sut.speed = .instant

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
    sut.speed = .instant

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

  @Test func cancelSimulationResumesAttachedSuspendController() async throws {
    let (sut, _) = try makeLifecycleSUT()

    // Simulate mid-run state: VM owns a controller currently parked in suspend.
    let controller = SuspendController()
    sut.suspendController = controller
    controller.requestSuspend()
    #expect(controller.isSuspendRequested() == true)

    sut.cancelSimulation()

    // cancelSimulation must wake the parked awaiter; awaitResume returns
    // immediately once the controller is in the `.resumed` state.
    await controller.awaitResume()
    #expect(sut.isCancelled == true)
  }

  @Test func simulationSurvivesSuspendResumeCycleMidRound() async throws {
    let (sut, _) = try makeLifecycleSUT()
    sut.speed = .instant

    // 2 agents × 1 phase × 1 round = 2 generate calls. The first generate will
    // throw `.suspended` (via simulateSuspendOnNextGenerate); the retry after
    // resume delivers the first response. The second agent's generate runs
    // normally.
    let mock = MockLLMService(responses: [
      #"{"statement": "first"}"#,
      #"{"statement": "second"}"#
    ])
    mock.simulateSuspendOnNextGenerate()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])]
    )

    let runTask = Task { await sut.run(scenario: scenario, llm: mock) }
    sut.runTask = runTask

    // Wait for run() to attach the SuspendController (happens synchronously
    // between two await points inside run(), so once observable it's stable).
    while sut.suspendController == nil {
      await Task.yield()
    }
    guard let controller = sut.suspendController else {
      Issue.record("Expected suspendController to be attached")
      return
    }

    // Put the controller into `.suspended` BEFORE the first generate runs so
    // LLMCaller's awaitResume() parks (otherwise mock's suspended throw would
    // hot-loop via idle-state awaitResume returning immediately).
    sut.handleWillResignActive()
    #expect(controller.isSuspendRequested() == true)

    // Give runTask time to reach awaitResume() and park. Not strictly
    // required for correctness (resume() is idempotent across states) — but
    // it exercises the park-then-wake path we actually care about.
    try await Task.sleep(for: .milliseconds(50))

    // Toggle OFF foreground path: resume() only, no reload.
    await sut.handleScenePhaseForeground()

    await runTask.value

    #expect(sut.isCompleted == true)
    #expect(sut.isCancelled == false)
    #expect(sut.errorMessage == nil)
    // Both agents produced output despite the mid-run suspend/resume cycle.
    let agents: Set<String> = Set(
      sut.logEntries.compactMap { entry in
        if case .agentOutput(let agent, _, _) = entry.kind { return agent }
        return nil
      })
    #expect(agents == Set(["Alice", "Bob"]))
    // Mock was called exactly twice (first throw doesn't consume callIndex,
    // retry + second agent each increment it).
    #expect(mock.generateCallCount == 2)
  }

  @Test func pauseAndResumeMidRunCompletesNormally() async throws {
    // Critical regression test for #84: previously, "pausing" the simulation
    // (e.g., on memoryWarning) corrupted terminal status because the old
    // proposal set `errorMessage` which `run()` defer interprets as `.failed`.
    // The new pauseSimulation/resumeSimulation API must NOT touch errorMessage
    // and a paused-then-resumed run must be persisted as `.completed`.
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
    sut.speed = .instant

    let mock = MockLLMService(responses: [
      #"{"statement": "first"}"#,
      #"{"statement": "second"}"#
    ])
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])]
    )

    let runTask = Task { await sut.run(scenario: scenario, llm: mock) }
    sut.runTask = runTask

    // Wait for run() to attach the SuspendController.
    while sut.suspendController == nil {
      await Task.yield()
    }

    // Pause via the unified API (mirrors what the memoryWarning handler does).
    sut.pauseSimulation(reason: "Memory warning — test pause")
    #expect(sut.isPaused == true)
    #expect(sut.suspendController?.isSuspendRequested() == true)

    // Reason was appended to the log so the user sees why.
    let summaryBeforeResume = sut.logEntries.last { entry in
      if case .summary(let text) = entry.kind { return text.contains("Memory warning") }
      return false
    }
    #expect(summaryBeforeResume != nil, "Expected pause reason logged as a summary entry")

    // Give the runner time to observe the pause / generate to park.
    try await Task.sleep(for: .milliseconds(50))

    // Resume — symmetric counterpart of pauseSimulation.
    sut.resumeSimulation()
    #expect(sut.isPaused == false)

    await runTask.value

    // Critical assertions — no terminal status corruption.
    #expect(sut.isCompleted == true)
    #expect(sut.isCancelled == false)
    #expect(sut.errorMessage == nil, "pauseSimulation must not set errorMessage")

    // DB row reflects the truth: the run completed, not failed.
    let sims = try simRepo.fetchByScenarioId("test")
    #expect(sims.first?.simulationStatus == .completed)
  }

  @Test func pauseSimulationInvalidatesIsPausedObservation() async throws {
    // Regression test for the memory-warning pause UI desync: `isPaused` is
    // a computed property that reads `runner.isPaused`, but `SimulationRunner`
    // is not `@Observable` — so a plain `runner.isPaused = true` does not
    // invalidate observers. The fix wraps the getter with `access(keyPath:)`
    // and the mutation with `withMutation(keyPath:)`; this test guards that
    // wiring against future refactors that strip either hook.
    //
    // Caveats on `withObservationTracking`:
    // - It is one-shot — `onChange` fires exactly once per registration. A
    //   naive "fires twice on pause+resume" extension would need to re-arm.
    // - `onChange` fires synchronously *before* the mutation commits, so
    //   reading `sut.isPaused` inside `onChange` returns the OLD value.
    //   Both the "fired at all" and "new value" assertions must live
    //   AFTER the mutating call, not inside `onChange`.
    let (sut, _) = try makeLifecycleSUT()
    sut.speed = .instant

    let mock = MockLLMService(responses: [
      #"{"statement": "first"}"#,
      #"{"statement": "second"}"#
    ])
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])]
    )

    let runTask = Task { await sut.run(scenario: scenario, llm: mock) }
    sut.runTask = runTask

    // Wait for run() to attach the SuspendController — proxy for "run is
    // in-flight" so `pauseSimulation` does not early-return on `!isRunning`.
    while sut.suspendController == nil {
      await Task.yield()
    }

    let fired = FiredFlag()
    withObservationTracking {
      _ = sut.isPaused
    } onChange: {
      fired.fire()
    }

    sut.pauseSimulation(reason: "test observation")

    #expect(fired.value == true, "pauseSimulation must invalidate isPaused observers")
    #expect(sut.isPaused == true)

    // Clean shutdown — resume so runTask completes rather than getting torn
    // down by test-suite teardown mid-park.
    sut.resumeSimulation()
    await runTask.value
  }

  @Test func runClearsSuspendControllerOnExit() async throws {
    let (sut, _) = try makeLifecycleSUT()
    sut.speed = .instant

    let mock = MockLLMService(responses: [#"{"statement": "hi"}"#])
    let scenario = makeTestScenario(
      agentNames: ["Alice"],
      rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])]
    )

    #expect(sut.suspendController == nil)
    await sut.run(scenario: scenario, llm: mock)
    // Defer block in run() clears the controller regardless of exit path.
    #expect(sut.suspendController == nil)
  }
}
