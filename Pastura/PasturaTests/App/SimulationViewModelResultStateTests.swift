import Foundation
import Testing

@testable import Pastura

/// Unit coverage for the result-state accumulators consumed by the
/// final-ranking card (issue #868):
///
/// - ``SimulationViewModel/eliminationVotes`` — per-agent vote count captured
///   at the moment each agent was eliminated (round-correct, unlike a
///   last-wins tally which drops earlier-round participants).
/// - ``SimulationViewModel/voteResults`` — the latest vote-phase tallies,
///   used to rank a vote-only ("popularity vote") scenario that eliminates
///   nobody.
///
/// The card's own display derivation is tested separately in
/// `SimulationResultCardTests`; these tests only pin that the VM feeds it the
/// right raw data.
@Suite(.serialized, .timeLimit(.minutes(1))) @MainActor
struct SimulationViewModelResultStateTests {
  private func makeModel() throws -> (SimulationViewModel, Scenario) {
    let db = try DatabaseManager.inMemory()
    let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
    let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
    let codeRepo = GRDBCodePhaseEventRepository(dbWriter: db.dbWriter)
    let model = SimulationViewModel(
      simulationRepository: simRepo,
      turnRepository: turnRepo,
      codePhaseEventRepository: codeRepo)
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob", "Carol"], rounds: 1)
    return (model, scenario)
  }

  @Test("Elimination events capture each agent's own vote count")
  func eliminationVotesCaptured() throws {
    let (model, scenario) = try makeModel()
    model.handleEvent(.elimination(agent: "Bob", voteCount: 3), scenario: scenario)
    model.handleEvent(.elimination(agent: "Carol", voteCount: 2), scenario: scenario)
    #expect(model.eliminationVotes["Bob"] == 3)
    #expect(model.eliminationVotes["Carol"] == 2)
    #expect(model.eliminationVotes["Alice"] == nil)
  }

  @Test("A multi-round elimination retains each agent's own round count")
  func multiRoundEliminationVotesRetained() throws {
    // Bob eliminated first (2 votes), Carol later (4 votes). Bob's count must
    // survive the later elimination — a last-wins vote tally would drop the
    // earlier-round participant, leaving Bob's survival row without a number.
    let (model, scenario) = try makeModel()
    model.handleEvent(.elimination(agent: "Bob", voteCount: 2), scenario: scenario)
    model.handleEvent(.elimination(agent: "Carol", voteCount: 4), scenario: scenario)
    #expect(model.eliminationVotes["Bob"] == 2)
    #expect(model.eliminationVotes["Carol"] == 4)
  }

  @Test("voteResults reflects the latest vote-phase tallies (last-wins)")
  func voteResultsLastWins() throws {
    let (model, scenario) = try makeModel()
    model.handleEvent(
      .voteResults(votes: ["Alice": "Bob"], tallies: ["Bob": 1]), scenario: scenario)
    model.handleEvent(
      .voteResults(votes: ["Alice": "Carol", "Bob": "Carol"], tallies: ["Carol": 2]),
      scenario: scenario)
    #expect(model.voteResults == ["Carol": 2])
  }
}
