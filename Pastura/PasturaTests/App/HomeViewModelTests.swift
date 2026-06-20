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
  // Preset fixture helpers (`makePreset` / `makePresetRecord`) live in the
  // sibling `HomeViewModelTests+Fixtures.swift` extension (type_body_length).

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

  /// A `nil` language column (pre-v8 / failed-backfill row) falls back to
  /// `"ja"` rather than the row disappearing — Phase 1 convention, preserving
  /// the prior ``ScenarioYAMLLanguage`` behavior after the #679 column switch.
  @Test func presetsResolvedForLanguageNilLanguageFallsBackToJa() {
    let bad = makePreset(id: "broken", language: nil, sourceId: "broken")
    // On a ja device the nil-language row is picked (nil → "ja" match).
    let jaResolved = HomeViewModel.presetsResolvedForLanguage([bad], deviceLanguage: "ja")
    #expect(jaResolved.count == 1)
    #expect(jaResolved.first?.id == "broken")
    // On an en device it still surfaces via the "any available variant" fallback.
    let enResolved = HomeViewModel.presetsResolvedForLanguage([bad], deviceLanguage: "en")
    #expect(enResolved.count == 1)
    #expect(enResolved.first?.id == "broken")
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
    try repo.save(makePresetRecord(id: "word_wolf", language: "ja", sourceId: "word_wolf"))
    try repo.save(makePresetRecord(id: "word_wolf_en", language: "en", sourceId: "word_wolf"))

    let viewModel = HomeViewModel(repository: repo)
    await viewModel.loadScenarios()

    let displayedIds = Set(viewModel.presets.map(\.id) + viewModel.userScenarios.map(\.id))
    #expect(Set(viewModel.rowMetadata.keys).isSubset(of: displayedIds))
    #expect(viewModel.presets.count == 1)
  }

  // MARK: - Observation count (completed runs, cross-variant aggregated)

  private func completedRun(id: String, scenarioId: String) -> SimulationRecord {
    SimulationRecord(
      id: id, scenarioId: scenarioId,
      status: SimulationStatus.completed.rawValue,
      currentRound: 0, currentPhaseIndex: 0,
      stateJSON: "{}", configJSON: nil,
      createdAt: Date(), updatedAt: Date())
  }

  /// Completed runs against *different* language variants of one canonical
  /// scenario aggregate onto the single displayed row (ADR-010 D4 intent):
  /// 2 runs on the JA variant + 1 on the EN variant → 3 on the displayed row.
  /// A `.paused` run does not count.
  @Test func observationCountsAggregateCompletedRunsAcrossVariants() async throws {
    let db = try DatabaseManager.inMemory()
    let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
    try scenarioRepo.save(makePresetRecord(id: "word_wolf", language: "ja", sourceId: "word_wolf"))
    try scenarioRepo.save(
      makePresetRecord(id: "word_wolf_en", language: "en", sourceId: "word_wolf"))

    try simRepo.save(completedRun(id: "r1", scenarioId: "word_wolf"))
    try simRepo.save(completedRun(id: "r2", scenarioId: "word_wolf"))
    try simRepo.save(completedRun(id: "r3", scenarioId: "word_wolf_en"))
    // A paused run on the same scenario must be excluded.
    try simRepo.save(
      SimulationRecord(
        id: "p1", scenarioId: "word_wolf",
        status: SimulationStatus.paused.rawValue,
        currentRound: 0, currentPhaseIndex: 0,
        stateJSON: "{}", configJSON: nil,
        createdAt: Date(), updatedAt: Date()))

    let viewModel = HomeViewModel(repository: scenarioRepo, simulationRepository: simRepo)
    await viewModel.loadScenarios()

    let displayed = try #require(viewModel.presets.first)
    #expect(viewModel.presets.count == 1)
    #expect(viewModel.observationCounts[displayed.id] == 3)
  }

  /// A displayed row with no completed runs reports an explicit 0 (so the
  /// View can read the dictionary uniformly).
  @Test func observationCountsReportZeroForRowWithNoRuns() async throws {
    let db = try DatabaseManager.inMemory()
    let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
    try scenarioRepo.save(
      ScenarioRecord(
        id: "lonely", name: "Lonely", yamlDefinition: "",
        isPreset: false, createdAt: Date(), updatedAt: Date()))

    let viewModel = HomeViewModel(repository: scenarioRepo, simulationRepository: simRepo)
    await viewModel.loadScenarios()

    #expect(viewModel.observationCounts["lonely"] == 0)
  }

  /// Without an injected `SimulationRepository`, observation counts stay empty
  /// rather than failing the load (back-compat for fixture tests).
  @Test func observationCountsEmptyWithoutSimulationRepository() async throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    try repo.save(
      ScenarioRecord(
        id: "u1", name: "U1", yamlDefinition: "",
        isPreset: false, createdAt: Date(), updatedAt: Date()))

    let viewModel = HomeViewModel(repository: repo)
    await viewModel.loadScenarios()

    #expect(viewModel.observationCounts.isEmpty)
    #expect(viewModel.errorMessage == nil)
  }

  /// Pure-function check of the aggregation: per-variant counts roll up to the
  /// canonical key and project onto the displayed row.
  @Test func aggregateObservationCountsSumsByCanonicalKey() {
    let ja = makePreset(id: "ww_ja", language: "ja", sourceId: "ww")
    let en = makePreset(id: "ww_en", language: "en", sourceId: "ww")
    let solo = ScenarioSummary(
      id: "solo", name: "Solo", isPreset: false, sourceId: nil, language: "ja")

    let result = HomeViewModel.aggregateObservationCounts(
      completedByScenarioId: ["ww_ja": 2, "ww_en": 1, "solo": 4, "ghost": 9],
      scenarios: [ja, en, solo],
      displayedRows: [ja, solo])

    // `ja` is the displayed variant; its count includes the EN sibling's run.
    #expect(result["ww_ja"] == 3)
    #expect(result["solo"] == 4)
    // `ghost` has no scenario record → contributes to nothing.
    #expect(result.count == 2)
  }
}
