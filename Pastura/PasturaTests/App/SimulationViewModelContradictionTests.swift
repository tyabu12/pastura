import Foundation
import GRDB
import Testing

@testable import Pastura

/// Integration coverage for the #916 contradiction-badge wiring in
/// `SimulationViewModel`: buffering, the choose-phase-completion evaluation
/// beat, per-round resets, and the reveal log line. The pure decision rule is
/// covered separately in `ContradictionDetectionLogicTests`; these tests pin
/// the VM plumbing around it.
@Suite(.serialized, .timeLimit(.minutes(1))) @MainActor
struct SimulationViewModelContradictionTests {

  private func makeSut() throws -> SimulationViewModel {
    let db = try DatabaseManager.inMemory()
    let writer = db.dbWriter
    let scenarioRepo = GRDBScenarioRepository(dbWriter: writer)
    let simRepo = GRDBSimulationRepository(dbWriter: writer)
    try scenarioRepo.save(
      ScenarioRecord(
        id: "s1", name: "PD", yamlDefinition: "y",
        isPreset: false, createdAt: Date(), updatedAt: Date()))
    try simRepo.save(
      SimulationRecord(
        id: "sim1", scenarioId: "s1", status: "running",
        currentRound: 1, currentPhaseIndex: 0, stateJSON: "{}", configJSON: nil,
        createdAt: Date(), updatedAt: Date()))
    let sut = SimulationViewModel(
      simulationRepository: simRepo,
      turnRepository: GRDBTurnRepository(dbWriter: writer),
      codePhaseEventRepository: GRDBCodePhaseEventRepository(dbWriter: writer))
    sut.beginPersistenceForTest(simulationId: "sim1")
    return sut
  }

  /// prisoners_dilemma-shaped phases: a declaration speak_all + an optioned
  /// round-robin choose.
  private let phases = [
    Phase(type: .speakAll),
    Phase(type: .choose, options: ["cooperate", "betray"], pairing: .roundRobin)
  ]

  private func makeScenario() -> Scenario {
    makeTestScenario(agentNames: ["Alice", "Bob"], rounds: 1, phases: phases)
  }

  private func declaration(_ agent: String, _ intent: String) -> SimulationEvent {
    .agentOutput(
      agent: agent,
      output: TurnOutput(fields: [
        "statement": "Let's all be friends.",
        "declared_intent": intent,
        "inner_thought": "…"
      ]),
      phaseType: .speakAll)
  }

  private func chooseAction(_ agent: String, _ action: String) -> SimulationEvent {
    .agentOutput(
      agent: agent,
      output: TurnOutput(fields: ["action": action, "inner_thought": "…"]),
      phaseType: .choose)
  }

  private let choosePhaseCompleted = SimulationEvent.phaseCompleted(
    phaseType: .choose, phasePath: [1])

  /// The id of the committed declaration row for `agent` (the retro-badge
  /// anchor the views look up).
  private func declarationEntryID(
    _ sut: SimulationViewModel, agent: String
  ) -> UUID? {
    sut.logEntries.first { entry in
      if case .agentOutput(let name, let output, .speakAll) = entry.kind {
        return name == agent && output.fields["declared_intent"] != nil
      }
      return false
    }?.id
  }

  private func revealedAgents(_ sut: SimulationViewModel) -> [String] {
    sut.logEntries.compactMap { entry in
      if case .contradictionRevealed(let agent) = entry.kind { return agent }
      return nil
    }
  }

  // MARK: Detection

  @Test func fullContradictionBadgesDeclarationAndAppendsReveal() throws {
    let sut = try makeSut()
    let scenario = makeScenario()
    sut.handleEvent(.roundStarted(round: 1, totalRounds: 1), scenario: scenario)
    sut.handleEvent(declaration("Alice", "cooperate"), scenario: scenario)
    sut.handleEvent(declaration("Bob", "cooperate"), scenario: scenario)
    sut.handleEvent(chooseAction("Alice", "betray"), scenario: scenario)
    sut.handleEvent(chooseAction("Bob", "cooperate"), scenario: scenario)
    sut.handleEvent(chooseAction("Alice", "betray"), scenario: scenario)
    sut.handleEvent(chooseAction("Bob", "cooperate"), scenario: scenario)
    sut.handleEvent(choosePhaseCompleted, scenario: scenario)

    let aliceRow = try #require(declarationEntryID(sut, agent: "Alice"))
    #expect(sut.contradictionBadgedEntryIDs == [aliceRow])
    #expect(revealedAgents(sut) == ["Alice"])
  }

  @Test func partialSplitDoesNotBadge() throws {
    let sut = try makeSut()
    let scenario = makeScenario()
    sut.handleEvent(.roundStarted(round: 1, totalRounds: 1), scenario: scenario)
    sut.handleEvent(declaration("Alice", "cooperate"), scenario: scenario)
    sut.handleEvent(chooseAction("Alice", "betray"), scenario: scenario)
    sut.handleEvent(chooseAction("Alice", "cooperate"), scenario: scenario)
    sut.handleEvent(choosePhaseCompleted, scenario: scenario)

    #expect(sut.contradictionBadgedEntryIDs.isEmpty)
    #expect(revealedAgents(sut).isEmpty)
  }

  @Test func noEvaluationBeforeChoosePhaseCompletes() throws {
    // The badge must not exist while actions are still landing — a
    // first-appearance betray would otherwise fire a premature verdict
    // (and spoil the reveal beat).
    let sut = try makeSut()
    let scenario = makeScenario()
    sut.handleEvent(.roundStarted(round: 1, totalRounds: 1), scenario: scenario)
    sut.handleEvent(declaration("Alice", "cooperate"), scenario: scenario)
    sut.handleEvent(chooseAction("Alice", "betray"), scenario: scenario)
    sut.handleEvent(chooseAction("Alice", "betray"), scenario: scenario)

    #expect(sut.contradictionBadgedEntryIDs.isEmpty)

    sut.handleEvent(choosePhaseCompleted, scenario: scenario)
    #expect(sut.contradictionBadgedEntryIDs.count == 1)
  }

  @Test func roundStartResetsDeclarationAndActionBuffers() throws {
    // A round-1 declaration must not badge against round-2 actions.
    let sut = try makeSut()
    let scenario = makeScenario()
    sut.handleEvent(.roundStarted(round: 1, totalRounds: 2), scenario: scenario)
    sut.handleEvent(declaration("Alice", "cooperate"), scenario: scenario)
    sut.handleEvent(.roundStarted(round: 2, totalRounds: 2), scenario: scenario)
    sut.handleEvent(chooseAction("Alice", "betray"), scenario: scenario)
    sut.handleEvent(chooseAction("Alice", "betray"), scenario: scenario)
    sut.handleEvent(choosePhaseCompleted, scenario: scenario)

    #expect(sut.contradictionBadgedEntryIDs.isEmpty)
  }

  @Test func scenarioWithoutChooseOptionsNeverBadges() throws {
    let sut = try makeSut()
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"], rounds: 1,
      phases: [Phase(type: .speakAll), Phase(type: .choose)])
    sut.handleEvent(.roundStarted(round: 1, totalRounds: 1), scenario: scenario)
    sut.handleEvent(declaration("Alice", "cooperate"), scenario: scenario)
    sut.handleEvent(chooseAction("Alice", "betray"), scenario: scenario)
    sut.handleEvent(choosePhaseCompleted, scenario: scenario)

    #expect(sut.contradictionBadgedEntryIDs.isEmpty)
  }

  @Test func revealOrderFollowsPersonaRoster() throws {
    // Two liars in one round: reveal lines follow the scenario's persona
    // order, not dictionary iteration order.
    let sut = try makeSut()
    let scenario = makeScenario()
    sut.handleEvent(.roundStarted(round: 1, totalRounds: 1), scenario: scenario)
    sut.handleEvent(declaration("Bob", "cooperate"), scenario: scenario)
    sut.handleEvent(declaration("Alice", "cooperate"), scenario: scenario)
    for _ in 0..<2 {
      sut.handleEvent(chooseAction("Alice", "betray"), scenario: scenario)
      sut.handleEvent(chooseAction("Bob", "betray"), scenario: scenario)
    }
    sut.handleEvent(choosePhaseCompleted, scenario: scenario)

    #expect(revealedAgents(sut) == ["Alice", "Bob"])
  }
}
