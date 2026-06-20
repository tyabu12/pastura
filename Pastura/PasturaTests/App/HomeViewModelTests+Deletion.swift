import Foundation
import Testing

@testable import Pastura

// MARK: - Scenario deletion (#686)

/// In-memory `ScenarioRepository` whose `delete(_:)` always throws, while
/// `fetchAll()` still returns the seeded rows. Required because a single
/// repository instance backs both `HomeViewModel.loadScenarios()` (via
/// `fetchAll`) and `HomeViewModel.deleteScenario(_:)` (via `delete`): to
/// exercise the failure path we need the list populated *and* the delete
/// to fail, which a real `GRDBScenarioRepository` cannot do at once.
///
/// `nonisolated` because the suite is `@MainActor`; the type holds only
/// immutable `let` data, so the `Sendable` conformance is sound without
/// MainActor binding (`.claude/rules/swift-isolation.md`).
nonisolated struct ThrowingDeleteScenarioRepository: ScenarioRepository {
  let scenarios: [ScenarioRecord]

  func save(_ record: ScenarioRecord) throws {}
  func fetchById(_ id: String) throws -> ScenarioRecord? { scenarios.first { $0.id == id } }
  func fetchBySource(type: String, id: String) throws -> ScenarioRecord? { nil }
  func fetchBySourceType(_ type: String) throws -> [ScenarioRecord] {
    scenarios.filter { $0.sourceType == type }
  }
  func fetchAll() throws -> [ScenarioRecord] { scenarios }
  func fetchAllSummaries() throws -> [ScenarioSummary] {
    scenarios.map {
      ScenarioSummary(
        id: $0.id, name: $0.name, isPreset: $0.isPreset, sourceId: $0.sourceId,
        language: $0.language)
    }
  }
  func fetchByIds(_ ids: [String]) throws -> [ScenarioRecord] {
    scenarios.filter { ids.contains($0.id) }
  }
  func fetchPresets() throws -> [ScenarioRecord] { scenarios.filter { $0.isPreset } }

  func delete(_ id: String) throws {
    // Distinctive description so the test can assert on a stable substring.
    throw DataError.databaseOpenFailed(description: "stub-delete-failure")
  }
}

extension HomeViewModelTests {
  /// A delete that throws sets `errorMessage` and leaves `userScenarios`
  /// untouched — no partial mutation. The pre-delete assertion proves the
  /// list was populated, so the "still contains" check is non-vacuous.
  @Test func deleteScenarioFailureSetsErrorAndKeepsList() async throws {
    let repo = ThrowingDeleteScenarioRepository(
      scenarios: [
        ScenarioRecord(
          id: "user1", name: "User", yamlDefinition: "",
          isPreset: false, createdAt: Date(), updatedAt: Date()
        )
      ])

    let viewModel = HomeViewModel(repository: repo)
    await viewModel.loadScenarios()

    // Load-bearing guard: the list must be populated for the post-delete
    // assertion to mean anything.
    #expect(viewModel.userScenarios.count == 1)
    #expect(viewModel.userScenarios.first?.id == "user1")

    await viewModel.deleteScenario("user1")

    #expect(viewModel.errorMessage != nil)
    #expect(viewModel.errorMessage?.contains("stub-delete-failure") == true)
    // No partial mutation: the scenario survives the failed delete.
    #expect(viewModel.userScenarios.contains { $0.id == "user1" })
  }

  /// `deleteScenario` does **not** gate presets — its `removeAll` is scoped
  /// to `userScenarios`, so passing a preset id is a no-op against that
  /// array. (Preventing preset deletion is the View's job: `HomeView` gates
  /// the affordance, and at the DB layer the row would in fact be removed.)
  /// We therefore assert only that `userScenarios` is unchanged; asserting
  /// the preset is "protected" would be a false contract.
  @Test func deleteScenarioWithPresetIdIsNoOpAgainstUserScenarios() async throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)

    try repo.save(
      ScenarioRecord(
        id: "preset1", name: "Preset", yamlDefinition: "",
        isPreset: true, createdAt: Date(), updatedAt: Date()
      ))
    try repo.save(
      ScenarioRecord(
        id: "user1", name: "User", yamlDefinition: "",
        isPreset: false, createdAt: Date(), updatedAt: Date()
      ))

    let viewModel = HomeViewModel(repository: repo)
    await viewModel.loadScenarios()
    #expect(viewModel.userScenarios.count == 1)

    await viewModel.deleteScenario("preset1")

    #expect(viewModel.userScenarios.count == 1)
    #expect(viewModel.userScenarios.first?.id == "user1")
    #expect(viewModel.errorMessage == nil)
  }
}
