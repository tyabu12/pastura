// swiftlint:disable file_length
import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
@MainActor
// swiftlint:disable:next type_body_length
struct ScenarioEditorViewModelTests {
  // Internal (not `private`) so sibling-file extensions can reuse.
  // See `.claude/rules/testing.md` § "Splitting a Suite Across Files".
  static let validYAML = """
    id: editor_test
    language: ja
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

  // MARK: - Semantic Lint (ADR-024)

  /// A lint error rule (`eliminate` with no `vote`, R1a) blocks validation —
  /// its message joins the blocking `validationErrors` array (ADR-024 D5).
  @Test func validateBlocksOnSemanticLintError() throws {
    let sut = try makeSUT()
    sut.yamlText = """
      id: lint_error_editor
      language: ja
      name: Lint Error Editor
      description: eliminate without a vote phase
      agents: 2
      rounds: 1
      context: Context
      personas:
        - name: Alice
          description: Agent A
        - name: Bob
          description: Agent B
      phases:
        - type: eliminate
      """
    sut.editorMode = .yaml

    sut.validate()

    #expect(!sut.isValid)
    #expect(!sut.validationErrors.isEmpty)
  }

  /// A warning-only lint finding (`choose` without `options`, R7) must NOT
  /// block: it surfaces non-blocking in `lintWarnings` (ADR-024 PR2), so the
  /// scenario stays valid and `validationErrors` stays empty.
  @Test func validateAllowsSemanticLintWarningOnly() throws {
    let sut = try makeSUT()
    sut.yamlText = """
      id: lint_warn_editor
      language: ja
      name: Lint Warn Editor
      description: choose without options is a warning, not blocking
      agents: 2
      rounds: 1
      context: Context
      personas:
        - name: Alice
          description: Agent A
        - name: Bob
          description: Agent B
      phases:
        - type: choose
          prompt: "Pick"
          output:
            action: string
      """
    sut.editorMode = .yaml

    sut.validate()

    #expect(sut.isValid)
    #expect(sut.validationErrors.isEmpty)
    // ADR-024 PR2: the warning is now surfaced non-blocking in lintWarnings.
    #expect(sut.lintWarnings.contains { $0.ruleID == "choose-should-declare-options" })
    #expect(sut.lintWarnings.allSatisfy { $0.severity != .error })
  }

  /// Regression (ADR-024 PR2, plan critic Axis 4): a warning that populated
  /// `lintWarnings` on one clean validate must not survive into a later
  /// early-return validate. Here the second validate flips to visual mode with
  /// empty fields, so it returns at the "name is required" pre-check *before*
  /// the linter runs — the reset must live at the top of `validate()`, not only
  /// at its success point. Reverting that top-of-`validate()` reset fails this.
  @Test func validateClearsStaleWarningsOnEarlyReturn() throws {
    let sut = try makeSUT()
    sut.yamlText = """
      id: lint_warn_editor
      language: ja
      name: Lint Warn Editor
      description: choose without options is a warning
      agents: 2
      rounds: 1
      context: Context
      personas:
        - name: Alice
          description: Agent A
        - name: Bob
          description: Agent B
      phases:
        - type: choose
          prompt: "Pick"
          output:
            action: string
      """
    sut.editorMode = .yaml
    sut.validate()
    #expect(!sut.lintWarnings.isEmpty)  // precondition: warning surfaced

    // Flip to visual mode; the visual fields were never populated, so
    // validate() early-returns at the empty-name pre-check before the linter.
    sut.editorMode = .visual
    sut.validate()

    #expect(!sut.validationErrors.isEmpty)  // blocked on the empty-name error
    #expect(sut.lintWarnings.isEmpty)  // the stale warning was cleared
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

  /// Issue #336: paste valid YAML in YAML mode and save without toggling Visual.
  /// Pre-fix, `save()` called `buildScenario()` regardless of mode → empty visual
  /// fields → `runCommitTimeValidation` surfaced the misleading
  /// "Agent count (0) is below minimum of 2" error even though the pasted YAML
  /// declared `agents: 2`.
  @Test func yamlModeSavePersistsWithoutToggle() async throws {
    let (sut, repo) = try makeSUTWithRepo()
    sut.yamlText = Self.validYAML
    sut.editorMode = .yaml

    let success = await sut.save()

    #expect(success)
    #expect(sut.savedScenarioId == "editor_test")
    #expect(sut.validationErrors.isEmpty)
    let record = try repo.fetchById("editor_test")
    #expect(record?.name == "Editor Test")
    let reloaded = try ScenarioLoader().load(yaml: record?.yamlDefinition ?? "")
    #expect(reloaded.agentCount == 2)
    #expect(reloaded.personas.count == 2)
  }

  /// YAML-mode save persists the user's exact text. The canonical serializer
  /// (used in visual-mode save) strips comments and normalizes key order, so
  /// pasting an authored YAML and saving must NOT round-trip through it.
  @Test func yamlModeSavePreservesUserText() async throws {
    let (sut, repo) = try makeSUTWithRepo()
    let yamlWithComment = """
      # custom comment from author
      id: comment_preservation_test
      language: ja
      name: Comment Preservation Test
      description: Tests comment survival on save
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
    sut.yamlText = yamlWithComment
    sut.editorMode = .yaml

    let success = await sut.save()

    #expect(success)
    let record = try repo.fetchById("comment_preservation_test")
    let saved = record?.yamlDefinition ?? ""
    // Canonical serializer would strip this comment line.
    #expect(saved.contains("# custom comment from author"))
  }

  /// Regression for #336's underlying drift class. extraData (e.g. bokete `topics`)
  /// must survive a YAML-mode-direct save (no Visual toggle). Pre-fix, save() went
  /// through `buildScenario()` → empty visual state, so this would fail with the
  /// agentCount=0 error before extraData ever entered the picture. Post-fix, this
  /// test guards against a future "simplify by routing both modes through
  /// buildScenario()" refactor that would silently re-introduce the bug.
  @Test func yamlModeSavePreservesExtraData() async throws {
    let (sut, repo) = try makeSUTWithRepo()
    let boketeYAML = """
      id: bokete_yaml_save_test
      language: ja
      name: Bokete Save Test
      description: Tests extraData survival on YAML-mode save
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
          target: all
      """
    sut.yamlText = boketeYAML
    sut.editorMode = .yaml

    let success = await sut.save()

    #expect(success)
    let record = try repo.fetchById("bokete_yaml_save_test")
    let reloaded = try ScenarioLoader().load(yaml: record?.yamlDefinition ?? "")
    #expect(reloaded.extraData["topics"] == .array(["Photo A", "Photo B", "Photo C"]))
  }

  /// Visual-mode equivalent of `yamlModeSavePreservesExtraData` above. Save in
  /// `.visual` mode routes through `currentScenario()` → `buildScenario()`, which
  /// reads `carriedExtraData` to pass through fields the visual editor has no UI
  /// for. Reverting the funnel to bypass `buildScenario()` — or removing
  /// `carriedExtraData` — would silently drop extraData on every visual-mode save.
  /// Tripwire for the funnel invariant; see `.claude/rules/scenario-editor.md`.
  @Test func visualModeSavePreservesExtraData() async throws {
    let (sut, repo) = try makeSUTWithRepo()
    let boketeYAML = """
      id: bokete_visual_save_test
      language: ja
      name: Bokete Visual Save Test
      description: Tests extraData survival on visual-mode save via carriedExtraData
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
          target: all
      """
    sut.loadFromTemplate(yaml: boketeYAML)
    // editorMode is .visual by default; populateFromScenario captures `topics`
    // into carriedExtraData. No mode switch — save() must go through the
    // .visual branch of currentScenario() → buildScenario().
    #expect(sut.editorMode == .visual)

    let success = await sut.save()

    #expect(success)
    // loadFromTemplate generates a new UUID-based id; resolve via savedScenarioId.
    let savedId = try #require(sut.savedScenarioId)
    let record = try repo.fetchById(savedId)
    let reloaded = try ScenarioLoader().load(yaml: record?.yamlDefinition ?? "")
    #expect(reloaded.extraData["topics"] == .array(["Photo A", "Photo B", "Photo C"]))
  }

  /// A `log_window` set in YAML has no Visual UI, so `editorLogWindow` must be
  /// carried through `buildScenario()` on a visual-mode save — same pattern as
  /// `carriedExtraData` / `editorSimulationLanguage` (#907).
  @Test func visualModeSavePreservesLogWindow() async throws {
    let (sut, repo) = try makeSUTWithRepo()
    let yaml = """
      id: lw_visual_save_test
      language: ja
      name: LW Visual Save Test
      description: Tests log_window survival on visual-mode save
      agents: 2
      rounds: 1
      log_window: 5
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
    sut.loadFromTemplate(yaml: yaml)
    #expect(sut.editorMode == .visual)
    #expect(sut.editorLogWindow == 5)

    let success = await sut.save()

    #expect(success)
    let savedId = try #require(sut.savedScenarioId)
    let record = try repo.fetchById(savedId)
    let reloaded = try ScenarioLoader().load(yaml: record?.yamlDefinition ?? "")
    #expect(reloaded.logWindow == 5)
  }

  @Test func saveSurfacesSourceNotFoundValidationMessage() async throws {
    let sut = try makeSUT()
    // YAML with an `assign` phase referencing a non-existent `topics` source.
    // Mirrors the real-world reproduction from issue #138: user removes
    // `topics:` from bokete.yaml and hits Save.
    let yamlMissingTopics = """
      id: missing_topics_test
      language: ja
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
      language: ja
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
      language: ja
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
      language: ja
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
      language: ja
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
      language: ja
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

  // MARK: - Content Validation

  @Test func validateRejectsBlockedPersonaDescriptionInVisualMode() throws {
    let sut = try makeSUT()
    sut.scenarioId = "content_test"
    sut.scenarioName = "Content Test"
    sut.scenarioDescription = "A test"
    sut.agentCount = 2
    sut.rounds = 1
    sut.context = "Context"
    // Uses the default bundled blocklist — "死ね" is in the harassment partition,
    // which is included in ContentBlocklist.inputPatterns. (ADR-005 §10.1 excludes
    // the violence category from input, so 殺す/殺害/殺人 wouldn't trigger this.)
    sut.personas = [
      EditablePersona(name: "Alice", description: "死ね"),
      EditablePersona(name: "Bob", description: "Agent B")
    ]
    sut.phases = [
      EditablePhase(type: .speakAll, prompt: "Go", outputFields: ["statement": "string"])
    ]

    sut.validate()

    #expect(sut.isValid == false)
    #expect(!sut.validationErrors.isEmpty)
    #expect(sut.validationErrors.contains { $0.contains("Alice") && $0.contains("description") })
  }

  @Test func validateRejectsBlockedPersonaDescriptionInYAMLMode() throws {
    let sut = try makeSUT()
    sut.yamlText = """
      id: content_yaml_test
      language: ja
      name: Content YAML Test
      description: A test
      agents: 2
      rounds: 1
      context: Context
      personas:
        - name: Alice
          description: 死ね
        - name: Bob
          description: Agent B
      phases:
        - type: speak_all
          prompt: "Say something"
          output:
            statement: string
      """
    sut.editorMode = .yaml

    sut.validate()

    #expect(sut.isValid == false)
    #expect(!sut.validationErrors.isEmpty)
    #expect(sut.validationErrors.contains { $0.contains("Alice") && $0.contains("description") })
  }

  // MARK: - Helpers

  // Internal (not `private`) so sibling-file extensions can reuse.
  // See `.claude/rules/testing.md` § "Splitting a Suite Across Files".
  func makeSUT() throws -> ScenarioEditorViewModel {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    return ScenarioEditorViewModel(repository: repo)
  }

  func makeSUTWithRepo() throws -> (ScenarioEditorViewModel, GRDBScenarioRepository) {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    return (ScenarioEditorViewModel(repository: repo), repo)
  }
}
