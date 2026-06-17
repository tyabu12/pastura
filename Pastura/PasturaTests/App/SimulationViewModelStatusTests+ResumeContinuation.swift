import Foundation
import Testing

@testable import Pastura

// Sibling-file split of `SimulationViewModelStatusTests` (file_length cap).
// These are an `extension` of the SAME suite — NOT a new `@Suite` — so they
// stay `.serialized` with the rest and don't race the shared SimulationRunner /
// AsyncStream cleanup (see `.claude/rules/testing.md`). Helpers live at file
// scope here. `FailingLLMService` is reused from
// `SimulationViewModelLifecycleTests.swift` (file-scope, module-internal).

/// Bundle for the resume *consumer* tests (P3 PR1b): a VM wired with all four
/// repositories plus the live `turnRepo` / `codeRepo` / `simRepo` so tests can
/// seed a paused run and read back the persisted rows after `resume(...)`.
@MainActor
private struct ContinuationSUT {
  let sut: SimulationViewModel
  let scenario: Scenario
  let simRepo: GRDBSimulationRepository
  let turnRepo: GRDBTurnRepository
  let codeRepo: GRDBCodePhaseEventRepository
}

@MainActor
private func makeContinuationSUT(rounds: Int) throws -> ContinuationSUT {
  let db = try DatabaseManager.inMemory()
  let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
  let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
  let codeRepo = GRDBCodePhaseEventRepository(dbWriter: db.dbWriter)
  let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
  let scenario = makeTestScenario(
    agentNames: ["Alice", "Bob"], rounds: rounds,
    phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])]
  )
  // FK: the simulation row references the scenario row, so it must exist first.
  try scenarioRepo.save(
    ScenarioRecord(
      id: scenario.id, name: scenario.name, yamlDefinition: "",
      isPreset: false, createdAt: Date(), updatedAt: Date()))
  let sut = SimulationViewModel(
    contentFilter: ContentFilter(),
    simulationRepository: simRepo,
    turnRepository: turnRepo,
    codePhaseEventRepository: codeRepo,
    scenarioRepository: scenarioRepo
  )
  return ContinuationSUT(
    sut: sut, scenario: scenario, simRepo: simRepo, turnRepo: turnRepo, codeRepo: codeRepo)
}

/// Seeds a `.paused` simulation row whose checkpoint records `completedRound`
/// (= K). Returns the encoded state for callers that assert on rehydration.
@MainActor
@discardableResult
private func seedPausedRun(
  _ env: ContinuationSUT, simId: String, completedRound: Int,
  scores: [String: Int] = ["Alice": 5, "Bob": 3]
) throws -> SimulationState {
  var state = SimulationState.initial(for: env.scenario)
  state.currentRound = completedRound
  state.scores = scores
  let json =
    (try? JSONEncoder().encode(state)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
  try env.simRepo.save(
    SimulationRecord(
      id: simId, scenarioId: env.scenario.id, status: SimulationStatus.paused.rawValue,
      currentRound: completedRound, currentPhaseIndex: 0, stateJSON: json, configJSON: nil,
      createdAt: Date(), updatedAt: Date()))
  return state
}

@MainActor
private func seedTurn(
  _ env: ContinuationSUT, simId: String, round: Int, seq: Int, agent: String
) throws {
  let json =
    (try? JSONEncoder().encode(TurnOutput(fields: ["statement": "seeded"])))
    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
  try env.turnRepo.save(
    TurnRecord(
      id: UUID().uuidString, simulationId: simId, roundNumber: round,
      phaseType: "speak_all", agentName: agent, rawOutput: "seeded",
      parsedOutputJSON: json, sequenceNumber: seq,
      createdAt: Date(timeIntervalSince1970: TimeInterval(seq))))
}

@MainActor
private func seedCodeEvent(
  _ env: ContinuationSUT, simId: String, round: Int, seq: Int, payload: CodePhaseEventPayload
) throws {
  let json =
    (try? JSONEncoder().encode(payload)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
  try env.codeRepo.save(
    CodePhaseEventRecord(
      id: UUID().uuidString, simulationId: simId, roundNumber: round,
      phaseType: "score_calc", sequenceNumber: seq, payloadJSON: json,
      createdAt: Date(timeIntervalSince1970: TimeInterval(seq))))
}

// Upper bound is generous (30s) because CI runs with code coverage are ~20×
// slower and the teardown→finalizeRun→async status-write chain can lag; the
// poll returns immediately on the happy path, so this only widens the
// failure-wait, not normal runtime (see `.claude/rules` CI-wallclock guidance).
@MainActor
private func pollResumeStatus(
  _ repo: GRDBSimulationRepository, _ simId: String,
  timeout: Duration = .seconds(30),
  until predicate: @escaping (SimulationRecord) -> Bool
) async throws -> SimulationRecord? {
  let deadline = ContinuousClock.now.advanced(by: timeout)
  while ContinuousClock.now < deadline {
    if let rec = try repo.fetchById(simId), predicate(rec) { return rec }
    await Task.yield()
  }
  return try repo.fetchById(simId)
}

/// A fresh run parked mid-flight by ``startSuspendedFreshRun(rounds:)``.
@MainActor
private struct SuspendedFreshRun {
  let env: ContinuationSUT
  let simId: String
  let runTask: Task<Void, Never>
}

/// Starts a FRESH `run(...)` whose first generate is parked (so the run is
/// genuinely mid-flight and its `.running` record persisted), localizing the
/// park-and-wait choreography. The caller then applies the leave action under
/// test (raw `Task.cancel()` vs `cancelSimulation`). `nil` if no record formed.
@MainActor
private func startSuspendedFreshRun(rounds: Int = 3) async throws -> SuspendedFreshRun? {
  let env = try makeContinuationSUT(rounds: rounds)
  let mock = MockLLMService(responses: Array(repeating: #"{"statement":"x"}"#, count: 10))
  env.sut.speed = .instant
  mock.simulateSuspendOnNextGenerate()

  let runTask = Task { await env.sut.run(scenario: env.scenario, llm: mock) }
  env.sut.runTask = runTask

  // Wait until the parked inference has started — by then run() has already
  // awaited createSimulationRecord, so simulationId is populated.
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while env.sut.thinkingAgents.isEmpty, ContinuousClock.now < deadline {
    await Task.yield()
  }
  guard let simId = env.sut.simulationId else {
    runTask.cancel()
    return nil
  }
  return SuspendedFreshRun(env: env, simId: simId, runTask: runTask)
}

extension SimulationViewModelStatusTests {

  // MARK: - Pure terminal-status ladder (deterministic, no run needed)

  @Test func terminalStatusLeavesPausedWhenExplicitlyPaused() {
    // didPersistPaused wins over everything → nil (skip the write, keep .paused).
    #expect(
      SimulationViewModel.terminalStatus(
        didPersistPaused: true, errorMessage: "boom",
        isCancelled: true, isCompleted: false) == nil)
  }

  @Test func terminalStatusFailedBeatsCompletion() {
    #expect(
      SimulationViewModel.terminalStatus(
        didPersistPaused: false, errorMessage: "boom",
        isCancelled: false, isCompleted: true) == .failed)
  }

  @Test func terminalStatusFailedBeatsTeardown() {
    // A real error on a not-yet-completed run still wins over the `.paused`
    // teardown branch — errorMessage is checked above `!isCompleted` (#673).
    #expect(
      SimulationViewModel.terminalStatus(
        didPersistPaused: false, errorMessage: "boom",
        isCancelled: false, isCompleted: false) == .failed)
  }

  @Test func terminalStatusCancelBeatsTeardownAndCompletion() {
    // User-cancel (`isCancelled`) is checked above `!isCompleted`, so a run
    // cancelled mid-flight records `.cancelled`, never the teardown `.paused`.
    #expect(
      SimulationViewModel.terminalStatus(
        didPersistPaused: false, errorMessage: nil,
        isCancelled: true, isCompleted: false) == .cancelled)
  }

  @Test func terminalStatusTornDownMidFlightStaysPaused() {
    // #673 — a run torn down before completion (no pause/cancel/error) stays
    // resumable rather than being marked complete. Symmetric across fresh and
    // resumed runs: `isResumedRun` is no longer a discriminator here. This
    // replaces the prior fresh-vs-resumed asymmetry pin (the fresh case used
    // to write `.completed`, silently losing the run).
    #expect(
      SimulationViewModel.terminalStatus(
        didPersistPaused: false, errorMessage: nil,
        isCancelled: false, isCompleted: false) == .paused)
  }

  @Test func terminalStatusCompletedRunWritesCompleted() {
    // The only path to `.completed`: `.simulationCompleted` set isCompleted, and
    // no higher-precedence terminal flag fired.
    #expect(
      SimulationViewModel.terminalStatus(
        didPersistPaused: false, errorMessage: nil,
        isCancelled: false, isCompleted: true) == .completed)
  }

  // MARK: - Resume continuation (seed → resume → assert persisted rows)

  @Test func resumeRunsNextRoundOnceWithContiguousSequence() async throws {
    let env = try makeContinuationSUT(rounds: 2)
    let simId = "sim-resume-contig"
    try seedPausedRun(env, simId: simId, completedRound: 1)
    // Round 1 fully persisted (Alice seq1, Bob seq2)...
    try seedTurn(env, simId: simId, round: 1, seq: 1, agent: "Alice")
    try seedTurn(env, simId: simId, round: 1, seq: 2, agent: "Bob")
    // ...plus a PARTIAL interrupted round 2 (only Alice spoke before the pause).
    try seedTurn(env, simId: simId, round: 2, seq: 3, agent: "Alice")

    guard let record = try env.simRepo.fetchById(simId) else {
      Issue.record("seed failed")
      return
    }
    let mock = MockLLMService(responses: [#"{"statement":"a2"}"#, #"{"statement":"b2"}"#])
    env.sut.speed = .instant

    let runTask = Task { await env.sut.resume(record: record, scenario: env.scenario, llm: mock) }
    env.sut.runTask = runTask
    await runTask.value

    let turns = try env.turnRepo.fetchBySimulationId(simId)
    // Round 2 must have EXACTLY one full set (Alice, Bob) — the partial Alice
    // (seq 3) was deleted, and the re-run produced a fresh pair. No duplicate.
    let round2 = turns.filter { $0.roundNumber == 2 }
    #expect(round2.count == 2)
    // Sequence numbers contiguous AND distinct: 1, 2, 3, 4. A reseed bug
    // (e.g. reverting to turnSequence = 0) would collide round-2 turns onto
    // 1, 2 — this assertion is the revert-fails guard for the reseed.
    #expect(turns.map(\.sequenceNumber).sorted() == [1, 2, 3, 4])
    // Rehydrated accumulated state from the checkpoint.
    #expect(env.sut.totalRounds == 2)
    #expect(env.sut.isCompleted == true)
  }

  @Test func resumeFromRoundZeroStartsSequenceAtOne() async throws {
    // K = 0: a pause before any round completed (no checkpoint advanced past 0).
    let env = try makeContinuationSUT(rounds: 1)
    let simId = "sim-resume-k0"
    try seedPausedRun(env, simId: simId, completedRound: 0)
    // A partial round-1 turn persisted before the pause.
    try seedTurn(env, simId: simId, round: 1, seq: 1, agent: "Alice")

    guard let record = try env.simRepo.fetchById(simId) else {
      Issue.record("seed failed")
      return
    }
    let mock = MockLLMService(responses: [#"{"statement":"a"}"#, #"{"statement":"b"}"#])
    env.sut.speed = .instant
    let runTask = Task { await env.sut.resume(record: record, scenario: env.scenario, llm: mock) }
    await runTask.value

    let turns = try env.turnRepo.fetchBySimulationId(simId)
    // round > 0 deleted (the partial Alice), round 1 re-run from scratch → seq 1, 2.
    #expect(turns.map(\.sequenceNumber).sorted() == [1, 2])
    #expect(turns.allSatisfy { $0.roundNumber == 1 })
  }

  @Test func resumeReseedsFromCodePhaseMaxWhenHigher() async throws {
    // codeMax > turnMax: the last persisted row in round K is a code-phase event.
    let env = try makeContinuationSUT(rounds: 2)
    let simId = "sim-resume-codemax"
    try seedPausedRun(env, simId: simId, completedRound: 1)
    try seedTurn(env, simId: simId, round: 1, seq: 1, agent: "Alice")
    try seedTurn(env, simId: simId, round: 1, seq: 2, agent: "Bob")
    // A code-phase event closes round 1 at seq 3 (higher than the turn max of 2).
    try seedCodeEvent(
      env, simId: simId, round: 1, seq: 3, payload: .scoreUpdate(scores: ["Alice": 1]))

    guard let record = try env.simRepo.fetchById(simId) else {
      Issue.record("seed failed")
      return
    }
    let mock = MockLLMService(responses: [#"{"statement":"a2"}"#, #"{"statement":"b2"}"#])
    env.sut.speed = .instant
    let runTask = Task { await env.sut.resume(record: record, scenario: env.scenario, llm: mock) }
    await runTask.value

    let round2 =
      try env.turnRepo.fetchBySimulationId(simId)
      .filter { $0.roundNumber == 2 }.map(\.sequenceNumber).sorted()
    // Reseed = max(turnMax 2, codeMax 3) = 3 → round-2 turns get 4, 5. A
    // turn-only reseed (ignoring codeMax) would produce 3, 4 and collide with
    // the surviving code event at seq 3.
    #expect(round2 == [4, 5])
  }

  @Test func resumeWithFailingModelLeavesRowPaused() async throws {
    // Hazard 1: a resume whose model fails to load must stay resumable — the DB
    // row remains .paused (never .failed), so the Home card still offers resume.
    let env = try makeContinuationSUT(rounds: 2)
    let simId = "sim-resume-loadfail"
    try seedPausedRun(env, simId: simId, completedRound: 1)
    try seedTurn(env, simId: simId, round: 1, seq: 1, agent: "Alice")

    guard let record = try env.simRepo.fetchById(simId) else {
      Issue.record("seed failed")
      return
    }
    await env.sut.resume(record: record, scenario: env.scenario, llm: FailingLLMService())

    let rec = try env.simRepo.fetchById(simId)
    #expect(rec?.simulationStatus == .paused)
    // The partial round was still pruned, but no new rows were written.
    let turns = try env.turnRepo.fetchBySimulationId(simId)
    #expect(turns.allSatisfy { $0.roundNumber <= 1 })
  }

  @Test func resumedRunTornDownMidFlightPersistsPaused() async throws {
    // End-to-end of the terminal-ladder branch: a resumed run cancelled at the
    // Task level (tab-switch / navigate-away) WITHOUT cancelSimulation must
    // leave the row .paused, not .failed/.completed. A scheduled suspend parks
    // the first round-2 generate so the cancel lands deterministically mid-flight.
    let env = try makeContinuationSUT(rounds: 3)
    let simId = "sim-resume-teardown"
    try seedPausedRun(env, simId: simId, completedRound: 1)
    try seedTurn(env, simId: simId, round: 1, seq: 1, agent: "Alice")
    try seedTurn(env, simId: simId, round: 1, seq: 2, agent: "Bob")

    guard let record = try env.simRepo.fetchById(simId) else {
      Issue.record("seed failed")
      return
    }
    let mock = MockLLMService(responses: Array(repeating: #"{"statement":"x"}"#, count: 10))
    env.sut.speed = .instant
    // Park the first resumed generate so the run is genuinely in-flight when
    // we tear it down (otherwise .instant would complete before the cancel).
    mock.simulateSuspendOnNextGenerate()

    let runTask = Task { await env.sut.resume(record: record, scenario: env.scenario, llm: mock) }
    env.sut.runTask = runTask

    // Wait until the parked inference has started (run is mid-flight).
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while env.sut.thinkingAgents.isEmpty, ContinuousClock.now < deadline {
      await Task.yield()
    }

    // Tab-switch teardown: cancel the Task directly (NOT cancelSimulation).
    runTask.cancel()
    await runTask.value

    let rec = try await pollResumeStatus(env.simRepo, simId) { $0.simulationStatus == .paused }
    #expect(rec?.simulationStatus == .paused)
  }

  // MARK: - Fresh-run mid-flight teardown (#673 terminal-ladder symmetry)

  @Test func freshRunTornDownMidFlightPersistsPaused() async throws {
    // #673 safety net: a FRESH run cancelled at the Task level (tab-switch /
    // back / swipe-back) WITHOUT cancelSimulation must leave the row .paused, not
    // the silent .completed (data loss) of the prior asymmetry. Reverting
    // `!isCompleted` → `isResumedRun && !isCompleted` would fail this assert.
    guard let run = try await startSuspendedFreshRun() else {
      Issue.record("fresh run did not create a simulation record")
      return
    }

    // Tab-switch / back teardown: cancel the Task directly (NOT cancelSimulation).
    run.runTask.cancel()
    await run.runTask.value

    let rec = try await pollResumeStatus(run.env.simRepo, run.simId) {
      $0.simulationStatus == .paused
    }
    #expect(rec?.simulationStatus == .paused)
  }

  @Test func freshRunUserCancelledPersistsCancelled() async throws {
    // Guard the #673 ladder change against demoting a genuine user-cancel into
    // `.paused`: cancelSimulation sets isCancelled, which the ladder checks ABOVE
    // the `!isCompleted` teardown branch → `.cancelled`.
    guard let run = try await startSuspendedFreshRun() else {
      Issue.record("fresh run did not create a simulation record")
      return
    }

    // User-initiated cancel (vs. the silent teardown above).
    run.env.sut.cancelSimulation()
    await run.runTask.value

    let rec = try await pollResumeStatus(run.env.simRepo, run.simId) {
      $0.simulationStatus == .cancelled
    }
    #expect(rec?.simulationStatus == .cancelled)
  }
}
