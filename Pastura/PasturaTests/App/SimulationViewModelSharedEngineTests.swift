import Foundation
import Synchronization
import Testing

@testable import Pastura

/// ADR-023 §6 S5-5 — the Kotlin engine as the sole fresh-run path, driven
/// through the real `SimulationViewModel.run` path with the bundled
/// `target_score_race` preset and a scripted `MockLLMService`.
///
/// The Kotlin runner is injected through the same factory `SimulationView`
/// wires, so what is under test is the ViewModel's selection and plumbing, not
/// a test-only shortcut: the per-run `SuspendController` reaching the Kotlin
/// relay is the critic finding this suite exists to pin.
@MainActor
@Suite("SimulationViewModel × shared engine (S5-5)", .timeLimit(.minutes(1)), .serialized)
struct SimulationViewModelSharedEngineTests {

  /// Counts how often the ViewModel asked for a Kotlin runner — the observable
  /// that distinguishes "Kotlin ran it" from "the Swift runner ran the same
  /// script" (both complete the preset, so completion alone proves nothing).
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

  private func makeEnv() throws -> Env {
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
    // 30 s, not 5: CI runs with coverage on a shared runner and has turned
    // ~120 ms into ~3 s (`testing.md` § "Wall-clock test bounds"); the suite
    // `.timeLimit` is the real backstop.
    let deadline = ContinuousClock.now.advanced(by: .seconds(30))
    var parked = false
    while ContinuousClock.now < deadline, !parked {
      if env.sut.isRunning, !env.sut.isLoadingModel, !env.sut.thinkingAgents.isEmpty,
        env.sut.suspendController?.isSuspendRequested() == true {
        parked = true
      } else {
        try await Task.sleep(for: .milliseconds(10))
      }
    }
    if !parked {
      // Do not hand back a task the caller would block on forever — before
      // the expectations, so this holds even if one later becomes #require.
      runTask.cancel()
    }
    #expect(parked, "the run reached its first inference and parked on the armed suspend")
    #expect(env.sut.isCompleted == false, "parked, not finished")
    return runTask
  }

  @Test("a fresh run goes to the Kotlin engine and persists its turns")
  func aFreshRunGoesToTheKotlinEngine() async throws {
    let env = try makeEnv()

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

  @Test("a background park mid-run reaches the Kotlin relay and the run resumes")
  func survivesABackgroundSuspendCycle() async throws {
    let env = try makeEnv()
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

  @Test("a user pause is forwarded to the Kotlin run and does not deadlock")
  func pauseThenResumeCompletes() async throws {
    let env = try makeEnv()
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

  @Test("a pause taken before the Kotlin runner exists is replayed to it")
  func pauseBeforeStreamCreationIsReplayed() async throws {
    let env = try makeEnv()
    // Arm the intro gate: run() parks at `awaitIntroReveal()` after the model
    // load and BEFORE `makeEventStream` — the window in which a pause reaches
    // only the Swift flag because no Kotlin runner exists yet.
    env.sut.beginIntro(revealBackstop: 60)
    let runTask = Task {
      await env.sut.run(scenario: env.scenario, llm: env.mock, yamlDefinition: env.yaml)
    }
    env.sut.runTask = runTask
    let deadline = ContinuousClock.now.advanced(by: .seconds(30))
    while ContinuousClock.now < deadline, !(env.sut.isRunning && !env.sut.isLoadingModel) {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(env.sut.isRunning && !env.sut.isLoadingModel, "parked at the intro gate")

    env.sut.pauseSimulation()
    #expect(env.sut.isPaused)
    #expect(env.probe.invocations == 0, "no Kotlin runner exists yet — that is the point")

    // Release the gate: `makeEventStream` builds the Kotlin runner and must
    // replay the standing pause. `pauseSimulation` also parked the suspend
    // controller; release THAT half directly so the only thing holding the
    // run is the Kotlin pause — with the replay the run halts at its next
    // checkpoint and cannot finish, without it the instant mock completes the
    // whole preset in well under the wait below.
    env.sut.introRevealDidComplete()
    env.sut.suspendController?.resume()
    try await Task.sleep(for: .milliseconds(500))
    #expect(env.probe.invocations == 1)
    #expect(env.sut.isCompleted == false, "the Kotlin run honoured the replayed pause")

    env.sut.resumeSimulation()
    await runTask.value
    #expect(env.sut.isCompleted, "the replayed pause was released by resume")
    #expect(env.sut.errorMessage == nil)
  }

  /// The S5-5 test seam (#1687): `run(scenario:llm:)` with no YAML still runs,
  /// on the Swift runner, because ~66 existing suites call it that way. It is
  /// not a production path — `SimulationView` always passes the record's
  /// `yamlDefinition` — and `makeEventStream` logs plus (outside the test
  /// harness) asserts when it is taken.
  @Test("no YAML: the Swift runner serves the run as the #1687 test seam")
  func withoutYamlFallsBackToTheSwiftSeam() async throws {
    let env = try makeEnv()

    await env.sut.run(scenario: env.scenario, llm: env.mock)

    #expect(
      env.probe.invocations == 0,
      "the Kotlin loader needs the YAML; without it the seam takes the run")
    #expect(env.sut.isCompleted)
  }

  /// The S5-5 default itself: a VM built with **no** `makeSharedRunner` must
  /// still run fresh runs on Kotlin. Asserted through the one behaviour only
  /// the Kotlin path has — it owns the YAML parse, so YAML the Kotlin
  /// `ScenarioLoader` rejects surfaces as `.scenarioValidationFailed`. The
  /// Swift runner ignores the YAML entirely and would happily complete the
  /// already-parsed `Scenario`, so a green here cannot be the Swift path.
  @Test("the default makeSharedRunner runs fresh runs on the Kotlin engine")
  func theDefaultFactoryRunsOnTheKotlinEngine() async throws {
    let db = try DatabaseManager.inMemory()
    let sut = SimulationViewModel(
      simulationRepository: GRDBSimulationRepository(dbWriter: db.dbWriter),
      turnRepository: GRDBTurnRepository(dbWriter: db.dbWriter)
    )
    sut.speed = .instant
    let scenario = try ScenarioLoader().load(yaml: SharedEngineFixtures.presetYaml())
    let mock = MockLLMService(responses: ["{}"])

    await sut.run(
      scenario: scenario, llm: mock,
      yamlDefinition: "name: broken\nthis is not a scenario document")

    #expect(sut.errorMessage != nil, "the Kotlin loader rejected the YAML it owns the parse of")
    #expect(sut.isCompleted == false)
    #expect(mock.generateCallCount == 0, "no engine ran: the parse failed first")
  }
}
