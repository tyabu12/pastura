#if DEBUG

  import Foundation
  import Testing

  @testable import Pastura

  /// Unit tests for ``StubResultSeeder`` fixtures.
  ///
  /// Validates that the seeded simulation + turns surface through the same
  /// `ResultsViewModel` pipeline the Past Results screens use, so fixture
  /// drift (record shape, status raw value, parsed-output JSON) breaks here
  /// in-process instead of inside the slow UI-test tour.
  @Suite(.timeLimit(.minutes(1)))
  @MainActor
  struct StubResultSeederTests {

    @Test func testSeededResultSurfacesThroughResultsViewModel() async throws {
      let db = try DatabaseManager.inMemory()
      let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
      let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
      let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)

      // Same ordering as setupUITestState: scenario seed first, then results.
      try await StubScenarioSeeder.seed(into: scenarioRepo)
      try await StubResultSeeder.seed(
        simulationRepository: simRepo, turnRepository: turnRepo)

      let viewModel = ResultsViewModel(
        scenarioRepository: scenarioRepo,
        simulationRepository: simRepo,
        turnRepository: turnRepo
      )
      // `.aggregate` is the History-root entry-point: aggregate across
      // all scenarios (see ``ResultsScope``).
      await viewModel.load(scope: .aggregate)

      #expect(viewModel.errorMessage == nil)
      #expect(viewModel.sections.count == 1, "seeded run should form one date section")
      let row = try #require(viewModel.sections.first?.rows.first)
      #expect(row.item.id == StubResultSeeder.simulationId)
      #expect(row.item.simulationStatus == .completed)

      let turns = await viewModel.loadTurns(
        simulationId: StubResultSeeder.simulationId)
      #expect(turns.count == 4, "expected 2 rounds x 2 agents")

      // Every parsedOutputJSON must decode through TurnOutput — the exact
      // path ResultDetailView.decodeTurnOutput renders — and carry a
      // statement, else the timeline shows empty bubbles.
      for turn in turns {
        let data = try #require(turn.parsedOutputJSON.data(using: .utf8))
        let output = try JSONDecoder().decode(TurnOutput.self, from: data)
        #expect(output.statement?.isEmpty == false, "turn \(turn.id) lacks statement")
      }
    }
  }

#endif
