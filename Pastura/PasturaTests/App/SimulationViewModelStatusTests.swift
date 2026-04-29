import Foundation
import Testing

@testable import Pastura

// MARK: - Test Helpers

@MainActor
private func makeStatusSUT() throws -> (sut: SimulationViewModel, scenario: Scenario) {
  let db = try DatabaseManager.inMemory()
  let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
  let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)

  let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
  try scenarioRepo.save(
    ScenarioRecord(
      id: "test", name: "Test", yamlDefinition: "",
      isPreset: false, createdAt: Date(), updatedAt: Date()
    ))

  let scenario = makeTestScenario(
    agentNames: ["Alice", "Bob"], rounds: 1,
    phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])]
  )
  let sut = SimulationViewModel(
    contentFilter: ContentFilter(),
    simulationRepository: simRepo,
    turnRepository: turnRepo
  )
  return (sut, scenario)
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
}
