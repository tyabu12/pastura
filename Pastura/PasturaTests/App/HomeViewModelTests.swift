import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct HomeViewModelTests {
  @Test func loadScenariosPopulatesPresetsAndUserLists() async throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)

    // Add a preset
    try repo.save(
      ScenarioRecord(
        id: "preset1", name: "Preset", yamlDefinition: "",
        isPreset: true, createdAt: Date(), updatedAt: Date()
      ))
    // Add a user scenario
    try repo.save(
      ScenarioRecord(
        id: "user1", name: "User", yamlDefinition: "",
        isPreset: false, createdAt: Date(), updatedAt: Date()
      ))

    let viewModel = HomeViewModel(repository: repo)
    await viewModel.loadScenarios()

    #expect(viewModel.presets.count == 1)
    #expect(viewModel.presets.first?.id == "preset1")
    #expect(viewModel.userScenarios.count == 1)
    #expect(viewModel.userScenarios.first?.id == "user1")
    #expect(viewModel.errorMessage == nil)
  }

  @Test func deleteScenarioRemovesFromList() async throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)

    try repo.save(
      ScenarioRecord(
        id: "user1", name: "User", yamlDefinition: "",
        isPreset: false, createdAt: Date(), updatedAt: Date()
      ))

    let viewModel = HomeViewModel(repository: repo)
    await viewModel.loadScenarios()
    #expect(viewModel.userScenarios.count == 1)

    await viewModel.deleteScenario("user1")
    #expect(viewModel.userScenarios.isEmpty)

    // Verify deleted from DB
    let record = try repo.fetchById("user1")
    #expect(record == nil)
  }

  @Test func loadScenariosHandlesEmptyDB() async throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)

    let viewModel = HomeViewModel(repository: repo)
    await viewModel.loadScenarios()

    #expect(viewModel.presets.isEmpty)
    #expect(viewModel.userScenarios.isEmpty)
    #expect(viewModel.errorMessage == nil)
  }
}
