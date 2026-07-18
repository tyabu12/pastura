import Foundation
import Testing

@testable import Pastura

/// ADR-022 D5 — cross-VM parity regression. Feeds one canonical instance of
/// **every** `SimulationEvent` case through both `SimulationViewModel.handleEvent`
/// and `ReplayViewModel.apply`, and asserts that for the shared code-phase
/// subset both sides project the same semantic value (compared through the
/// common `CodePhaseLine(payload:filter:)` mapper with a passthrough filter, so
/// replay's defense-in-depth ContentFilter doesn't skew the comparison). Every
/// non-code-phase event must produce NO code-phase projection on either side.
///
/// The `fixtureCase(of:)` switch is no-default over `SimulationEvent`, so a
/// newly added event case breaks THIS test target's compile until the fixture
/// mirror and the parity expectation are extended — the executable registry of
/// intended cross-VM asymmetry the P2 `apply` header comment entrusts to prose.
@Suite(.serialized, .timeLimit(.minutes(1))) @MainActor
struct CrossVMEventParityTests {

  // MARK: - Exhaustive fixture (compile-break on a new SimulationEvent case)

  /// Mirror of every `SimulationEvent` case. `CaseIterable` so the fixture is
  /// built by iterating all members; kept in lockstep with `SimulationEvent`
  /// by the no-default `fixtureCase(of:)` pin below.
  private enum EventCase: CaseIterable {
    case roundStarted, roundCompleted, phaseStarted, phaseCompleted
    case agentOutput, agentOutputStream
    case scoreUpdate, elimination, assignment, sharedAssignment, summary, narration
    case relationshipUpdate, voteResults, pairingResult, conditionalEvaluated
    case eventInjected, simulationCompleted, roundCheckpoint, simulationPaused
    case error, inferenceStarted, inferenceCompleted, languageMismatch, turnSkipped
    case actionRejected
  }

  /// One canonical `SimulationEvent` instance per fixture case.
  private func canonicalEvent(_ eventCase: EventCase) -> SimulationEvent {  // swiftlint:disable:this cyclomatic_complexity
    switch eventCase {
    case .roundStarted: return .roundStarted(round: 1, totalRounds: 3)
    case .roundCompleted: return .roundCompleted(round: 1, scores: ["Alice": 1])
    case .phaseStarted: return .phaseStarted(phaseType: .speakAll, phasePath: [0])
    case .phaseCompleted: return .phaseCompleted(phaseType: .speakAll, phasePath: [0])
    case .agentOutput:
      return .agentOutput(
        agent: "Alice", output: TurnOutput(fields: ["statement": "hi"]),
        phaseType: .speakAll)
    case .agentOutputStream:
      return .agentOutputStream(agent: "Alice", primary: "hi", thought: nil)
    case .scoreUpdate: return .scoreUpdate(scores: ["Alice": 2])
    case .elimination: return .elimination(agent: "Bob", voteCount: 2)
    case .assignment: return .assignment(agent: "Alice", value: "wolf")
    case .sharedAssignment: return .sharedAssignment(value: "topic")
    case .summary: return .summary(text: "round summary")
    case .narration: return .narration(text: "Alice made a bold move")
    case .relationshipUpdate:
      return .relationshipUpdate(relationships: ["Alice": ["Bob": 1]])
    case .voteResults:
      return .voteResults(votes: ["Alice": "Bob"], tallies: ["Bob": 1])
    case .pairingResult:
      return .pairingResult(agent1: "Alice", action1: "c", agent2: "Bob", action2: "d")
    case .conditionalEvaluated:
      return .conditionalEvaluated(condition: "x > 0", result: true)
    case .eventInjected: return .eventInjected(event: "meteor")
    case .simulationCompleted: return .simulationCompleted
    case .roundCheckpoint: return .roundCheckpoint(state: SimulationState())
    case .simulationPaused: return .simulationPaused(round: 1, phasePath: [0])
    case .error: return .error(.cancelled)
    case .inferenceStarted: return .inferenceStarted(agent: "Alice")
    case .inferenceCompleted:
      return .inferenceCompleted(agent: "Alice", durationSeconds: 1, tokenCount: 10)
    case .languageMismatch:
      return .languageMismatch(agent: "Alice", detected: "en", expected: "ja")
    case .turnSkipped:
      return .turnSkipped(agent: "Alice", phaseType: .speakAll, cause: "x")
    case .actionRejected:
      return .actionRejected(agent: "Alice", phaseType: .choose, raw: "betray!")
    }
  }

  /// Compile-break pin: no-default over `SimulationEvent`. A new event case
  /// fails HERE until its `EventCase` mirror + canonical instance are added.
  private func fixtureCase(of event: SimulationEvent) -> EventCase {  // swiftlint:disable:this cyclomatic_complexity
    switch event {
    case .roundStarted: return .roundStarted
    case .roundCompleted: return .roundCompleted
    case .phaseStarted: return .phaseStarted
    case .phaseCompleted: return .phaseCompleted
    case .agentOutput: return .agentOutput
    case .agentOutputStream: return .agentOutputStream
    case .scoreUpdate: return .scoreUpdate
    case .elimination: return .elimination
    case .assignment: return .assignment
    case .sharedAssignment: return .sharedAssignment
    case .summary: return .summary
    case .narration: return .narration
    case .relationshipUpdate: return .relationshipUpdate
    case .voteResults: return .voteResults
    case .pairingResult: return .pairingResult
    case .conditionalEvaluated: return .conditionalEvaluated
    case .eventInjected: return .eventInjected
    case .simulationCompleted: return .simulationCompleted
    case .roundCheckpoint: return .roundCheckpoint
    case .simulationPaused: return .simulationPaused
    case .error: return .error
    case .inferenceStarted: return .inferenceStarted
    case .inferenceCompleted: return .inferenceCompleted
    case .languageMismatch: return .languageMismatch
    case .turnSkipped: return .turnSkipped
    case .actionRejected: return .actionRejected
    }
  }

  @Test func fixtureCoversEverySimulationEventCaseExactlyOnce() {
    // Roundtrip guards a copy-paste slip in `canonicalEvent` (a case returning
    // the wrong instance). Combined with the no-default `fixtureCase(of:)`, this
    // pins the fixture to the full enum.
    for eventCase in EventCase.allCases {
      #expect(fixtureCase(of: canonicalEvent(eventCase)) == eventCase)
    }
  }

  // MARK: - Cross-VM code-phase parity

  @Test func bothVMsProjectTheSameCodePhaseSemantics() async throws {
    // Passthrough filter on BOTH sides so replay's defense-in-depth
    // ContentFilter doesn't diverge the comparison — parity is about the
    // semantic mapping, not the filtering policy (that asymmetry is exercised
    // by the ReplayViewModel ContentFilter suite).
    let passthrough = ContentFilter(blockedPatterns: [])

    for eventCase in EventCase.allCases {
      let event = canonicalEvent(eventCase)
      let expectedPayload = CodePhaseEventPayload(event: event)

      let simPayload = try await liveProjection(of: event)
      let replayLine = replayProjection(of: event, filter: passthrough)

      // Both VMs agree with the D3 semantic core on which events are code-phase.
      #expect(
        (simPayload != nil) == (expectedPayload != nil),
        "live VM code-phase membership diverged for \(eventCase)")
      #expect(
        (replayLine != nil) == (expectedPayload != nil),
        "replay VM code-phase membership diverged for \(eventCase)")

      guard let expectedPayload else {
        // Non-code-phase: no projection on either side — asserted by the two
        // membership checks above.
        continue
      }

      // Live VM persists the exact D3 payload.
      #expect(simPayload == expectedPayload, "live payload diverged for \(eventCase)")

      // Cross-VM parity: the live VM's persisted payload, run through the SAME
      // mapper replay uses, equals what replay actually produced.
      let simPayloadValue = try #require(simPayload)
      let expectedReplayLine = ReplayViewModel.CodePhaseLine(
        payload: simPayloadValue, filter: passthrough)
      #expect(
        replayLine == expectedReplayLine, "cross-VM line diverged for \(eventCase)")
    }
  }

  // MARK: - Per-VM drivers

  /// Drives the live VM's `handleEvent` and returns the code-phase payload it
  /// persisted for `event` (nil if none). A `.roundStarted` precedes the event
  /// so `.summary` clears the `currentRound > 0` persist gate — a realistic
  /// order that keeps the pre-round-summary drop out of scope here.
  private func liveProjection(
    of event: SimulationEvent
  ) async throws -> CodePhaseEventPayload? {
    let sut = try makeLiveSUT()
    sut.model.handleEvent(.roundStarted(round: 1, totalRounds: 3), scenario: sut.scenario)
    sut.model.handleEvent(event, scenario: sut.scenario)
    // Finish draining the persistence continuation, then read the committed rows.
    await sut.model.finishPersistenceForTest()
    let rows = try sut.codeRepo.fetchBySimulationId(sut.simId)
    // `.roundStarted` is not a code-phase event, so any row came from `event`.
    guard let last = rows.last else { return nil }
    return try JSONDecoder().decode(
      CodePhaseEventPayload.self, from: Data(last.payloadJSON.utf8))
  }

  /// Drives the replay VM's `apply` and returns the `CodePhaseLine` it appended
  /// for `event` (nil if none).
  private func replayProjection(
    of event: SimulationEvent, filter: ContentFilter
  ) -> ReplayViewModel.CodePhaseLine? {
    let viewModel = ReplayViewModel(sources: [], contentFilter: filter)
    viewModel.applyEventForTest(event)
    for item in viewModel.chatItems {
      if case .codePhaseLine(_, let line) = item { return line }
    }
    return nil
  }

  // MARK: - Live-VM harness

  private struct LiveSUT {
    let model: SimulationViewModel
    let scenario: Scenario
    let codeRepo: GRDBCodePhaseEventRepository
    let simId: String
  }

  private func makeLiveSUT() throws -> LiveSUT {
    let db = try DatabaseManager.inMemory()
    let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
    let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
    let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    let codeRepo = GRDBCodePhaseEventRepository(dbWriter: db.dbWriter)

    try scenarioRepo.save(
      ScenarioRecord(
        id: "test", name: "Test", yamlDefinition: "",
        isPreset: false, createdAt: Date(), updatedAt: Date()))
    let simId = "sim1"
    try simRepo.save(
      SimulationRecord(
        id: simId, scenarioId: "test", status: "running", currentRound: 1,
        currentPhaseIndex: 0, stateJSON: "{}", configJSON: nil,
        createdAt: Date(), updatedAt: Date()))

    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"], rounds: 1)
    let model = SimulationViewModel(
      simulationRepository: simRepo, turnRepository: turnRepo,
      codePhaseEventRepository: codeRepo)
    model.beginPersistenceForTest(simulationId: simId)
    return LiveSUT(model: model, scenario: scenario, codeRepo: codeRepo, simId: simId)
  }
}
