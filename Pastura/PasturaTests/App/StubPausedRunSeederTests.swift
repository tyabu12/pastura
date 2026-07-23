#if DEBUG

  import Foundation
  import Testing

  @testable import Pastura

  /// Unit tests for ``StubPausedRunSeeder``.
  ///
  /// Validates that the seeded paused run surfaces through the same
  /// `HomeViewModel.pausedSummary` pipeline the Home resume card uses, so
  /// fixture drift (status raw value, scenario reference, round count) breaks
  /// here in-process instead of inside the slow UI-test tour.
  @Suite(.timeLimit(.minutes(1)))
  @MainActor
  struct StubPausedRunSeederTests {

    @Test func testSeededPausedRunSurfacesAsResumeCard() async throws {
      let db = try DatabaseManager.inMemory()
      let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
      let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)

      // Same pairing setupUITestState enforces: rich seed (carries the
      // referenced scenario) before the paused run. The language is pinned
      // rather than defaulted so the name assertion below can compare against a
      // literal — a `LocaleResolver`-derived expectation would pass on any
      // runner locale without proving the copy reached the record.
      try await StubScenarioSeeder.seedRichHome(into: scenarioRepo, language: "ja")
      try await StubPausedRunSeeder.seed(simulationRepository: simRepo, language: "ja")

      let paused = try simRepo.fetchByStatus(.paused)
      #expect(paused.count == 1, "expected exactly one seeded paused run")
      let run = try #require(paused.first)
      #expect(run.id == StubPausedRunSeeder.simulationId)
      #expect(run.scenarioId == StubScenarioSeeder.richWordWolfScenarioId)
      #expect(run.currentRound < StubScenarioSeeder.richWordWolfRounds)

      // Surface through HomeViewModel so the resume-card model actually builds
      // with a non-nil, in-range progress (currentRound < rounds).
      let viewModel = HomeViewModel(
        repository: scenarioRepo, simulationRepository: simRepo)
      await viewModel.loadScenarios()

      let summary = try #require(
        viewModel.pausedSummary, "pausedSummary should be non-nil after seeding a paused run")
      #expect(summary.runId == StubPausedRunSeeder.simulationId)
      #expect(summary.name == "ワードウルフ")
      #expect(summary.rounds == StubScenarioSeeder.richWordWolfRounds)
      #expect(summary.currentRound == StubPausedRunSeeder.currentRound)
    }
  }

#endif
