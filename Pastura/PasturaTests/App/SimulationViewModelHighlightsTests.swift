import Foundation
import Testing

@testable import Pastura

/// Integration coverage for `SimulationViewModel.highlightCandidates` (#1070
/// Stage 2) — the transcript→candidate projection that feeds the end-of-run
/// "Share a highlight" section. The pure selection rule is covered by
/// `HighlightCandidateLogicTests`; these pin the VM wiring: a 🃏 badge
/// becomes a candidate carrying the filtered output, and the non-empty
/// primary pre-filter (dead-tap guard) excludes an empty declaration.
///
/// The `.revealed` path (prediction ground truth) is not driven here: it
/// requires toggling the shared `FeatureFlags` UserDefaults key, which would
/// race a parallel suite (`.claude/rules/testing.md`). It is covered by
/// `HighlightCandidateLogicTests` (selection) + `SimulationViewModelPrediction
/// Tests` (`actualAgent` is carried on `PredictionOutcome`); the VM property
/// only forwards `predictionOutcome?.actualAgent` to the logic.
@Suite(.serialized, .timeLimit(.minutes(1))) @MainActor
struct SimulationViewModelHighlightsTests {

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

  private let phases = [
    Phase(type: .speakAll),
    Phase(type: .choose, options: ["cooperate", "betray"], pairing: .roundRobin)
  ]

  private func makeScenario() -> Scenario {
    makeTestScenario(agentNames: ["Alice", "Bob"], rounds: 1, phases: phases)
  }

  private func declaration(
    _ agent: String, _ intent: String, statement: String = "Let's all be friends."
  ) -> SimulationEvent {
    .agentOutput(
      agent: agent,
      output: TurnOutput(fields: [
        "statement": statement,
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

  private func speak(_ agent: String, _ text: String) -> SimulationEvent {
    .agentOutput(
      agent: agent,
      output: TurnOutput(fields: ["statement": text]),
      phaseType: .speakAll)
  }

  /// Drives Alice into a full declaration/action contradiction; Bob stays
  /// consistent. `statement` lets a caller blank Alice's public statement.
  private func runAliceContradiction(
    _ sut: SimulationViewModel, scenario: Scenario, aliceStatement: String
  ) {
    sut.handleEvent(.roundStarted(round: 1, totalRounds: 1), scenario: scenario)
    sut.handleEvent(
      declaration("Alice", "cooperate", statement: aliceStatement), scenario: scenario)
    sut.handleEvent(declaration("Bob", "cooperate"), scenario: scenario)
    sut.handleEvent(chooseAction("Alice", "betray"), scenario: scenario)
    sut.handleEvent(chooseAction("Bob", "cooperate"), scenario: scenario)
    sut.handleEvent(chooseAction("Alice", "betray"), scenario: scenario)
    sut.handleEvent(chooseAction("Bob", "cooperate"), scenario: scenario)
    sut.handleEvent(choosePhaseCompleted, scenario: scenario)
  }

  @Test func contradictionBadgeBecomesCandidateCarryingOutput() throws {
    let sut = try makeSut()
    let scenario = makeScenario()
    runAliceContradiction(sut, scenario: scenario, aliceStatement: "Trust me, I'm loyal.")

    let candidates = sut.highlightCandidates
    #expect(candidates.count == 1)
    let candidate = try #require(candidates.first)
    #expect(candidate.agent == "Alice")
    #expect(candidate.reason == .contradiction)
    #expect(candidate.previewText == "Trust me, I'm loyal.")
    // The candidate id is the badged declaration row's id.
    #expect(sut.contradictionBadgedEntryIDs.contains(candidate.id))
  }

  @Test func emptyPrimaryDeclarationIsFilteredEvenWhenBadged() throws {
    // Dead-tap guard: a badged row with no public statement must not surface —
    // `HighlightShareCard.Model`'s failable init would reject it on tap.
    let sut = try makeSut()
    let scenario = makeScenario()
    runAliceContradiction(sut, scenario: scenario, aliceStatement: "")

    #expect(sut.contradictionBadgedEntryIDs.count == 1)  // still badged…
    #expect(sut.highlightCandidates.isEmpty)  // …but not a candidate
  }

  @Test func noSignalsYieldsNoCandidates() throws {
    let sut = try makeSut()
    let scenario = makeScenario()
    sut.handleEvent(.roundStarted(round: 1, totalRounds: 1), scenario: scenario)
    sut.handleEvent(declaration("Alice", "cooperate"), scenario: scenario)
    sut.handleEvent(declaration("Bob", "cooperate"), scenario: scenario)
    // Consistent actions — no contradiction, no prediction scored.
    sut.handleEvent(chooseAction("Alice", "cooperate"), scenario: scenario)
    sut.handleEvent(chooseAction("Bob", "cooperate"), scenario: scenario)
    sut.handleEvent(choosePhaseCompleted, scenario: scenario)

    #expect(sut.highlightCandidates.isEmpty)
  }

  // MARK: Reaction signal (#1109)

  @Test func eventInjectReactionSurfacesFirstSpeakerAfter() throws {
    let sut = try makeSut()
    let scenario = makeScenario()
    sut.handleEvent(.roundStarted(round: 1, totalRounds: 1), scenario: scenario)
    sut.handleEvent(.eventInjected(event: "A storm hits the camp."), scenario: scenario)
    sut.handleEvent(speak("Alice", "We must regroup now!"), scenario: scenario)
    sut.handleEvent(speak("Bob", "Everyone stay calm."), scenario: scenario)

    let candidates = sut.highlightCandidates
    #expect(candidates.count == 1)
    let candidate = try #require(candidates.first)
    #expect(candidate.agent == "Alice")  // only the FIRST post-event speaker
    #expect(candidate.reason == .reaction)
    #expect(candidate.previewText == "We must regroup now!")
  }

  @Test func eventInjectMissDoesNotSurfaceReaction() throws {
    // `.eventInjected(nil)` = probability roll missed: logged but not a turning
    // point, so the following speak is an ordinary utterance, not a reaction.
    let sut = try makeSut()
    let scenario = makeScenario()
    sut.handleEvent(.roundStarted(round: 1, totalRounds: 1), scenario: scenario)
    sut.handleEvent(.eventInjected(event: nil), scenario: scenario)
    sut.handleEvent(speak("Alice", "Just another quiet turn."), scenario: scenario)

    #expect(sut.highlightCandidates.isEmpty)
  }

  @Test func voteResultsReactionSurfacesSameRoundSpeaker() throws {
    // A same-round speak after a vote reveal (a defense / parting line) reacts.
    let sut = try makeSut()
    let scenario = makeScenario()
    sut.handleEvent(.roundStarted(round: 1, totalRounds: 1), scenario: scenario)
    sut.handleEvent(
      .voteResults(votes: ["Alice": "Bob"], tallies: ["Bob": 1]), scenario: scenario)
    sut.handleEvent(speak("Bob", "You'll regret voting me out."), scenario: scenario)

    let candidates = sut.highlightCandidates
    #expect(candidates.count == 1)
    #expect(candidates.first?.agent == "Bob")
    #expect(candidates.first?.reason == .reaction)
  }

  @Test func contradictionOutranksReactionOnTheSameEntry() throws {
    // Alice's declaration is BOTH the first post-event speaker (reaction) and a
    // contradiction; the stronger signal wins and the entry surfaces once.
    let sut = try makeSut()
    let scenario = makeScenario()
    sut.handleEvent(.roundStarted(round: 1, totalRounds: 1), scenario: scenario)
    sut.handleEvent(.eventInjected(event: "A storm hits the camp."), scenario: scenario)
    sut.handleEvent(
      declaration("Alice", "cooperate", statement: "Trust me, I'm loyal."),
      scenario: scenario)
    sut.handleEvent(declaration("Bob", "cooperate"), scenario: scenario)
    sut.handleEvent(chooseAction("Alice", "betray"), scenario: scenario)
    sut.handleEvent(chooseAction("Bob", "cooperate"), scenario: scenario)
    sut.handleEvent(chooseAction("Alice", "betray"), scenario: scenario)
    sut.handleEvent(chooseAction("Bob", "cooperate"), scenario: scenario)
    sut.handleEvent(choosePhaseCompleted, scenario: scenario)

    let candidates = sut.highlightCandidates
    #expect(candidates.count == 1)
    #expect(candidates.first?.agent == "Alice")
    #expect(candidates.first?.reason == .contradiction)
  }
}
