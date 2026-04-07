import Foundation
import Testing

@testable import Pastura

@MainActor
struct ImportViewModelTests {
  private static let validYAML = """
    id: import_test
    name: Import Test
    description: A test
    agents: 2
    rounds: 1
    context: Context
    personas:
      - name: Alice
        description: Agent A
      - name: Bob
        description: Agent B
    phases:
      - type: speak_all
        prompt: "Say something"
        output:
          statement: string
    """

  @Test func validateMarksValidYAML() throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    let vm = ImportViewModel(repository: repo)

    vm.yamlText = Self.validYAML
    vm.validate()

    #expect(vm.isValid == true)
    #expect(vm.validationErrors.isEmpty)
  }

  @Test func validateDetectsEmptyInput() throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    let vm = ImportViewModel(repository: repo)

    vm.yamlText = ""
    vm.validate()

    #expect(vm.isValid == false)
    #expect(vm.validationErrors.count == 1)
  }

  @Test func validateDetectsInvalidYAML() throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    let vm = ImportViewModel(repository: repo)

    vm.yamlText = "not: valid: yaml: {{"
    vm.validate()

    #expect(vm.isValid == false)
    #expect(!vm.validationErrors.isEmpty)
  }

  @Test func savePersistsScenario() async throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    let vm = ImportViewModel(repository: repo)

    vm.yamlText = Self.validYAML
    vm.validate()
    let saved = await vm.save()

    #expect(saved == true)
    #expect(vm.savedScenarioId == "import_test")

    let record = try repo.fetchById("import_test")
    #expect(record != nil)
    #expect(record?.isPreset == false)
  }

  @Test func saveRejectsOverwritingPreset() async throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)

    // Save a preset with the same ID
    try repo.save(
      ScenarioRecord(
        id: "import_test", name: "Preset", yamlDefinition: "",
        isPreset: true, createdAt: Date(), updatedAt: Date()
      ))

    let vm = ImportViewModel(repository: repo)
    vm.yamlText = Self.validYAML
    vm.validate()
    let saved = await vm.save()

    #expect(saved == false)
    #expect(!vm.validationErrors.isEmpty)
  }

  @Test func scenarioGenerationPromptIsNotEmpty() {
    #expect(!ImportViewModel.scenarioGenerationPrompt.isEmpty)
  }
}
