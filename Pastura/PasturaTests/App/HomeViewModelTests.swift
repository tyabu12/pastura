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

  // MARK: - ADR-010 D6 variant collapsing

  /// Test fixture helper — bundled-preset row with parsed-from-YAML
  /// `language` field. Keeps the per-test YAML minimal so the
  /// language attribute is the only signal under test.
  private func makePreset(
    id: String, language: String, sourceId: String?
  ) -> ScenarioRecord {
    ScenarioRecord(
      id: id, name: id,
      yamlDefinition: "id: \(id)\nlanguage: \(language)\nname: \(id)\n",
      isPreset: true, createdAt: Date(), updatedAt: Date(),
      sourceType: nil, sourceId: sourceId, sourceHash: nil)
  }

  @Test func presetsResolvedForLanguageEmptyInputReturnsEmpty() {
    let resolved = HomeViewModel.presetsResolvedForLanguage([], deviceLanguage: "ja")
    #expect(resolved.isEmpty)
  }

  @Test func presetsResolvedForLanguageSingleVariantReturnsItself() {
    let presets = [makePreset(id: "word_wolf", language: "ja", sourceId: "word_wolf")]

    let jaResolved = HomeViewModel.presetsResolvedForLanguage(presets, deviceLanguage: "ja")
    #expect(jaResolved.count == 1)
    #expect(jaResolved.first?.id == "word_wolf")

    // EN device with only a JA variant available — D6 fallback to
    // "any available variant" still surfaces the row.
    let enResolved = HomeViewModel.presetsResolvedForLanguage(presets, deviceLanguage: "en")
    #expect(enResolved.count == 1)
    #expect(enResolved.first?.id == "word_wolf")
  }

  @Test func presetsResolvedForLanguagePicksDeviceLanguageVariant() {
    let presets = [
      makePreset(id: "word_wolf", language: "ja", sourceId: "word_wolf"),
      makePreset(id: "word_wolf_en", language: "en", sourceId: "word_wolf")
    ]

    let jaResolved = HomeViewModel.presetsResolvedForLanguage(presets, deviceLanguage: "ja")
    #expect(jaResolved.count == 1)
    #expect(jaResolved.first?.id == "word_wolf")

    let enResolved = HomeViewModel.presetsResolvedForLanguage(presets, deviceLanguage: "en")
    #expect(enResolved.count == 1)
    #expect(enResolved.first?.id == "word_wolf_en")
  }

  @Test func presetsResolvedForLanguageGroupsMultipleSourceIds() {
    let presets = [
      makePreset(id: "word_wolf", language: "ja", sourceId: "word_wolf"),
      makePreset(id: "word_wolf_en", language: "en", sourceId: "word_wolf"),
      makePreset(id: "bokete", language: "ja", sourceId: "bokete"),
      makePreset(id: "bokete_en", language: "en", sourceId: "bokete")
    ]

    let enResolved = HomeViewModel.presetsResolvedForLanguage(presets, deviceLanguage: "en")
    #expect(enResolved.count == 2)
    let enIds = Set(enResolved.map(\.id))
    #expect(enIds == ["word_wolf_en", "bokete_en"])

    let jaResolved = HomeViewModel.presetsResolvedForLanguage(presets, deviceLanguage: "ja")
    let jaIds = Set(jaResolved.map(\.id))
    #expect(jaIds == ["word_wolf", "bokete"])
  }

  /// Phase 1 / pre-Step-D bundled row with `sourceId == nil`. Groups
  /// by id (its own group), no cross-language sibling — keeps its
  /// visibility regardless of device language.
  @Test func presetsResolvedForLanguageLegacyNilSourceIdRowKeptVisible() {
    let presets = [
      makePreset(id: "word_wolf", language: "ja", sourceId: nil)
    ]
    let enResolved = HomeViewModel.presetsResolvedForLanguage(presets, deviceLanguage: "en")
    #expect(enResolved.count == 1)
    #expect(enResolved.first?.id == "word_wolf")
  }

  /// Malformed yamlDefinition falls back to `"ja"` rather than the row
  /// disappearing. Phase 1 convention applies — a row stays visible
  /// even if its YAML can't be re-parsed for the language field.
  @Test func presetsResolvedForLanguageMalformedYamlFallsBackToJa() {
    let bad = ScenarioRecord(
      id: "broken", name: "broken",
      yamlDefinition: "\t\tnot: [valid: yaml::",
      isPreset: true, createdAt: Date(), updatedAt: Date(),
      sourceType: nil, sourceId: "broken", sourceHash: nil)
    let resolved = HomeViewModel.presetsResolvedForLanguage([bad], deviceLanguage: "ja")
    #expect(resolved.count == 1)
    #expect(resolved.first?.id == "broken")
  }

  // MARK: - Row metadata (parse cache + name-only degradation)

  /// A complete, schema-valid scenario YAML. Used so the heavy
  /// `ScenarioLoader.load` path resolves agentCount / rounds / description.
  private static func validYAML(
    id: String, name: String, agents: Int = 2, rounds: Int = 3
  ) -> String {
    """
    id: \(id)
    language: ja
    name: \(name)
    description: A test scenario
    agents: \(agents)
    rounds: \(rounds)
    context: You are in a game.
    personas:
      - name: Alice
        description: A strategist
      - name: Bob
        description: An optimist
    phases:
      - type: speak_all
        prompt: "Speak your mind."
        output:
          statement: string
    """
  }

  @Test func rowMetadataExposesParsedMetaForValidYaml() async throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    try repo.save(
      ScenarioRecord(
        id: "valid", name: "Valid",
        yamlDefinition: Self.validYAML(id: "valid", name: "Valid", agents: 2, rounds: 5),
        isPreset: false, createdAt: Date(), updatedAt: Date()))

    let viewModel = HomeViewModel(repository: repo)
    await viewModel.loadScenarios()

    let meta = viewModel.rowMetadata["valid"]
    #expect(meta?.name == "Valid")
    #expect(meta?.agentCount == 2)
    #expect(meta?.rounds == 5)
    #expect(meta?.description == "A test scenario")
    #expect(viewModel.errorMessage == nil)
  }

  /// Name-only degradation contract. The YAML parses for the light
  /// `language` key (so the row survives D6 selection) but throws in the
  /// heavy `ScenarioLoader.load` (missing required `personas`). The row must
  /// stay visible with name-only metadata, and `errorMessage` must stay nil —
  /// the second assertion is the load-bearing regression guard.
  @Test func rowMetadataDegradesToNameOnlyForBrokenYamlWithoutSettingError() async throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    // Valid top-level `language`, but no `personas`/`agents` → load() throws.
    let brokenYAML = "id: broken\nlanguage: ja\nname: Broken\n"
    try repo.save(
      ScenarioRecord(
        id: "broken", name: "Broken", yamlDefinition: brokenYAML,
        isPreset: false, createdAt: Date(), updatedAt: Date()))

    let viewModel = HomeViewModel(repository: repo)
    await viewModel.loadScenarios()

    // Row stays visible.
    #expect(viewModel.userScenarios.contains { $0.id == "broken" })
    // Metadata degrades to name-only.
    let meta = viewModel.rowMetadata["broken"]
    #expect(meta?.name == "Broken")
    #expect(meta?.agentCount == nil)
    #expect(meta?.rounds == nil)
    #expect(meta?.description == nil)
    // One broken row never blanks the whole list.
    #expect(viewModel.errorMessage == nil)
  }

  /// D6 non-interference: metadata is resolved on the collapsed row set, so
  /// its keys are a subset of the displayed (preset + user) row ids — never
  /// the pre-collapse variant ids.
  @Test func rowMetadataKeysAreSubsetOfDisplayedRows() async throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    // Two variants of one canonical scenario — D6 collapses to one row.
    try repo.save(makePreset(id: "word_wolf", language: "ja", sourceId: "word_wolf"))
    try repo.save(makePreset(id: "word_wolf_en", language: "en", sourceId: "word_wolf"))

    let viewModel = HomeViewModel(repository: repo)
    await viewModel.loadScenarios()

    let displayedIds = Set(viewModel.presets.map(\.id) + viewModel.userScenarios.map(\.id))
    #expect(Set(viewModel.rowMetadata.keys).isSubset(of: displayedIds))
    #expect(viewModel.presets.count == 1)
  }
}
