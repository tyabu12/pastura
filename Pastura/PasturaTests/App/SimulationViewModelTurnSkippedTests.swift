import Foundation
import Testing

@testable import Pastura

/// `.turnSkipped` event surfacing (ADR-021 D5/D6). Each skipped LLM turn
/// increments the App-side `degradedTurnCount` aggregate and appends a
/// per-skip live-log narration line. Mirrors the `languageMismatchCount`
/// counting shape (reset at `run()` entry, incremented in `handleEvent`),
/// but — unlike language drift — every event lands its own log line
/// because a skip is a per-agent/per-location fact, not a run-level
/// condition. Persistence of the aggregate is exercised separately
/// (Data-layer tests); this suite covers the live counting + narration.
@Suite("SimulationViewModelTurnSkipped", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct SimulationViewModelTurnSkippedTests {

  // MARK: - Initial state

  @Test func initialStateHasZeroDegradedCount() throws {
    let (sut, _) = try makeSUT()
    #expect(sut.degradedTurnCount == 0)
  }

  // MARK: - handleEvent dispatch

  @Test func turnSkippedIncrementsCountAndAppendsLogLine() throws {
    let (sut, scenario) = try makeSUT()
    sut.handleEvent(
      .turnSkipped(agent: "Alice", phaseType: .vote, cause: "retries exhausted"),
      scenario: scenario)
    #expect(sut.degradedTurnCount == 1)
    guard case .turnSkipped(let agent, let phaseType) = sut.logEntries.last?.kind else {
      Issue.record(
        "expected a .turnSkipped log entry, got \(String(describing: sut.logEntries.last?.kind))")
      return
    }
    #expect(agent == "Alice")
    #expect(phaseType == .vote)
  }

  @Test func multipleTurnSkippedAccumulateOneLinePerEvent() throws {
    let (sut, scenario) = try makeSUT()
    sut.handleEvent(
      .turnSkipped(agent: "Alice", phaseType: .vote, cause: "retries exhausted"),
      scenario: scenario)
    sut.handleEvent(
      .turnSkipped(agent: "Bob", phaseType: .speakAll, cause: "generation failed"),
      scenario: scenario)
    #expect(sut.degradedTurnCount == 2)
    // Each skip is a distinct fact — one narration line per event (unlike
    // the one-shot language-drift toast).
    let skippedLines = sut.logEntries.filter {
      if case .turnSkipped = $0.kind { return true }
      return false
    }
    #expect(skippedLines.count == 2)
  }

  // MARK: - Reset on run() entry

  @Test func runResetsDegradedTurnCount() async throws {
    let (sut, scenario) = try makeSUT()

    // Pre-populate via direct dispatch so we can observe the reset.
    sut.handleEvent(
      .turnSkipped(agent: "Alice", phaseType: .vote, cause: "retries exhausted"),
      scenario: scenario)
    sut.handleEvent(
      .turnSkipped(agent: "Bob", phaseType: .vote, cause: "retries exhausted"),
      scenario: scenario)
    #expect(sut.degradedTurnCount == 2)

    sut.speed = .instant

    let mock = MockLLMService(responses: [
      #"{"statement": "first"}"#,
      #"{"statement": "second"}"#,
      #"{"statement": "third"}"#,
      #"{"statement": "fourth"}"#
    ])

    let runTask = Task { await sut.run(scenario: scenario, llm: mock) }
    sut.runTask = runTask

    // Wait for the reset (run() applies it synchronously near entry,
    // before awaiting the event stream).
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while sut.degradedTurnCount > 0, ContinuousClock.now < deadline {
      await Task.yield()
    }
    #expect(sut.degradedTurnCount == 0)

    sut.cancelSimulation()
    await runTask.value
  }

  // MARK: - Persistence at completion (ADR-021 D6)

  @Test func completedRunWithSkipPersistsDegradedTurnCount() async throws {
    let db = try DatabaseManager.inMemory()
    let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
    let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
    let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    try scenarioRepo.save(
      ScenarioRecord(
        id: "test", name: "Test", yamlDefinition: "",
        isPreset: false, createdAt: Date(), updatedAt: Date()))

    let sut = SimulationViewModel(
      simulationRepository: simRepo, turnRepository: turnRepo)
    sut.speed = .instant

    // Alice's turn fails transiently (one skip, < breaker threshold); Bob
    // speaks, so the run still reaches `.completed`.
    let mock = MockLLMService(responses: [#"{"statement": "hello from Bob"}"#])
    mock.throwErrorOnNextGenerate(.generationFailed(description: "transient"), count: 1)

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"], rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])])

    await sut.run(scenario: scenario, llm: mock)

    #expect(sut.degradedTurnCount == 1)
    let sims = try simRepo.fetchByScenarioId("test")
    #expect(sims.first?.simulationStatus == .completed)
    #expect(sims.first?.degradedTurnCount == 1)
  }
}
