import Foundation
import Testing

@testable import Pastura

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

    let vm = HomeViewModel(repository: repo)
    await vm.loadScenarios()

    #expect(vm.presets.count == 1)
    #expect(vm.presets.first?.id == "preset1")
    #expect(vm.userScenarios.count == 1)
    #expect(vm.userScenarios.first?.id == "user1")
    #expect(vm.errorMessage == nil)
  }

  @Test func deleteScenarioRemovesFromList() async throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)

    try repo.save(
      ScenarioRecord(
        id: "user1", name: "User", yamlDefinition: "",
        isPreset: false, createdAt: Date(), updatedAt: Date()
      ))

    let vm = HomeViewModel(repository: repo)
    await vm.loadScenarios()
    #expect(vm.userScenarios.count == 1)

    await vm.deleteScenario("user1")
    #expect(vm.userScenarios.isEmpty)

    // Verify deleted from DB
    let record = try repo.fetchById("user1")
    #expect(record == nil)
  }

  @Test func loadScenariosHandlesEmptyDB() async throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)

    let vm = HomeViewModel(repository: repo)
    await vm.loadScenarios()

    #expect(vm.presets.isEmpty)
    #expect(vm.userScenarios.isEmpty)
    #expect(vm.errorMessage == nil)
  }
}
