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
      let codeEventRepo = GRDBCodePhaseEventRepository(dbWriter: db.dbWriter)

      // Same ordering as setupUITestState: scenario seed first, then results.
      try await StubScenarioSeeder.seed(into: scenarioRepo)
      try await StubResultSeeder.seed(
        simulationRepository: simRepo, turnRepository: turnRepo,
        codePhaseEventRepository: codeEventRepo)

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

    /// Guards the two marketing transcripts against verbatim drift in-process
    /// (faster than the `MarketingShotTests` UI capture): the counts, a
    /// load-bearing on-screen anchor, and — for prisoners — that the editorial
    /// 皮肉な着地 line is NOT seeded (it is doc annotation, not model output).
    @Test func testMarketingFixturesSeedVerbatimTimelines() async throws {
      let wolf = try await seedFixture(.wordWolf)
      #expect(wolf.turns.count == 3, "レン speak_each + サクラ/ユウキ votes")
      #expect(wolf.events.count == 2, "vote_results + summary")
      #expect(
        statements(wolf.turns).contains { $0.contains("全体の形について語りたい") },
        "レン's statement is the on-screen 綻び")
      #expect(summaries(wolf.events).contains { $0.contains("ウルフ発見") })

      let dilemma = try await seedFixture(.prisoners)
      #expect(dilemma.turns.count == 2, "public speak_all + whisper")
      #expect(dilemma.events.count == 1, "summary only")
      #expect(dilemma.turns.contains { $0.phaseType == "whisper" }, "密談 turn present")
      #expect(
        summaries(dilemma.events).allSatisfy { !$0.contains("皮肉な着地") },
        "editorial annotation must never be seeded")
    }

    private func seedFixture(_ fixture: StubResultSeeder.MarketingFixture) async throws
      -> (turns: [TurnRecord], events: [CodePhaseEventRecord]) {
      let db = try DatabaseManager.inMemory()
      let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
      let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
      let codeEventRepo = GRDBCodePhaseEventRepository(dbWriter: db.dbWriter)
      try await StubResultSeeder.seed(
        simulationRepository: simRepo, turnRepository: turnRepo,
        codePhaseEventRepository: codeEventRepo, fixture: fixture)
      return (
        try turnRepo.fetchBySimulationId(StubResultSeeder.simulationId),
        try codeEventRepo.fetchBySimulationId(StubResultSeeder.simulationId)
      )
    }

    private func statements(_ turns: [TurnRecord]) -> [String] {
      turns.compactMap { turn in
        guard let data = turn.parsedOutputJSON.data(using: .utf8),
          let out = try? JSONDecoder().decode(TurnOutput.self, from: data)
        else { return nil }
        return out.statement
      }
    }

    private func summaries(_ events: [CodePhaseEventRecord]) -> [String] {
      events.compactMap { event in
        guard let data = event.payloadJSON.data(using: .utf8),
          let payload = try? JSONDecoder().decode(CodePhaseEventPayload.self, from: data)
        else { return nil }
        if case .summary(let text) = payload { return text }
        return nil
      }
    }
  }

#endif
