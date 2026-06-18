#if DEBUG

  import Foundation
  import Testing

  @testable import Pastura

  /// Unit tests for ``StubScenarioSeeder`` fixtures.
  ///
  /// Validates that `editorSeedYAML` and `homeSeedYAML` remain well-formed
  /// across refactors. Running in-process (~100 ms) catches YAML indentation
  /// drift or validator regressions long before the slow UI-test target would.
  @Suite(.timeLimit(.minutes(1)))
  @MainActor
  struct StubScenarioSeederTests {

    // MARK: - editor seed YAML

    /// `editorSeedYAML` must load cleanly and save successfully through the
    /// full `ScenarioEditorViewModel` pipeline — the same path the UI test
    /// exercises end-to-end. Guards against fixture drift silently breaking the
    /// UI test.
    @Test func testEditorSeedYAMLRoundTripsThroughLoadFromTemplateThenSave() async throws {
      let db = try DatabaseManager.inMemory()
      let repository = GRDBScenarioRepository(dbWriter: db.dbWriter)
      let viewModel = ScenarioEditorViewModel(repository: repository)

      viewModel.loadFromTemplate(yaml: StubScenarioSeeder.editorSeedYAML)

      #expect(
        viewModel.validationErrors.isEmpty,
        "validationErrors after loadFromTemplate: \(viewModel.validationErrors)")

      let didSave = await viewModel.save()
      #expect(didSave, "save() returned false; errors: \(viewModel.validationErrors)")

      let savedId = try #require(
        viewModel.savedScenarioId, "savedScenarioId should be non-nil after a successful save")

      let record = try repository.fetchById(savedId)
      let unwrapped = try #require(record, "fetchById(\(savedId)) returned nil")
      #expect(unwrapped.name == StubScenarioSeeder.editorSeedScenarioName)

      #expect(
        viewModel.validationErrors.isEmpty,
        "validationErrors after save: \(viewModel.validationErrors)")
    }

    // MARK: - home seed YAML

    /// `homeSeedYAML` must be parseable and valid — mirrors what
    /// `StubScenarioSeeder.seed(into:)` inserts, so the home-list row would
    /// survive an editor round-trip if it ever needed to.
    @Test func testHomeSeedYAMLParsesAndPassesValidation() throws {
      let scenario = try ScenarioLoader().load(yaml: StubScenarioSeeder.homeSeedYAML)

      _ = try ScenarioValidator().validate(scenario)

      let contentFindings = ScenarioContentValidator().validate(scenario)
      #expect(contentFindings.isEmpty, "Content validation findings: \(contentFindings)")
    }

    // MARK: - repository persistence

    /// `seed(into:)` must persist the home-list row with the expected id and
    /// name so UI tests can address the cell by stable accessibility identifier.
    @Test func testSeededScenarioPersistsToRepository() async throws {
      let db = try DatabaseManager.inMemory()
      let repository = GRDBScenarioRepository(dbWriter: db.dbWriter)

      try await StubScenarioSeeder.seed(into: repository)

      let record = try repository.fetchById(StubScenarioSeeder.homeSeedScenarioId)
      let unwrapped = try #require(
        record,
        "fetchById(\(StubScenarioSeeder.homeSeedScenarioId)) returned nil after seed"
      )
      #expect(unwrapped.name == StubScenarioSeeder.homeSeedScenarioName)
      #expect(unwrapped.isPreset == false)
    }

    // MARK: - rich Home seed (--ui-test-seed-home-rich)

    /// Every rich-seed YAML must parse, validate, and pass content validation —
    /// same gate as `homeSeedYAML`, so fixture drift breaks here instead of in
    /// the slow UI-test tour.
    @Test func testRichHomeSeedYAMLsParseAndPassValidation() throws {
      let loader = ScenarioLoader()
      let validator = ScenarioValidator()
      let contentValidator = ScenarioContentValidator()
      for yaml in [
        StubScenarioSeeder.richDilemmaYAML,
        StubScenarioSeeder.richDesertYAML,
        StubScenarioSeeder.richWordWolfYAML
      ] {
        let scenario = try loader.load(yaml: yaml)
        _ = try validator.validate(scenario)
        let findings = contentValidator.validate(scenario)
        #expect(findings.isEmpty, "Content findings for \(scenario.id): \(findings)")
      }
    }

    /// `seedRichHome(into:)` persists the preset rows (with `isPreset`) and the
    /// gallery-sourced user row (with `sourceType`), and the Word Wolf scenario
    /// keeps `rounds == richWordWolfRounds` (≥ 2) — the invariant the paused-run
    /// resume card depends on for a visible progress line.
    @Test func testSeedRichHomePersistsPresetAndGalleryRows() async throws {
      let db = try DatabaseManager.inMemory()
      let repository = GRDBScenarioRepository(dbWriter: db.dbWriter)

      try await StubScenarioSeeder.seedRichHome(into: repository)

      let dilemma = try #require(try repository.fetchById("ui_test_preset_dilemma"))
      #expect(dilemma.isPreset == true)

      let wordWolf = try #require(
        try repository.fetchById(StubScenarioSeeder.richWordWolfScenarioId))
      #expect(wordWolf.isPreset == false)
      #expect(wordWolf.sourceType == ScenarioSourceType.gallery)

      let scenario = try ScenarioLoader().load(yaml: wordWolf.yamlDefinition)
      #expect(scenario.rounds == StubScenarioSeeder.richWordWolfRounds)
      #expect(scenario.rounds >= 2)
    }
  }

#endif
