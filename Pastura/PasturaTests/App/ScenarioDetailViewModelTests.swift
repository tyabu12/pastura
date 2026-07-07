import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
@MainActor
// swiftlint:disable:next type_body_length
struct ScenarioDetailViewModelTests {
  private static let validYAML = """
    id: test_scenario
    language: ja
    name: Test
    description: A test scenario
    agents: 2
    rounds: 1
    context: Test context
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

  @Test func loadParsesYAMLAndValidates() async throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)

    try repo.save(
      ScenarioRecord(
        id: "test_scenario", name: "Test", yamlDefinition: Self.validYAML,
        isPreset: false, createdAt: Date(), updatedAt: Date()
      ))

    let viewModel = ScenarioDetailViewModel(repository: repo)
    await viewModel.load(scenarioId: "test_scenario")

    #expect(viewModel.scenario != nil)
    #expect(viewModel.scenario?.name == "Test")
    #expect(viewModel.scenario?.agentCount == 2)
    #expect(viewModel.estimatedInferences == 2)  // 2 agents * 1 round * 1 speak_all
    #expect(viewModel.validationError == nil)
    #expect(viewModel.canRun == true)
    #expect(viewModel.errorMessage == nil)
  }

  @Test func loadHandlesMissingScenario() async throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)

    let viewModel = ScenarioDetailViewModel(repository: repo)
    await viewModel.load(scenarioId: "nonexistent")

    #expect(viewModel.scenario == nil)
    // Use partial match (`.contains`) — `errorMessage` is wrapped in
    // `String(localized:)`, so equality would flip under non-en locales
    // once `ja` translations land in Item 7. Mirror the
    // `LocalizedError`-tests convention from CLAUDE.md "Error message i18n
    // prep" preemptively (axis 3 of the A-1 plan critic review).
    #expect(viewModel.errorMessage?.contains("Scenario not found") == true)
  }

  @Test func loadDetectsValidationErrors() async throws {
    // Too many agents (>10) will trigger validation error
    let badYAML = """
      id: bad
      language: ja
      name: Bad
      description: Too many agents
      agents: 11
      rounds: 1
      context: Context
      personas:
        - name: A1
          description: d
        - name: A2
          description: d
        - name: A3
          description: d
        - name: A4
          description: d
        - name: A5
          description: d
        - name: A6
          description: d
        - name: A7
          description: d
        - name: A8
          description: d
        - name: A9
          description: d
        - name: A10
          description: d
        - name: A11
          description: d
      phases:
        - type: speak_all
          prompt: "hi"
          output:
            statement: string
      """

    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    try repo.save(
      ScenarioRecord(
        id: "bad", name: "Bad", yamlDefinition: badYAML,
        isPreset: false, createdAt: Date(), updatedAt: Date()
      ))

    let viewModel = ScenarioDetailViewModel(repository: repo)
    await viewModel.load(scenarioId: "bad")

    #expect(viewModel.scenario != nil)
    #expect(viewModel.validationError != nil)
    #expect(viewModel.canRun == false)
  }

  /// A scenario tripping a lint error rule (`eliminate` with no `vote`, R1a)
  /// gates `canRun` via `validationError`, same surface as a structural
  /// validation error (ADR-022 D5).
  @Test func loadDetectsSemanticLintErrors() async throws {
    let lintErrorYAML = """
      id: lint_error
      language: ja
      name: Lint Error
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

    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    try repo.save(
      ScenarioRecord(
        id: "lint_error", name: "Lint Error", yamlDefinition: lintErrorYAML,
        isPreset: false, createdAt: Date(), updatedAt: Date()
      ))

    let viewModel = ScenarioDetailViewModel(repository: repo)
    await viewModel.load(scenarioId: "lint_error")

    #expect(viewModel.scenario != nil)
    #expect(viewModel.validationError != nil)
    #expect(viewModel.canRun == false)
  }

  @Test func deleteScenarioReturnsTrue() async throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    try repo.save(
      ScenarioRecord(
        id: "del", name: "Del", yamlDefinition: Self.validYAML,
        isPreset: false, createdAt: Date(), updatedAt: Date()
      ))

    let viewModel = ScenarioDetailViewModel(repository: repo)
    await viewModel.load(scenarioId: "del")
    let deleted = await viewModel.deleteScenario()

    #expect(deleted == true)
    #expect(try repo.fetchById("del") == nil)
  }

  // MARK: - ADR-010 D6 cross-language sibling (Step D)

  /// Minimal valid YAML for an EN sibling — same shape as `validYAML`
  /// but `language: en`. Phase 1 baseline (no cross-language sibling)
  /// uses `validYAML` alone; the sibling tests pair the two.
  private static let validYAMLEn = """
    id: test_scenario_en
    language: en
    name: Test
    description: A test scenario
    agents: 2
    rounds: 1
    context: Test context
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

  /// JA scenario with EN sibling in the same repository — sibling
  /// resolver returns the EN record.
  @Test func loadSiblingFindsEnSiblingForJaScenario() async throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)

    try repo.save(
      ScenarioRecord(
        id: "test_scenario", name: "Test", yamlDefinition: Self.validYAML,
        isPreset: true, createdAt: Date(), updatedAt: Date(),
        sourceType: nil, sourceId: "test_scenario", sourceHash: nil))
    try repo.save(
      ScenarioRecord(
        id: "test_scenario_en", name: "Test", yamlDefinition: Self.validYAMLEn,
        isPreset: true, createdAt: Date(), updatedAt: Date(),
        sourceType: nil, sourceId: "test_scenario", sourceHash: nil))

    let viewModel = ScenarioDetailViewModel(repository: repo)
    await viewModel.load(scenarioId: "test_scenario")
    await viewModel.loadSibling()

    #expect(viewModel.siblingVariant?.id == "test_scenario_en")
  }

  /// EN scenario with JA sibling — symmetric to the above. The
  /// resolver picks any different-id record sharing the canonical
  /// `sourceId`, regardless of which side initiated.
  @Test func loadSiblingFindsJaSiblingForEnScenario() async throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)

    try repo.save(
      ScenarioRecord(
        id: "test_scenario", name: "Test", yamlDefinition: Self.validYAML,
        isPreset: true, createdAt: Date(), updatedAt: Date(),
        sourceType: nil, sourceId: "test_scenario", sourceHash: nil))
    try repo.save(
      ScenarioRecord(
        id: "test_scenario_en", name: "Test", yamlDefinition: Self.validYAMLEn,
        isPreset: true, createdAt: Date(), updatedAt: Date(),
        sourceType: nil, sourceId: "test_scenario", sourceHash: nil))

    let viewModel = ScenarioDetailViewModel(repository: repo)
    await viewModel.load(scenarioId: "test_scenario_en")
    await viewModel.loadSibling()

    #expect(viewModel.siblingVariant?.id == "test_scenario")
  }

  /// Solo scenario without a sibling — resolver returns nil and the
  /// View hides the affordance.
  @Test func loadSiblingReturnsNilWhenNoSibling() async throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    try repo.save(
      ScenarioRecord(
        id: "test_scenario", name: "Test", yamlDefinition: Self.validYAML,
        isPreset: true, createdAt: Date(), updatedAt: Date(),
        sourceType: nil, sourceId: "test_scenario", sourceHash: nil))

    let viewModel = ScenarioDetailViewModel(repository: repo)
    await viewModel.load(scenarioId: "test_scenario")
    await viewModel.loadSibling()

    #expect(viewModel.siblingVariant == nil)
  }

  /// Legacy pre-Step-D row with `sourceId == nil` — sibling resolution
  /// short-circuits (no canonical key to group by). Phase 1 / D11
  /// install-base reset territory.
  @Test func loadSiblingReturnsNilWhenSourceIdIsNil() async throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    try repo.save(
      ScenarioRecord(
        id: "test_scenario", name: "Test", yamlDefinition: Self.validYAML,
        isPreset: true, createdAt: Date(), updatedAt: Date(),
        sourceType: nil, sourceId: nil, sourceHash: nil))
    // Another record with sourceId == nil — even though both have nil,
    // the resolver still short-circuits when the current record has
    // none (no canonical key to match against).
    try repo.save(
      ScenarioRecord(
        id: "other", name: "Other", yamlDefinition: Self.validYAML,
        isPreset: true, createdAt: Date(), updatedAt: Date(),
        sourceType: nil, sourceId: nil, sourceHash: nil))

    let viewModel = ScenarioDetailViewModel(repository: repo)
    await viewModel.load(scenarioId: "test_scenario")
    await viewModel.loadSibling()

    #expect(viewModel.siblingVariant == nil)
  }

  /// Two siblings share the canonical `sourceId` — the resolver returns
  /// the **newest** (`createdAt DESC`). Pins the newest-wins tie-break
  /// preserved by the `fetchAllSummaries()` + `fetchById()` lookup
  /// (#704), so a future refactor that drops the ordering or resolves
  /// the wrong sibling fails here.
  @Test func loadSiblingResolvesNewestAmongMultipleSiblings() async throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)

    try repo.save(
      ScenarioRecord(
        id: "test_scenario", name: "Test", yamlDefinition: Self.validYAML,
        isPreset: true, createdAt: Date(timeIntervalSince1970: 2000),
        updatedAt: Date(timeIntervalSince1970: 2000),
        sourceType: nil, sourceId: "test_scenario", sourceHash: nil))
    // Older sibling — must lose to the newer one below.
    try repo.save(
      ScenarioRecord(
        id: "test_scenario_old", name: "Test", yamlDefinition: Self.validYAMLEn,
        isPreset: true, createdAt: Date(timeIntervalSince1970: 1000),
        updatedAt: Date(timeIntervalSince1970: 1000),
        sourceType: nil, sourceId: "test_scenario", sourceHash: nil))
    // Newest sibling — the resolver should pick this one.
    try repo.save(
      ScenarioRecord(
        id: "test_scenario_new", name: "Test", yamlDefinition: Self.validYAMLEn,
        isPreset: true, createdAt: Date(timeIntervalSince1970: 3000),
        updatedAt: Date(timeIntervalSince1970: 3000),
        sourceType: nil, sourceId: "test_scenario", sourceHash: nil))

    let viewModel = ScenarioDetailViewModel(repository: repo)
    await viewModel.load(scenarioId: "test_scenario")
    await viewModel.loadSibling()

    #expect(viewModel.siblingVariant?.id == "test_scenario_new")
  }
}
