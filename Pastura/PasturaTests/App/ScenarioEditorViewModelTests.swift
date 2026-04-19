// swiftlint:disable file_length
import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
@MainActor
// swiftlint:disable:next type_body_length
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

  @Test func saveSurfacesSourceNotFoundValidationMessage() async throws {
    let sut = try makeSUT()
    // YAML with an `assign` phase referencing a non-existent `topics` source.
    // Mirrors the real-world reproduction from issue #138: user removes
    // `topics:` from bokete.yaml and hits Save.
    let yamlMissingTopics = """
      id: missing_topics_test
      name: Missing Topics Test
      description: triggers validator's missing-source path
      agents: 2
      rounds: 1
      context: Context
      personas:
        - name: Alice
          description: Agent A
        - name: Bob
          description: Agent B
      phases:
        - type: assign
          source: topics
          target: all
        - type: speak_all
          prompt: "Say something"
          output:
            statement: string
      """
    sut.yamlText = yamlMissingTopics
    sut.editorMode = .yaml

    let saved = await sut.save()

    #expect(saved == false)
    let firstError = sut.validationErrors.first ?? ""
    #expect(firstError.contains("source 'topics' not found"))
    // Regression guard for #138: the cryptic NSError fallback must not appear.
    #expect(!firstError.contains("SimulationError error"))
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

  // MARK: - extraData Round-Trip

  /// Verifies that `.array` extraData (bokete-shaped `topics` list) survives a
  /// visual-edit round-trip via switchToYAMLMode → ScenarioLoader.
  @Test func loadFromTemplatePreservesArrayExtraData() throws {
    let yaml = """
      id: bokete_test
      name: Bokete Test
      description: Bokete-shaped scenario
      agents: 2
      rounds: 1
      context: Context
      topics:
        - Photo A
        - Photo B
        - Photo C
      personas:
        - name: Alice
          description: Agent A
        - name: Bob
          description: Agent B
      phases:
        - type: assign
          source: topics
          target: random_one
      """
    let sut = try makeSUT()
    sut.loadFromTemplate(yaml: yaml)

    sut.switchToYAMLMode()
    let reloaded = try ScenarioLoader().load(yaml: sut.yamlText)

    #expect(reloaded.extraData["topics"] == .array(["Photo A", "Photo B", "Photo C"]))
  }

  /// Verifies that `.arrayOfDictionaries` extraData (word_wolf-shaped `words` list) survives
  /// a visual-edit round-trip.
  @Test func loadFromTemplatePreservesArrayOfDictionariesExtraData() throws {
    let yaml = """
      id: word_wolf_test
      name: Word Wolf Test
      description: Word-wolf-shaped scenario
      agents: 2
      rounds: 1
      context: Context
      words:
        - majority: dog
          minority: cat
      personas:
        - name: Alice
          description: Agent A
        - name: Bob
          description: Agent B
      phases:
        - type: assign
          source: words
          target: random_one
      """
    let sut = try makeSUT()
    sut.loadFromTemplate(yaml: yaml)

    sut.switchToYAMLMode()
    let reloaded = try ScenarioLoader().load(yaml: sut.yamlText)

    #expect(
      reloaded.extraData["words"] == .arrayOfDictionaries([["majority": "dog", "minority": "cat"]])
    )
  }

  /// Verifies that a `.string` extraData value survives a visual-edit round-trip.
  @Test func loadFromTemplatePreservesStringExtraData() throws {
    let yaml = """
      id: string_extra_test
      name: String Extra Test
      description: Scenario with string extraData
      agents: 2
      rounds: 1
      context: Context
      topic: "Hello"
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
    let sut = try makeSUT()
    sut.loadFromTemplate(yaml: yaml)

    sut.switchToYAMLMode()
    let reloaded = try ScenarioLoader().load(yaml: sut.yamlText)

    #expect(reloaded.extraData["topic"] == .string("Hello"))
  }

  /// Verifies that a `.dictionary` extraData value survives a visual-edit round-trip.
  @Test func loadFromTemplatePreservesDictionaryExtraData() throws {
    let yaml = """
      id: dict_extra_test
      name: Dict Extra Test
      description: Scenario with dictionary extraData
      agents: 2
      rounds: 1
      context: Context
      config:
        key1: value1
        key2: value2
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
    let sut = try makeSUT()
    sut.loadFromTemplate(yaml: yaml)

    sut.switchToYAMLMode()
    let reloaded = try ScenarioLoader().load(yaml: sut.yamlText)

    #expect(reloaded.extraData["config"] == .dictionary(["key1": "value1", "key2": "value2"]))
  }

  /// Verifies that extraData survives the full visual→YAML→visual→YAML mode cycle.
  @Test func modeSwitchPreservesExtraData() throws {
    let yaml = """
      id: roundtrip_test
      name: Round-Trip Test
      description: Mode-switch round-trip
      agents: 2
      rounds: 1
      context: Context
      topics:
        - Alpha
        - Beta
      personas:
        - name: Alice
          description: Agent A
        - name: Bob
          description: Agent B
      phases:
        - type: assign
          source: topics
          target: random_one
      """
    let sut = try makeSUT()
    sut.loadFromTemplate(yaml: yaml)

    // visual → YAML → visual → YAML
    sut.switchToYAMLMode()
    let switched = sut.switchToVisualMode()
    #expect(switched)
    sut.switchToYAMLMode()

    let reloaded = try ScenarioLoader().load(yaml: sut.yamlText)
    #expect(reloaded.extraData["topics"] == .array(["Alpha", "Beta"]))
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
