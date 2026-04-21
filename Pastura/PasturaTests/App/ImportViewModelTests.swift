import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
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
    let viewModel = ImportViewModel(repository: repo)

    viewModel.yamlText = Self.validYAML
    viewModel.validate()

    #expect(viewModel.isValid == true)
    #expect(viewModel.validationErrors.isEmpty)
  }

  @Test func validateDetectsEmptyInput() throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    let viewModel = ImportViewModel(repository: repo)

    viewModel.yamlText = ""
    viewModel.validate()

    #expect(viewModel.isValid == false)
    #expect(viewModel.validationErrors.count == 1)
  }

  @Test func validateDetectsInvalidYAML() throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    let viewModel = ImportViewModel(repository: repo)

    viewModel.yamlText = "not: valid: yaml: {{"
    viewModel.validate()

    #expect(viewModel.isValid == false)
    #expect(!viewModel.validationErrors.isEmpty)
  }

  @Test func savePersistsScenario() async throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    let viewModel = ImportViewModel(repository: repo)

    viewModel.yamlText = Self.validYAML
    viewModel.validate()
    let saved = await viewModel.save()

    #expect(saved == true)
    #expect(viewModel.savedScenarioId == "import_test")

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

    let viewModel = ImportViewModel(repository: repo)
    viewModel.yamlText = Self.validYAML
    viewModel.validate()
    let saved = await viewModel.save()

    #expect(saved == false)
    #expect(!viewModel.validationErrors.isEmpty)
  }

  @Test func scenarioGenerationPromptIsNotEmpty() {
    #expect(!ImportViewModel.scenarioGenerationPrompt.isEmpty)
  }

  // MARK: - Content Validation

  @Test func validateRejectsBlockedPersonaDescription() throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    let viewModel = ImportViewModel(repository: repo)

    // Uses the default bundled blocklist — "殺す" is present in ContentBlocklist.txt.
    viewModel.yamlText = """
      id: blocked_content_test
      name: Blocked Content Test
      description: A test
      agents: 2
      rounds: 1
      context: Context
      personas:
        - name: Alice
          description: 殺す
        - name: Bob
          description: Agent B
      phases:
        - type: speak_all
          prompt: "Say something"
          output:
            statement: string
      """
    viewModel.validate()

    #expect(viewModel.isValid == false)
    #expect(!viewModel.validationErrors.isEmpty)
    #expect(
      viewModel.validationErrors.contains { $0.contains("Alice") && $0.contains("description") })
  }
}
