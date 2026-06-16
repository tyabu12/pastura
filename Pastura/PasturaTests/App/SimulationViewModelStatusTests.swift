import Foundation
import Testing

@testable import Pastura

// MARK: - Test Helpers

@MainActor
private func makeStatusSUT() throws -> (sut: SimulationViewModel, scenario: Scenario) {
  let db = try DatabaseManager.inMemory()
  let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
  let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)

  let scenario = makeTestScenario(
    agentNames: ["Alice", "Bob"], rounds: 1,
    phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])]
  )

  // ScenarioRecord seed satisfies FK constraints when `run()` triggers
  // turn persistence. Keyed on `scenario.id` so the lookup actually
  // resolves rather than silent-no-op against a hard-coded "test"
  // string that would not match.
  let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
  try scenarioRepo.save(
    ScenarioRecord(
      id: scenario.id, name: scenario.name, yamlDefinition: "",
      isPreset: false, createdAt: Date(), updatedAt: Date()
    ))

  let sut = SimulationViewModel(
    contentFilter: ContentFilter(),
    simulationRepository: simRepo,
    turnRepository: turnRepo
  )
  return (sut, scenario)
}

/// Bundle for resume/checkpoint tests that need to read the persisted DB row.
@MainActor
private struct ResumeSUT {
  let sut: SimulationViewModel
  let scenario: Scenario
  let simRepo: GRDBSimulationRepository
}

/// Variant exposing the live `simRepo` so resume/checkpoint tests can read the
/// persisted DB row, with a configurable round count.
@MainActor
private func makeResumeSUT(rounds: Int) throws -> ResumeSUT {
  let db = try DatabaseManager.inMemory()
  let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
  let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
  let scenario = makeTestScenario(
    agentNames: ["Alice", "Bob"], rounds: rounds,
    phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])]
  )
  let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
  try scenarioRepo.save(
    ScenarioRecord(
      id: scenario.id, name: scenario.name, yamlDefinition: "",
      isPreset: false, createdAt: Date(), updatedAt: Date()))
  let sut = SimulationViewModel(
    contentFilter: ContentFilter(),
    simulationRepository: simRepo,
    turnRepository: turnRepo
  )
  return ResumeSUT(sut: sut, scenario: scenario, simRepo: simRepo)
}

/// Polls the persisted row (status writes happen on detached/unstructured
/// Tasks) until `predicate` holds or the deadline passes. Returns the last
/// fetched record either way so callers can assert on it.
@MainActor
private func pollSimulation(
  _ repo: GRDBSimulationRepository, _ simId: String,
  timeout: Duration = .seconds(2),
  until predicate: @escaping (SimulationRecord) -> Bool
) async throws -> SimulationRecord? {
  let deadline = ContinuousClock.now.advanced(by: timeout)
  while ContinuousClock.now < deadline {
    if let rec = try repo.fetchById(simId), predicate(rec) { return rec }
    await Task.yield()
  }
  return try repo.fetchById(simId)
}

/// Drives `run()` on a background Task and waits until the SuspendController is
/// attached (run is genuinely in-flight) so pause/teardown land mid-run.
@MainActor
private func startInFlight(
  _ sut: SimulationViewModel, _ scenario: Scenario, _ mock: MockLLMService
) async -> Task<Void, Never> {
  sut.speed = .instant
  let runTask = Task { await sut.run(scenario: scenario, llm: mock) }
  sut.runTask = runTask
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while sut.suspendController == nil, ContinuousClock.now < deadline {
    await Task.yield()
  }
  return runTask
}

/// `GameHeader`'s 7-state status pill (#297 PR 3) — derivation
/// precedence + cancel-clears-pause invariant.
///
/// Pure `deriveStatus(...)` tests cover the precedence; the
/// integration test pins that `cancelSimulation()` actually clears
/// the runner's pause flag (defense-in-depth alongside the new
/// precedence — see comment at `SimulationViewModel.cancelSimulation`).
@Suite("SimulationViewModelStatus", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct SimulationViewModelStatusTests {

  // MARK: - Pure deriveStatus precedence (no SUT needed)

  @Test func defaultIsSimulating() {
    let status = SimulationViewModel.deriveStatus(
      isCancelled: false, errorMessage: nil, isCompleted: false, isPaused: false)
    #expect(status == .simulating)
  }

  @Test func pausedAloneMapsToPaused() {
    let status = SimulationViewModel.deriveStatus(
      isCancelled: false, errorMessage: nil, isCompleted: false, isPaused: true)
    #expect(status == .paused)
  }

  @Test func completedAloneMapsToCompleted() {
    let status = SimulationViewModel.deriveStatus(
      isCancelled: false, errorMessage: nil, isCompleted: true, isPaused: false)
    #expect(status == .completed)
  }

  @Test func cancelledAloneMapsToCancelled() {
    let status = SimulationViewModel.deriveStatus(
      isCancelled: true, errorMessage: nil, isCompleted: false, isPaused: false)
    #expect(status == .cancelled)
  }

  @Test func errorMessageAloneMapsToError() {
    let status = SimulationViewModel.deriveStatus(
      isCancelled: false, errorMessage: "boom", isCompleted: false, isPaused: false)
    #expect(status == .error)
  }

  // MARK: - Pairwise precedence

  @Test func cancelledWinsOverPaused() {
    let status = SimulationViewModel.deriveStatus(
      isCancelled: true, errorMessage: nil, isCompleted: false, isPaused: true)
    #expect(status == .cancelled)
  }

  @Test func cancelledWinsOverCompleted() {
    let status = SimulationViewModel.deriveStatus(
      isCancelled: true, errorMessage: nil, isCompleted: true, isPaused: false)
    #expect(status == .cancelled)
  }

  @Test func cancelledWinsOverError() {
    // Pathological case from critic (axis 3): an error fires during
    // a run, then the user explicitly cancels. The user's cancel
    // intent supersedes the error display.
    let status = SimulationViewModel.deriveStatus(
      isCancelled: true, errorMessage: "boom", isCompleted: false, isPaused: false)
    #expect(status == .cancelled)
  }

  @Test func errorWinsOverCompleted() {
    let status = SimulationViewModel.deriveStatus(
      isCancelled: false, errorMessage: "boom", isCompleted: true, isPaused: false)
    #expect(status == .error)
  }

  @Test func errorWinsOverPaused() {
    let status = SimulationViewModel.deriveStatus(
      isCancelled: false, errorMessage: "boom", isCompleted: false, isPaused: true)
    #expect(status == .error)
  }

  @Test func completedWinsOverPaused() {
    // A completed-then-paused state is unusual (the runner clears
    // isPaused on completion via the same defensive path as cancel),
    // but precedence still has to handle it.
    let status = SimulationViewModel.deriveStatus(
      isCancelled: false, errorMessage: nil, isCompleted: true, isPaused: true)
    #expect(status == .completed)
  }

  @Test func allFlagsSetReturnsCancelled() {
    // Stress: every flag set + errorMessage non-nil → still cancelled.
    let status = SimulationViewModel.deriveStatus(
      isCancelled: true, errorMessage: "boom", isCompleted: true, isPaused: true)
    #expect(status == .cancelled)
  }

  // MARK: - Instance-level status reads through deriveStatus

  @Test func instanceStatusIsSimulatingPreRun() throws {
    let (sut, _) = try makeStatusSUT()
    #expect(sut.status == .simulating)
  }

  // MARK: - Cancel-clears-pause invariant (integration)

  @Test func cancelClearsPausedFlag() async throws {
    // The defensive `runner.isPaused = false` clear in
    // `cancelSimulation` (see its comment for the dual-rationale)
    // protects:
    //  1. The pause-button icon (load-bearing — reads `isPaused`
    //     directly, doesn't go through `status`).
    //  2. Status precedence (defense-in-depth — `deriveStatus`
    //     already prioritises `isCancelled`, but precedence reorders
    //     would otherwise reintroduce the stale-paused-pill regression).
    //
    // This test pins behavior #1: after cancel, `isPaused == false`.
    let (sut, scenario) = try makeStatusSUT()
    sut.speed = .instant

    // Long-running mock — yields to allow the test to observe the
    // run mid-flight without racing it to completion.
    let mock = MockLLMService(responses: [
      #"{"statement": "first"}"#,
      #"{"statement": "second"}"#
    ])

    let runTask = Task { await sut.run(scenario: scenario, llm: mock) }
    sut.runTask = runTask

    // Wait until the run is in-flight (suspendController attached).
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while sut.suspendController == nil, ContinuousClock.now < deadline {
      await Task.yield()
    }
    #expect(sut.suspendController != nil, "run() should have attached SuspendController")

    sut.pauseSimulation(reason: "test pause")
    #expect(sut.isPaused == true)
    // While paused, status reflects the pause.
    #expect(sut.status == .paused)

    sut.cancelSimulation()
    // The defensive clear flips isPaused back to false.
    #expect(sut.isPaused == false, "cancelSimulation must clear runner.isPaused")
    // And status now reports `.cancelled` (not `.paused`).
    #expect(sut.status == .cancelled)

    await runTask.value
  }

  // MARK: - P3 producer: checkpoint + pause persistence (#656)

  @Test func checkpointPersistsRoundBoundaryStateWithPhaseIndexZero() async throws {
    let env = try makeResumeSUT(rounds: 1)
    let sut = env.sut
    let scenario = env.scenario
    let simRepo = env.simRepo
    let mock = MockLLMService(responses: [
      #"{"statement": "a"}"#, #"{"statement": "b"}"#
    ])
    let runTask = await startInFlight(sut, scenario, mock)
    await runTask.value

    guard let simId = sut.simulationId else {
      Issue.record("simulationId should be set after run()")
      return
    }
    // The round checkpoint write is async; poll until it lands.
    let rec = try await pollSimulation(simRepo, simId) { $0.currentRound == 1 }
    #expect(rec?.currentRound == 1)
    // Round-boundary continuation: phase index is not a resume marker here.
    #expect(rec?.currentPhaseIndex == 0)
    // stateJSON is the resumable snapshot carrying the completed round.
    let decoded = (rec?.stateJSON).flatMap { json in
      json.data(using: .utf8).flatMap { try? JSONDecoder().decode(SimulationState.self, from: $0) }
    }
    #expect(decoded?.currentRound == 1)
  }

  @Test func pausePersistsPausedStatusAndResumeRestoresRunning() async throws {
    let env = try makeResumeSUT(rounds: 1)
    let sut = env.sut
    let scenario = env.scenario
    let simRepo = env.simRepo
    let mock = MockLLMService(responses: [
      #"{"statement": "a"}"#, #"{"statement": "b"}"#
    ])
    let runTask = await startInFlight(sut, scenario, mock)
    #expect(sut.suspendController != nil)

    sut.pauseSimulation()
    guard let simId = sut.simulationId else {
      Issue.record("simulationId should be set")
      return
    }
    let paused = try await pollSimulation(simRepo, simId) { $0.simulationStatus == .paused }
    #expect(paused?.simulationStatus == .paused)

    // Resume restores .running so a later normal completion isn't left .paused.
    sut.resumeSimulation()
    let running = try await pollSimulation(simRepo, simId) {
      $0.simulationStatus == .running || $0.simulationStatus == .completed
    }
    #expect(running?.simulationStatus == .running || running?.simulationStatus == .completed)

    await runTask.value
  }

  @Test func teardownWhilePausedKeepsPausedStatus() async throws {
    let env = try makeResumeSUT(rounds: 1)
    let sut = env.sut
    let scenario = env.scenario
    let simRepo = env.simRepo
    let mock = MockLLMService(responses: [
      #"{"statement": "a"}"#, #"{"statement": "b"}"#
    ])
    let runTask = await startInFlight(sut, scenario, mock)

    sut.pauseSimulation()
    guard let simId = sut.simulationId else {
      Issue.record("simulationId should be set")
      return
    }
    _ = try await pollSimulation(simRepo, simId) { $0.simulationStatus == .paused }

    // Simulate the view tearing down (tab switch / navigate-away): cancel the
    // run Task directly WITHOUT cancelSimulation (which is user-cancel). The
    // terminal ladder must leave the resumable .paused row intact.
    runTask.cancel()
    await runTask.value

    let rec = try simRepo.fetchById(simId)
    #expect(rec?.simulationStatus == .paused)
  }

  @Test func userCancelWhilePausedPersistsCancelled() async throws {
    let env = try makeResumeSUT(rounds: 1)
    let sut = env.sut
    let scenario = env.scenario
    let simRepo = env.simRepo
    let mock = MockLLMService(responses: [
      #"{"statement": "a"}"#, #"{"statement": "b"}"#
    ])
    let runTask = await startInFlight(sut, scenario, mock)

    sut.pauseSimulation()
    guard let simId = sut.simulationId else {
      Issue.record("simulationId should be set")
      return
    }
    _ = try await pollSimulation(simRepo, simId) { $0.simulationStatus == .paused }

    // Explicit user-cancel supersedes the pause → terminal .cancelled.
    sut.cancelSimulation()
    await runTask.value

    let rec = try await pollSimulation(simRepo, simId) { $0.simulationStatus == .cancelled }
    #expect(rec?.simulationStatus == .cancelled)
  }

  @Test func errorSuppressionWhilePausedIsLimitedToCancelled() async throws {
    // Pins the handleEvent suppression granularity: while explicitly paused, a
    // `.cancelled` (teardown artifact) is suppressed but a genuine error still
    // surfaces. (A real error cannot actually arise while parked; this is a
    // unit-level pin of the predicate, not a live path.)
    let env = try makeResumeSUT(rounds: 1)
    let sut = env.sut
    let scenario = env.scenario
    let mock = MockLLMService(responses: [
      #"{"statement": "a"}"#, #"{"statement": "b"}"#
    ])
    let runTask = await startInFlight(sut, scenario, mock)

    sut.pauseSimulation()

    sut.handleEvent(.error(.cancelled), scenario: scenario)
    #expect(sut.errorMessage == nil, ".cancelled while paused is suppressed")

    sut.handleEvent(
      .error(.llmGenerationFailed(description: "boom")), scenario: scenario)
    #expect(sut.errorMessage != nil, "a genuine error while paused still surfaces")

    sut.cancelSimulation()
    await runTask.value
  }
}
