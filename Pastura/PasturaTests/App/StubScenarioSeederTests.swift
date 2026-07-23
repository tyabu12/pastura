#if DEBUG

  import Foundation
  import Testing

  @testable import Pastura

  /// Unit tests for ``StubScenarioSeeder`` fixtures.
  ///
  /// Validates that `editorSeedYAML` and the per-language Home fixtures remain
  /// well-formed across refactors. Running in-process (~100 ms) catches YAML
  /// indentation drift or validator regressions long before the slow UI-test
  /// target would.
  ///
  /// **Every language assertion pins an explicit `language:` argument and
  /// compares against a literal.** The seeder's default argument is
  /// `LocaleResolver.deviceDefault()`, so comparing a locale-resolved value
  /// against a locale-resolved constant would pass on any runner locale without
  /// proving the selection works — and the validation loops would only ever
  /// reach one language's YAML. Both are why the language is enumerated here
  /// rather than inherited.
  @Suite(.timeLimit(.minutes(1)))
  @MainActor
  struct StubScenarioSeederTests {

    /// Both shipped fixture languages. The loops below iterate this
    /// unconditionally so neither language's YAML can escape validation on a
    /// differently-configured runner.
    static let languages = ["en", "ja"]

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

    // MARK: - Home fixture YAML (all rows, both languages)

    /// Every seeded Home row, in **both** languages, must parse, validate, and
    /// pass content validation — the same gate the single-language loop used to
    /// apply, widened so fixture drift in either language breaks here instead of
    /// in the slow UI-test tour (or, worse, only in the ja App Store capture).
    @Test func testAllHomeFixturesParseAndPassValidation() throws {
      let loader = ScenarioLoader()
      let validator = ScenarioValidator()
      let contentValidator = ScenarioContentValidator()
      for language in Self.languages {
        let fixtures = StubScenarioSeeder.allHomeFixtures(language: language)
        #expect(fixtures.count == 4, "expected 4 Home rows for \(language)")
        for fixture in fixtures {
          let scenario = try loader.load(yaml: fixture.yaml)
          _ = try validator.validate(scenario)
          let findings = contentValidator.validate(scenario)
          #expect(
            findings.isEmpty, "Content findings for \(scenario.id) (\(language)): \(findings)")
          // The record's display name and the YAML's own `name` drive two
          // different surfaces (the Home row label vs. re-parsed metadata); a
          // divergence renders one name on Home and another after a reload.
          #expect(
            scenario.name == fixture.name,
            "\(scenario.id) (\(language)): record '\(fixture.name)' != YAML '\(scenario.name)'")
        }
      }
    }

    /// The language selector must actually switch. Literal expectations (not
    /// `LocaleResolver`-derived ones) so a selector that ignored its argument
    /// and always returned one language would fail here.
    @Test func testHomeFixtureSelectorReturnsRequestedLanguage() {
      #expect(StubScenarioSeeder.homeSeed(language: "en").name == "Hello, Pasture")
      #expect(StubScenarioSeeder.homeSeed(language: "ja").name == "はじめての牧場")
      #expect(StubScenarioSeeder.richDilemma(language: "en").name == "Prisoner's Dilemma")
      #expect(StubScenarioSeeder.richDilemma(language: "ja").name == "囚人のジレンマ")
      #expect(StubScenarioSeeder.richDesert(language: "en").name == "Desert Survival")
      #expect(StubScenarioSeeder.richDesert(language: "ja").name == "砂漠のサバイバル")
      #expect(StubScenarioSeeder.richWordWolf(language: "en").name == "Word Wolf")
      #expect(StubScenarioSeeder.richWordWolf(language: "ja").name == "ワードウルフ")
    }

    /// An unknown / unsupported language code falls back to English, the App
    /// Store launch base locale — mirrors `LocaleResolver.deviceDefault()`'s own
    /// `default:` arm so the two can't disagree at the seam.
    @Test func testUnknownLanguageFallsBackToEnglish() {
      #expect(StubScenarioSeeder.homeSeed(language: "fr").name == "Hello, Pasture")
      #expect(StubScenarioSeeder.richWordWolf(language: "").name == "Word Wolf")
    }

    // MARK: - repository persistence

    /// `seed(into:language:)` must persist the home-list row with the expected
    /// id and the requested language's name, so UI tests can address the cell by
    /// stable accessibility identifier while the App Store capture gets
    /// locale-appropriate copy.
    @Test func testSeededScenarioPersistsToRepository() async throws {
      for (language, expectedName) in [("en", "Hello, Pasture"), ("ja", "はじめての牧場")] {
        let db = try DatabaseManager.inMemory()
        let repository = GRDBScenarioRepository(dbWriter: db.dbWriter)

        try await StubScenarioSeeder.seed(into: repository, language: language)

        let record = try repository.fetchById(StubScenarioSeeder.homeSeedScenarioId)
        let unwrapped = try #require(
          record, "fetchById(homeSeedScenarioId) returned nil after seed (\(language))")
        #expect(unwrapped.name == expectedName)
        #expect(unwrapped.isPreset == false)
      }
    }

    // MARK: - rich Home seed (--ui-test-seed-home-rich)

    /// `seedRichHome(into:language:)` persists the preset rows (with `isPreset`)
    /// and the gallery-sourced user row (with `sourceType`), and the Word Wolf
    /// scenario keeps `rounds == richWordWolfRounds` (≥ 2) — the invariant the
    /// paused-run resume card depends on for a visible progress line.
    @Test func testSeedRichHomePersistsPresetAndGalleryRows() async throws {
      let db = try DatabaseManager.inMemory()
      let repository = GRDBScenarioRepository(dbWriter: db.dbWriter)

      try await StubScenarioSeeder.seedRichHome(into: repository, language: "en")

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

    /// The `language:` argument must reach **every** persisted rich row — the
    /// regression the ja App Store screenshots exposed was English display copy
    /// surviving a Japanese-locale launch.
    @Test func testSeedRichHomeHonorsRequestedLanguage() async throws {
      let db = try DatabaseManager.inMemory()
      let repository = GRDBScenarioRepository(dbWriter: db.dbWriter)

      try await StubScenarioSeeder.seedRichHome(into: repository, language: "ja")

      let dilemma = try #require(try repository.fetchById("ui_test_preset_dilemma"))
      #expect(dilemma.name == "囚人のジレンマ")
      let desert = try #require(try repository.fetchById("ui_test_preset_desert"))
      #expect(desert.name == "砂漠のサバイバル")
      let wordWolf = try #require(
        try repository.fetchById(StubScenarioSeeder.richWordWolfScenarioId))
      #expect(wordWolf.name == "ワードウルフ")

      // `rounds` is an invariant shared with StubPausedRunSeeder — it must not
      // drift between the language variants.
      let scenario = try ScenarioLoader().load(yaml: wordWolf.yamlDefinition)
      #expect(scenario.rounds == StubScenarioSeeder.richWordWolfRounds)
    }
  }

#endif
