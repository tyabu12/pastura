import Foundation
import Testing

@testable import Pastura

/// Tests persistence of code-phase events to `code_phase_events` table,
/// plus the shared `sequenceNumber` invariant across turns and code-phase
/// tables.
@Suite(.serialized, .timeLimit(.minutes(1))) @MainActor
// swiftlint:disable:next type_name
struct SimulationViewModelCodePhasePersistenceTests {

  private struct SUT {
    let model: SimulationViewModel
    let scenario: Scenario
    let turnRepo: GRDBTurnRepository
    let codeRepo: GRDBCodePhaseEventRepository
    let simId: String
  }

  private func makeSUT() throws -> SUT {
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
        id: simId, scenarioId: "test",
        status: "running", currentRound: 1, currentPhaseIndex: 0,
        stateJSON: "{}", configJSON: nil,
        createdAt: Date(), updatedAt: Date()))

    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"], rounds: 1)
    let model = SimulationViewModel(
      simulationRepository: simRepo,
      turnRepository: turnRepo,
      codePhaseEventRepository: codeRepo)
    model.beginPersistenceForTest(simulationId: simId)

    return SUT(
      model: model, scenario: scenario,
      turnRepo: turnRepo, codeRepo: codeRepo, simId: simId)
  }

  private func decodePayload(_ json: String) throws -> CodePhaseEventPayload {
    let data = Data(json.utf8)
    return try JSONDecoder().decode(CodePhaseEventPayload.self, from: data)
  }

  // MARK: - Basic persistence of each code-phase event type

  @Test func persistsAllSixCodePhaseEventTypes() async throws {
    let sut = try makeSUT()
    sut.model.handleEvent(.roundStarted(round: 1, totalRounds: 1), scenario: sut.scenario)

    sut.model.handleEvent(.assignment(agent: "Alice", value: "wolf"), scenario: sut.scenario)
    sut.model.handleEvent(.scoreUpdate(scores: ["Alice": 1]), scenario: sut.scenario)
    sut.model.handleEvent(.elimination(agent: "Bob", voteCount: 2), scenario: sut.scenario)
    sut.model.handleEvent(.summary(text: "round summary"), scenario: sut.scenario)
    sut.model.handleEvent(
      .voteResults(votes: ["Alice": "Bob"], tallies: ["Bob": 1]),
      scenario: sut.scenario)
    sut.model.handleEvent(
      .pairingResult(agent1: "A", action1: "c", agent2: "B", action2: "d"),
      scenario: sut.scenario)

    await sut.model.finishPersistenceForTest()

    let records = try sut.codeRepo.fetchBySimulationId(sut.simId)
    #expect(records.count == 6)

    let payloads = try records.map { try decodePayload($0.payloadJSON) }
    #expect(payloads.contains(.assignment(agent: "Alice", value: "wolf")))
    #expect(payloads.contains(.scoreUpdate(scores: ["Alice": 1])))
    #expect(payloads.contains(.elimination(agent: "Bob", voteCount: 2)))
    #expect(payloads.contains(.summary(text: "round summary")))
    #expect(
      payloads.contains(
        .voteResults(votes: ["Alice": "Bob"], tallies: ["Bob": 1])))
    #expect(
      payloads.contains(
        .pairingResult(agent1: "A", action1: "c", agent2: "B", action2: "d")))
  }

  // MARK: - Shared sequence number across tables

  @Test func interleavedAgentAndCodeEventsHaveStrictlyMonotonicSequence() async throws {
    let sut = try makeSUT()
    sut.model.handleEvent(.roundStarted(round: 1, totalRounds: 1), scenario: sut.scenario)

    // Interleave: agent, code, agent, code, agent, code
    sut.model.handleEvent(
      .agentOutput(
        agent: "Alice",
        output: TurnOutput(fields: ["vote": "Bob"]),
        phaseType: .vote),
      scenario: sut.scenario)
    sut.model.handleEvent(
      .voteResults(votes: ["Alice": "Bob"], tallies: ["Bob": 1]),
      scenario: sut.scenario)
    sut.model.handleEvent(
      .agentOutput(
        agent: "Bob",
        output: TurnOutput(fields: ["vote": "Alice"]),
        phaseType: .vote),
      scenario: sut.scenario)
    sut.model.handleEvent(
      .elimination(agent: "Bob", voteCount: 1),
      scenario: sut.scenario)
    sut.model.handleEvent(
      .agentOutput(
        agent: "Alice",
        output: TurnOutput(fields: ["statement": "done"]),
        phaseType: .summarize),
      scenario: sut.scenario)
    sut.model.handleEvent(
      .summary(text: "Alice won"),
      scenario: sut.scenario)

    await sut.model.finishPersistenceForTest()

    let turns = try sut.turnRepo.fetchBySimulationId(sut.simId)
    let codeEvents = try sut.codeRepo.fetchBySimulationId(sut.simId)

    #expect(turns.count == 3)
    #expect(codeEvents.count == 3)

    let allSequences =
      (turns.map(\.sequenceNumber) + codeEvents.map(\.sequenceNumber))
      .sorted()
    #expect(allSequences == [1, 2, 3, 4, 5, 6])
  }

  // MARK: - round == 0 summary skip

  @Test func summaryAtRoundZeroIsNotPersistedButAppearsInLog() async throws {
    let sut = try makeSUT()
    // currentRound is 0 before roundStarted fires.
    sut.model.handleEvent(.summary(text: "⚠️ validator warning"), scenario: sut.scenario)

    await sut.model.finishPersistenceForTest()

    let records = try sut.codeRepo.fetchBySimulationId(sut.simId)
    #expect(records.isEmpty)

    // But UI log still shows it.
    #expect(
      sut.model.logEntries.contains { entry in
        if case .summary(let text) = entry.kind { return text.contains("validator") }
        return false
      })
  }

  // MARK: - currentPhaseType tracking

  @Test func summaryInheritsActivePhaseTypeNotHardcodedSummarize() async throws {
    // wordwolf_judge emits .summary INSIDE the score_calc phase; a separate
    // SummarizeHandler emits .summary inside the summarize phase. Both must
    // be persisted under the phase that actually emitted them so the exporter
    // groups them correctly.
    let sut = try makeSUT()
    sut.model.handleEvent(.roundStarted(round: 1, totalRounds: 1), scenario: sut.scenario)

    // score_calc phase: judge verdict summary
    sut.model.handleEvent(
      .phaseStarted(phaseType: .scoreCalc, phaseIndex: 0), scenario: sut.scenario)
    sut.model.handleEvent(
      .summary(text: "多数派の勝ち！"), scenario: sut.scenario)
    sut.model.handleEvent(
      .phaseCompleted(phaseType: .scoreCalc, phaseIndex: 0), scenario: sut.scenario)

    // summarize phase: round wrap summary
    sut.model.handleEvent(
      .phaseStarted(phaseType: .summarize, phaseIndex: 1), scenario: sut.scenario)
    sut.model.handleEvent(
      .summary(text: "Round 1 ends."), scenario: sut.scenario)

    await sut.model.finishPersistenceForTest()

    let records = try sut.codeRepo.fetchBySimulationId(sut.simId)
    #expect(records.count == 2)
    let judgeRecord = try #require(
      records.first { $0.payloadJSON.contains("多数派の勝ち") })
    let wrapRecord = try #require(
      records.first { $0.payloadJSON.contains("Round 1 ends") })
    #expect(judgeRecord.phaseType == "score_calc")
    #expect(wrapRecord.phaseType == "summarize")
  }

  @Test func otherCodePhaseEventsAtRoundZeroArePersisted() async throws {
    // Only .summary is suppressed at round==0 (validator warning / early-term);
    // other events would be genuine bugs if they fired pre-round, so persist them
    // to surface the issue in exports.
    let sut = try makeSUT()

    sut.model.handleEvent(.scoreUpdate(scores: ["Alice": 1]), scenario: sut.scenario)

    await sut.model.finishPersistenceForTest()

    let records = try sut.codeRepo.fetchBySimulationId(sut.simId)
    #expect(records.count == 1)
    #expect(records.first?.roundNumber == 0)
  }
}
