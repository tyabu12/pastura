import Foundation
import Testing

@testable import Pastura

// Tests for `SimulationSession` (Phase B PR1, ADR-017): the app-level run
// owner. Covers the start-time single-run guard, `adoptIfMatching` identity
// matching, and that `end()` cancels an in-flight run and lets it settle to a
// resumable `.paused` row (lossless cancel-on-disappear, reproduced in PR1).
//
// Serialized + MainActor: the cancellation test drives a real SimulationRunner
// (Task + AsyncStream), which testing.md requires be serialized; the session
// and view model are MainActor types.
@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct SimulationSessionTests {

  /// Builds an in-memory-backed view model + the saved scenario record the run
  /// will create rows against. Mirrors `SimulationViewModelLifecycleTests`.
  func makeViewModel(
    registry: SimulationActivityRegistry = SimulationActivityRegistry()
  ) throws -> (viewModel: SimulationViewModel, simRepo: any SimulationRepository) {
    let db = try DatabaseManager.inMemory()
    let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
    let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
    let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    try scenarioRepo.save(
      ScenarioRecord(
        id: "test", name: "Test", yamlDefinition: "",
        isPreset: false, createdAt: Date(), updatedAt: Date()
      ))
    let viewModel = SimulationViewModel(
      simulationRepository: simRepo,
      turnRepository: turnRepo,
      simulationActivityRegistry: registry
    )
    return (viewModel, simRepo)
  }

  // MARK: - Start-time single-run guard

  @Test func startGuardedStartsWhenIdleThenRefusesWhileLive() throws {
    let session = SimulationSession()
    let (viewModel, _) = try makeViewModel()
    let scenario = makeTestScenario(agentNames: ["Alice"], rounds: 1)

    #expect(session.isLive == false, "fresh session owns no run")

    // A no-op body keeps the slot occupied without needing an LLM — `isLive`
    // is occupancy-based, so it stays true until `end()` regardless of body.
    let first = session.startGuarded(
      source: .scenario(scenarioId: "test"),
      scenario: scenario,
      tab: .home,
      makeViewModel: { viewModel },
      body: { _ in })

    #expect(first == .started)
    #expect(session.isLive == true)

    let second = session.startGuarded(
      source: .scenario(scenarioId: "other"),
      scenario: scenario,
      tab: .home,
      makeViewModel: {
        Issue.record("makeViewModel must not run on refusal")
        return viewModel
      },
      body: { _ in })

    #expect(second == .refusedLiveRunExists, "a second start is refused while a run is owned")
    #expect(session.isLive == true)

    session.end()
    #expect(session.isLive == false, "end() frees the slot")

    let third = session.startGuarded(
      source: .scenario(scenarioId: "test"),
      scenario: scenario,
      tab: .home,
      makeViewModel: { viewModel },
      body: { _ in })
    #expect(third == .started, "a new run may start once the slot is freed")
    session.end()
  }

  // MARK: - adoptIfMatching identity

  @Test func adoptReturnsNilWhenIdle() {
    let session = SimulationSession()
    #expect(session.adoptIfMatching(source: .scenario(scenarioId: "test")) == nil)
  }

  @Test func adoptReturnsViewModelOnlyForMatchingSource() throws {
    let session = SimulationSession()
    let (viewModel, _) = try makeViewModel()
    let scenario = makeTestScenario(agentNames: ["Alice"], rounds: 1)

    _ = session.startGuarded(
      source: .scenario(scenarioId: "test"),
      scenario: scenario,
      tab: .home,
      makeViewModel: { viewModel },
      body: { _ in })

    #expect(
      session.adoptIfMatching(source: .scenario(scenarioId: "test")) === viewModel,
      "matching source re-projects the owned view model")
    #expect(
      session.adoptIfMatching(source: .scenario(scenarioId: "other")) == nil,
      "a different scenario id does not match")
    #expect(
      session.adoptIfMatching(source: .resume(runId: "test")) == nil,
      "a resume of the same id is a different run identity")

    session.end()
    #expect(
      session.adoptIfMatching(source: .scenario(scenarioId: "test")) == nil,
      "after end() nothing is adoptable")
  }

  // MARK: - end() cancels an in-flight run → lossless .paused

  @Test func endCancelsInFlightRunAndPersistsPaused() async throws {
    let registry = SimulationActivityRegistry()
    let (viewModel, simRepo) = try makeViewModel(registry: registry)

    let mock = MockLLMService(responses: [
      #"{"statement": "first"}"#,
      #"{"statement": "second"}"#
    ])
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])]
    )

    let session = SimulationSession()
    let decision = session.startGuarded(
      source: .scenario(scenarioId: "test"),
      scenario: scenario,
      tab: .home,
      makeViewModel: { viewModel },
      body: { model in await model.run(scenario: scenario, llm: mock) })
    #expect(decision == .started)
    #expect(
      registry.isActive == true || viewModel.suspendController == nil,
      "registry brackets the run once run() reaches enter()")

    // Wait for run() to attach the SuspendController (proxy for "in-flight").
    while viewModel.suspendController == nil {
      await Task.yield()
    }

    // Park the run at the next generate boundary so the teardown lands
    // mid-flight (isCompleted == false), exercising the lossless .paused
    // safety net rather than a normal completion.
    viewModel.handleWillResignActive()
    #expect(viewModel.suspendController?.isSuspendRequested() == true)
    try await Task.sleep(for: .milliseconds(50))

    // The session ends the run (PR1: reproduces cancel-on-disappear).
    session.end()
    #expect(session.isLive == false)

    // Wait for the cancelled run to fully unwind through finalizeRun. The VM
    // keeps its runTask reference (end() does not nil it), so it is awaitable.
    await viewModel.runTask?.value

    #expect(viewModel.isRunning == false, "the run task is cancelled and torn down")
    let sims = try simRepo.fetchByScenarioId("test")
    #expect(sims.count == 1)
    #expect(
      sims.first?.simulationStatus == .paused,
      "a mid-flight end() leaves a resumable .paused row")
    #expect(registry.activeCount == 0, "run()'s registry enter/leave stays matched through end()")
  }
}
