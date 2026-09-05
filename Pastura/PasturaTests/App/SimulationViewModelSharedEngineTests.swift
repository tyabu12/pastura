import Foundation
import Synchronization
import Testing

@testable import Pastura

/// ADR-023 §6 S5-4 — the flag-gated engine switch, driven through the real
/// `SimulationViewModel.run` path with the bundled `target_score_race` preset
/// and a scripted `MockLLMService`.
///
/// The Kotlin runner is injected through the same factory `SimulationView`
/// wires, so what is under test is the ViewModel's selection and plumbing, not
/// a test-only shortcut: the per-run `SuspendController` reaching the Kotlin
/// relay is the critic finding this suite exists to pin.
@MainActor
@Suite("SimulationViewModel × shared engine (S5-4)", .timeLimit(.minutes(1)), .serialized)
struct SimulationViewModelSharedEngineTests {

  /// Counts how often the ViewModel asked for a Kotlin runner — the observable
  /// that distinguishes "flag honoured" from "Swift runner ran the same script".
  nonisolated private final class FactoryProbe: Sendable {
    private let count = Mutex(0)
    var invocations: Int { count.withLock { $0 } }
    func note() { count.withLock { $0 += 1 } }
  }

  private struct Env {
    let sut: SimulationViewModel
    let turnRepo: GRDBTurnRepository
    let scenario: Scenario
    let yaml: String
    let mock: MockLLMService
    let probe: FactoryProbe
  }

  private func makeEnv(flagOn: Bool) throws -> Env {
    let db = try DatabaseManager.inMemory()
    let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
    let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
    let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)

    let yaml = try SharedEngineFixtures.presetYaml()
    // The Swift loader parses the same text the Kotlin loader will: both
    // engines see one scenario, and the scripted answers derived from the
    // Kotlin parse are valid for either.
    let scenario = try ScenarioLoader().load(yaml: yaml)
    try scenarioRepo.save(
      ScenarioRecord(
        id: scenario.id, name: scenario.name, yamlDefinition: yaml,
        isPreset: true, createdAt: Date(), updatedAt: Date()))
    let kotlinScenario = try SharedEngineFixtures.loadedPreset()
    let mock = MockLLMService(
      responses: SharedEngineFixtures.scriptedResponses(for: kotlinScenario))

    let probe = FactoryProbe()
    let sut = SimulationViewModel(
      makeSharedRunner: { controller in
        probe.note()
        return SharedEngineRunner(suspendController: controller)
      },
      isSharedEngineEnabled: { flagOn },
      simulationRepository: simRepo,
      turnRepository: turnRepo
    )
    sut.speed = .instant
    return Env(
      sut: sut, turnRepo: turnRepo, scenario: scenario, yaml: yaml, mock: mock, probe: probe)
  }

  /// Starts a run whose first inference parks on the armed `SuspendController`
  /// and waits until the mock has actually taken that first (suspended) call.
  private func startParkedRun(_ env: Env) async throws -> Task<Void, Never> {
    // Arm the controller's suspend at attach time, so the very first
    // inference throws `.suspended` with no scheduling race — the Kotlin
    // `LLMCaller` then parks on its relay and only a `SuspendController.resume`
    // (→ `RunHandle.notifyLLMResumed`) can release it.
    env.mock.suspendOnControllerAttach()
    let runTask = Task {
      await env.sut.run(scenario: env.scenario, llm: env.mock, yamlDefinition: env.yaml)
    }
    env.sut.runTask = runTask
    // "Parked" is observable as: model up, run in flight, an agent marked
    // thinking (`.inferenceStarted` precedes the backend call) and the armed
    // suspend still standing. The mock's call counters do not move on a
    // suspended throw, so they cannot serve here (same shape as
    // `parkRunMidFlight` in the status-tests suite).
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    var parked = false
    while ContinuousClock.now < deadline, !parked {
      if env.sut.isRunning, !env.sut.isLoadingModel, !env.sut.thinkingAgents.isEmpty,
        env.sut.suspendController?.isSuspendRequested() == true {
        parked = true
      } else {
        try await Task.sleep(for: .milliseconds(10))
      }
    }
    #expect(parked, "the run reached its first inference and parked on the armed suspend")
    #expect(env.sut.isCompleted == false, "parked, not finished")
    return runTask
  }

  @Test("flag on: a fresh run goes to the Kotlin engine and persists its turns")
  func flagOnRunsOnTheKotlinEngine() async throws {
    let env = try makeEnv(flagOn: true)

    await env.sut.run(scenario: env.scenario, llm: env.mock, yamlDefinition: env.yaml)

    #expect(env.probe.invocations == 1, "exactly one Kotlin runner per run")
    #expect(env.sut.errorMessage == nil)
    #expect(env.sut.isCompleted)
    // The persistence consumer drains before run() returns, so the turn rows
    // written from *translated* Kotlin events are already queryable.
    let simId = try #require(env.sut.simulationId)
    let turns = try env.turnRepo.fetchBySimulationId(simId)
    #expect(!turns.isEmpty, "agentOutput events from the Kotlin engine reach TurnRepository")
  }

  @Test("flag on: a background park mid-run reaches the Kotlin relay and the run resumes")
  func flagOnSurvivesABackgroundSuspendCycle() async throws {
    let env = try makeEnv(flagOn: true)
    let runTask = try await startParkedRun(env)
    #expect(env.sut.suspendController?.isSuspendRequested() == true)

    // The foreground handler is the production release path
    // (`routeUnpark` → `SuspendController.resume`).
    await env.sut.handleScenePhaseForeground()
    await runTask.value

    #expect(env.probe.invocations == 1)
    #expect(env.sut.errorMessage == nil)
    #expect(env.sut.isCompleted, "the relay released the parked Kotlin run")
  }

  @Test("flag on: a user pause is forwarded to the Kotlin run and does not deadlock")
  func flagOnPauseThenResumeCompletes() async throws {
    let env = try makeEnv(flagOn: true)
    let runTask = try await startParkedRun(env)

    // Pause while parked, then resume: `setRunnerPaused` must reach the Kotlin
    // `RunHandle` both ways, and the resume must also release the park.
    env.sut.pauseSimulation()
    #expect(env.sut.isPaused)
    env.sut.resumeSimulation()
    #expect(env.sut.isPaused == false)
    await env.sut.handleScenePhaseForeground()
    await runTask.value

    #expect(env.sut.isCompleted, "a paused-then-resumed Kotlin run still completes")
    #expect(env.sut.errorMessage == nil)
  }

  @Test("flag off: the Swift runner serves the run and no Kotlin runner is built")
  func flagOffStaysOnTheSwiftRunner() async throws {
    let env = try makeEnv(flagOn: false)

    await env.sut.run(scenario: env.scenario, llm: env.mock, yamlDefinition: env.yaml)

    #expect(env.probe.invocations == 0)
    #expect(env.sut.isCompleted)
  }

  @Test("flag on but no YAML: the Swift runner serves the run")
  func flagOnWithoutYamlStaysOnTheSwiftRunner() async throws {
    let env = try makeEnv(flagOn: true)

    await env.sut.run(scenario: env.scenario, llm: env.mock)

    #expect(
      env.probe.invocations == 0,
      "the Kotlin loader needs the YAML; without it the switch is inert")
    #expect(env.sut.isCompleted)
  }
}
