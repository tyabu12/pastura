import Foundation
import GRDB
import Testing

@testable import Pastura

/// Integration coverage for the viewer-prediction interception in
/// `SimulationViewModel` (#915): gating, once-per-run latch, ground-truth
/// scoring, and persistence. The pure decision logic is covered separately in
/// `ViewerPredictionLogicTests`; these tests pin the VM wiring around it.
///
/// The prediction is presented at the first `.phaseStarted(.vote)` (before any
/// vote is shown, so the outcome isn't spoiled) and scored at the subsequent
/// `.voteResults`, so each test drives those two events in order.
///
/// Serialized + `@MainActor`: the tests toggle the process-global
/// `viewerPredictionEnabled` default and exercise MainActor VM state. Each
/// test removes the key so the suite leaves no residue.
@Suite(.serialized, .timeLimit(.minutes(1))) @MainActor
struct SimulationViewModelPredictionTests {
  private static let flagKey = "viewerPredictionEnabled"

  private struct Env {
    let sut: SimulationViewModel
    let repo: GRDBPredictionRepository
    let scenario: Scenario
  }

  private func makeEnv(
    predictionRepo: Bool = true,
    phases: [Phase]
  ) throws -> Env {
    let db = try DatabaseManager.inMemory()
    let writer = db.dbWriter
    let scenarioRepo = GRDBScenarioRepository(dbWriter: writer)
    let simRepo = GRDBSimulationRepository(dbWriter: writer)
    try scenarioRepo.save(
      ScenarioRecord(
        id: "s1", name: "WW", yamlDefinition: "y",
        isPreset: false, createdAt: Date(), updatedAt: Date()))
    try simRepo.save(
      SimulationRecord(
        id: "sim1", scenarioId: "s1", status: "running",
        currentRound: 1, currentPhaseIndex: 0, stateJSON: "{}", configJSON: nil,
        createdAt: Date(), updatedAt: Date()))
    let repo = GRDBPredictionRepository(dbWriter: writer)
    let sut = SimulationViewModel(
      simulationRepository: simRepo,
      turnRepository: GRDBTurnRepository(dbWriter: writer),
      codePhaseEventRepository: GRDBCodePhaseEventRepository(dbWriter: writer),
      predictionRepository: predictionRepo ? repo : nil)
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob", "Carol", "Dave", "Eve"], rounds: 1, phases: phases)
    sut.beginPersistenceForTest(simulationId: "sim1")
    return Env(sut: sut, repo: repo, scenario: scenario)
  }

  /// Feeds word-wolf assignments so the wolf ground-truth resolves to "Eve".
  private func feedWolfAssignments(_ sut: SimulationViewModel, scenario: Scenario) {
    for agent in ["Alice", "Bob", "Carol", "Dave"] {
      sut.handleEvent(.assignment(agent: agent, value: "apple"), scenario: scenario)
    }
    sut.handleEvent(.assignment(agent: "Eve", value: "orange"), scenario: scenario)
  }

  /// Resolves the sheet once it appears — run concurrently with the awaited
  /// vote-phase-start interception.
  private func autoResolve(
    _ sut: SimulationViewModel, with resolution: ViewerPredictionSheet.Resolution
  ) async {
    while sut.predictionPrompt == nil { await Task.yield() }
    sut.resolvePrediction(resolution)
  }

  private let votePhaseStart = SimulationEvent.phaseStarted(
    phaseType: .vote, phasePath: [])

  /// Drives the vote-phase-start prompt (auto-resolving with `resolution` if the
  /// sheet is expected to appear), then delivers the tally to score it.
  private func runPrediction(
    _ env: Env,
    resolve resolution: ViewerPredictionSheet.Resolution?,
    tallies: [String: Int]
  ) async {
    if let resolution {
      async let resolver: Void = autoResolve(env.sut, with: resolution)
      await env.sut.handleViewerPredictionEvent(
        event: votePhaseStart, scenario: env.scenario)
      await resolver
    } else {
      await env.sut.handleViewerPredictionEvent(
        event: votePhaseStart, scenario: env.scenario)
    }
    await env.sut.handleViewerPredictionEvent(
      event: .voteResults(votes: [:], tallies: tallies), scenario: env.scenario)
  }

  private var wolfPhases: [Phase] {
    [Phase(type: .assign, target: .randomOne), Phase(type: .vote)]
  }
  private var votePhases: [Phase] { [Phase(type: .vote)] }

  @Test func wolfCorrectGuessPersistsHit() async throws {
    FeatureFlags.setViewerPredictionEnabled(true)
    defer { UserDefaults.standard.removeObject(forKey: Self.flagKey) }
    let env = try makeEnv(phases: wolfPhases)
    feedWolfAssignments(env.sut, scenario: env.scenario)

    await runPrediction(env, resolve: .predicted("Eve"), tallies: [:])

    let record = try env.repo.fetchBySimulationId("sim1")
    #expect(record?.isHit == true)
    #expect(record?.predictedAgent == "Eve")
    #expect(record?.actualAgent == "Eve")
    #expect(record?.questionKind == "wolf")
    // The end-of-run reward surface (#915) reflects the same result + streak.
    #expect(env.sut.predictionOutcome?.isHit == true)
    #expect(env.sut.predictionOutcome?.streak == 1)
  }

  @Test func wolfWrongGuessPersistsMiss() async throws {
    FeatureFlags.setViewerPredictionEnabled(true)
    defer { UserDefaults.standard.removeObject(forKey: Self.flagKey) }
    let env = try makeEnv(phases: wolfPhases)
    feedWolfAssignments(env.sut, scenario: env.scenario)

    await runPrediction(env, resolve: .predicted("Alice"), tallies: [:])

    let record = try env.repo.fetchBySimulationId("sim1")
    #expect(record?.isHit == false)
    #expect(record?.predictedAgent == "Alice")
    #expect(record?.actualAgent == "Eve")
    #expect(env.sut.predictionOutcome?.isHit == false)
  }

  @Test func topVoteScoresAgainstTallyLeader() async throws {
    FeatureFlags.setViewerPredictionEnabled(true)
    defer { UserDefaults.standard.removeObject(forKey: Self.flagKey) }
    let env = try makeEnv(phases: votePhases)

    await runPrediction(env, resolve: .predicted("Bob"), tallies: ["Bob": 3, "Alice": 1])

    let record = try env.repo.fetchBySimulationId("sim1")
    #expect(record?.isHit == true)
    #expect(record?.questionKind == "topVote")
    #expect(record?.actualAgent == "Bob")
  }

  @Test func skipWritesNoRecord() async throws {
    FeatureFlags.setViewerPredictionEnabled(true)
    defer { UserDefaults.standard.removeObject(forKey: Self.flagKey) }
    let env = try makeEnv(phases: wolfPhases)
    feedWolfAssignments(env.sut, scenario: env.scenario)

    await runPrediction(env, resolve: .skipped, tallies: [:])

    #expect(try env.repo.fetchBySimulationId("sim1") == nil)
    #expect(env.sut.predictionOutcome == nil)
  }

  @Test func latchPreventsSecondAsk() async throws {
    FeatureFlags.setViewerPredictionEnabled(true)
    defer { UserDefaults.standard.removeObject(forKey: Self.flagKey) }
    let env = try makeEnv(phases: wolfPhases)
    feedWolfAssignments(env.sut, scenario: env.scenario)

    await runPrediction(env, resolve: .predicted("Eve"), tallies: [:])

    // A second vote phase in the same run must not re-arm the sheet.
    await env.sut.handleViewerPredictionEvent(
      event: votePhaseStart, scenario: env.scenario)
    #expect(env.sut.predictionPrompt == nil)
    // Still exactly the first (wolf) record — the second vote wrote nothing.
    #expect(try env.repo.fetchBySimulationId("sim1")?.questionKind == "wolf")
  }

  @Test func disabledFlagSkipsInterception() async throws {
    FeatureFlags.setViewerPredictionEnabled(false)
    defer { UserDefaults.standard.removeObject(forKey: Self.flagKey) }
    let env = try makeEnv(phases: wolfPhases)
    feedWolfAssignments(env.sut, scenario: env.scenario)

    await runPrediction(env, resolve: nil, tallies: [:])

    #expect(env.sut.predictionPrompt == nil)
    #expect(try env.repo.fetchBySimulationId("sim1") == nil)
  }

  @Test func nilRepositorySkipsInterception() async throws {
    FeatureFlags.setViewerPredictionEnabled(true)
    defer { UserDefaults.standard.removeObject(forKey: Self.flagKey) }
    let env = try makeEnv(predictionRepo: false, phases: wolfPhases)
    feedWolfAssignments(env.sut, scenario: env.scenario)

    await env.sut.handleViewerPredictionEvent(
      event: votePhaseStart, scenario: env.scenario)

    #expect(env.sut.predictionPrompt == nil)
  }

  @Test func notVisibleSkipsInterception() async throws {
    FeatureFlags.setViewerPredictionEnabled(true)
    defer { UserDefaults.standard.removeObject(forKey: Self.flagKey) }
    let env = try makeEnv(phases: wolfPhases)
    feedWolfAssignments(env.sut, scenario: env.scenario)
    env.sut.setViewVisible(false)

    await runPrediction(env, resolve: nil, tallies: [:])

    #expect(env.sut.predictionPrompt == nil)
    #expect(try env.repo.fetchBySimulationId("sim1") == nil)
  }

  @Test func firstVoteWhileNotVisibleConsumesTheOpportunity() async throws {
    // The first vote phase latches even when not presentable (parked), so a
    // later visible vote in the same run is NOT asked — strict "first vote"
    // contract. If the latch were set AFTER the visibility check, the second
    // vote-start below would present the sheet and this test would fail.
    FeatureFlags.setViewerPredictionEnabled(true)
    defer { UserDefaults.standard.removeObject(forKey: Self.flagKey) }
    let env = try makeEnv(phases: wolfPhases)
    feedWolfAssignments(env.sut, scenario: env.scenario)

    env.sut.setViewVisible(false)
    await env.sut.handleViewerPredictionEvent(
      event: votePhaseStart, scenario: env.scenario)

    env.sut.setViewVisible(true)
    await env.sut.handleViewerPredictionEvent(
      event: votePhaseStart, scenario: env.scenario)

    #expect(env.sut.predictionPrompt == nil)
    #expect(try env.repo.fetchBySimulationId("sim1") == nil)
  }
}
