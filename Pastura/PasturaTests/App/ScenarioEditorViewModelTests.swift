import Foundation
import Testing

@testable import Pastura

@MainActor
struct ScenarioEditorViewModelTests {
  private static let validYAML = """
    id: editor_test
    name: Editor Test
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

  // MARK: - Initialization

  @Test func initializesWithEmptyState() throws {
    let sut = try makeSUT()
    #expect(sut.scenarioName.isEmpty)
    #expect(sut.phases.isEmpty)
    #expect(sut.personas.isEmpty)
    #expect(sut.editorMode == .visual)
  }

  @Test func initializesFromTemplateScenario() throws {
    let sut = try makeSUT()
    sut.loadFromTemplate(yaml: Self.validYAML)

    #expect(sut.scenarioName == "Editor Test")
    #expect(sut.agentCount == 2)
    #expect(sut.rounds == 1)
    #expect(sut.personas.count == 2)
    #expect(sut.phases.count == 1)
  }

  @Test func templateDuplicationGeneratesNewId() throws {
    let sut = try makeSUT()
    sut.loadFromTemplate(yaml: Self.validYAML)

    // ID should not be the original preset ID
    #expect(sut.scenarioId != "editor_test")
    #expect(!sut.scenarioId.isEmpty)
  }

  // MARK: - Mode Switching

  @Test func switchToYAMLSerializesCurrentState() throws {
    let sut = try makeSUT()
    sut.loadFromTemplate(yaml: Self.validYAML)
    // Restore the original ID for this test
    sut.scenarioId = "editor_test"

    sut.switchToYAMLMode()

    #expect(sut.editorMode == .yaml)
    #expect(sut.yamlText.contains("editor_test"))
    #expect(sut.yamlText.contains("Editor Test"))
  }

  @Test func switchToVisualParsesValidYAML() throws {
    let sut = try makeSUT()
    sut.yamlText = Self.validYAML
    sut.editorMode = .yaml

    let success = sut.switchToVisualMode()

    #expect(success)
    #expect(sut.editorMode == .visual)
    #expect(sut.scenarioName == "Editor Test")
    #expect(sut.personas.count == 2)
  }

  @Test func switchToVisualBlocksOnInvalidYAML() throws {
    let sut = try makeSUT()
    sut.yamlText = "invalid: yaml: {{"
    sut.editorMode = .yaml

    let success = sut.switchToVisualMode()

    #expect(!success)
    #expect(sut.editorMode == .yaml)
    #expect(!sut.validationErrors.isEmpty)
  }

  @Test func switchToVisualBlocksOnEmptyYAML() throws {
    let sut = try makeSUT()
    sut.yamlText = ""
    sut.editorMode = .yaml

    let success = sut.switchToVisualMode()

    #expect(!success)
    #expect(sut.editorMode == .yaml)
  }

  // MARK: - Validation

  @Test func validateDetectsEmptyName() throws {
    let sut = try makeSUT()
    sut.scenarioId = "test"
    sut.scenarioName = ""
    sut.scenarioDescription = "Desc"
    sut.agentCount = 2
    sut.rounds = 1
    sut.context = "Context"
    sut.personas = [
      EditablePersona(name: "A", description: "A"),
      EditablePersona(name: "B", description: "B")
    ]
    sut.phases = [EditablePhase(type: .speakAll)]

    sut.validate()

    #expect(!sut.isValid)
  }

  @Test func validateAcceptsCompleteScenario() throws {
    let sut = try makeSUT()
    sut.loadFromTemplate(yaml: Self.validYAML)

    sut.validate()

    #expect(sut.isValid)
    #expect(sut.validationErrors.isEmpty)
  }

  // MARK: - Save

  @Test func savePersistsToRepository() async throws {
    let (sut, repo) = try makeSUTWithRepo()
    sut.loadFromTemplate(yaml: Self.validYAML)
    sut.validate()

    let success = await sut.save()

    #expect(success)
    #expect(sut.savedScenarioId != nil)

    let record = try repo.fetchById(sut.savedScenarioId!)
    #expect(record != nil)
    #expect(record?.isPreset == false)
  }

  @Test func saveRejectsOverwritingPreset() async throws {
    let (sut, repo) = try makeSUTWithRepo()

    // Pre-save a preset with the ID
    try repo.save(
      ScenarioRecord(
        id: "some_preset", name: "Preset", yamlDefinition: "",
        isPreset: true, createdAt: Date(), updatedAt: Date()
      ))

    sut.scenarioId = "some_preset"
    sut.scenarioName = "Override Attempt"
    sut.scenarioDescription = "Desc"
    sut.agentCount = 2
    sut.rounds = 1
    sut.context = "Context"
    sut.personas = [
      EditablePersona(name: "A", description: "A"),
      EditablePersona(name: "B", description: "B")
    ]
    sut.phases = [
      EditablePhase(type: .speakAll, prompt: "Go", outputFields: ["statement": "string"])
    ]
    sut.validate()

    let success = await sut.save()

    #expect(!success)
    #expect(!sut.validationErrors.isEmpty)
  }

  // MARK: - Loading for Edit

  @Test func loadExistingScenarioPopulatesFields() async throws {
    let (sut, repo) = try makeSUTWithRepo()

    try repo.save(
      ScenarioRecord(
        id: "existing_test", name: "Existing", yamlDefinition: Self.validYAML,
        isPreset: false, createdAt: Date(), updatedAt: Date()
      ))

    await sut.loadForEditing(scenarioId: "existing_test")

    #expect(sut.scenarioId == "editor_test")  // ID from YAML content
    #expect(sut.scenarioName == "Editor Test")
    #expect(sut.personas.count == 2)
  }

  // MARK: - Helpers

  private func makeSUT() throws -> ScenarioEditorViewModel {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    return ScenarioEditorViewModel(repository: repo)
  }

  private func makeSUTWithRepo() throws -> (ScenarioEditorViewModel, GRDBScenarioRepository) {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    return (ScenarioEditorViewModel(repository: repo), repo)
  }
}
