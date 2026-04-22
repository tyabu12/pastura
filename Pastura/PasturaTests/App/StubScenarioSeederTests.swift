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
      let vm = ScenarioEditorViewModel(repository: repository)

      vm.loadFromTemplate(yaml: StubScenarioSeeder.editorSeedYAML)

      #expect(
        vm.validationErrors.isEmpty,
        "validationErrors after loadFromTemplate: \(vm.validationErrors)")

      let ok = await vm.save()
      #expect(ok, "save() returned false; errors: \(vm.validationErrors)")

      let savedId = try #require(
        vm.savedScenarioId, "savedScenarioId should be non-nil after a successful save")

      let record = try repository.fetchById(savedId)
      let unwrapped = try #require(record, "fetchById(\(savedId)) returned nil")
      #expect(unwrapped.name == StubScenarioSeeder.editorSeedScenarioName)

      #expect(vm.validationErrors.isEmpty, "validationErrors after save: \(vm.validationErrors)")
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
  }

#endif
