#if DEBUG

  import Foundation

  /// UI-test-only seeding helpers.
  ///
  /// Two orthogonal responsibilities:
  /// 1. ``seed(into:)`` — inserts a known `ScenarioRecord` into the in-memory
  ///    DB so `HomeView` shows at least one tappable row. Used by
  ///    ``BackGestureTests`` and ``EditorReloadTests`` for a deterministic
  ///    "before" count.
  /// 2. ``editorSeedYAML`` — a minimal YAML string passed to
  ///    `Route.editor(templateYAML:)` via `AppDependencies.uiTestEditorSeedYAML`.
  ///    Pre-verified to pass both `ScenarioValidator` and
  ///    `ScenarioContentValidator` after `ScenarioEditorViewModel.loadFromTemplate`'s
  ///    UUID regeneration (see `StubScenarioSeederTests`).
  ///
  /// Distinct from ``StubGalleryService/canaryYAML`` (id `ui_test_canary`,
  /// used by the Share Board install-flow canary) — the seeds here use
  /// `ui_test_home_seed` / `ui_test_editor_reload_seed` to keep provenance
  /// obvious to future maintainers.
  nonisolated public enum StubScenarioSeeder {
    /// Scenario id for the Home-list seed row. Stable so tests can target
    /// `home.scenarioListCell.ui_test_home_seed` by identifier.
    public static let homeSeedScenarioId = "ui_test_home_seed"

    /// Human-readable name for the Home-list seed row. Distinct from any
    /// preset or gallery fixture so UI tests can query it unambiguously.
    public static let homeSeedScenarioName = "UITest Home Seed"

    /// Scenario name carried by ``editorSeedYAML``. `EditorReloadTests`
    /// asserts this label appears on Home after the editor save → pop →
    /// reload chain.
    public static let editorSeedScenarioName = "UITest Editor Reload Seed"

    /// Inserts the Home-list seed scenario into the repository.
    ///
    /// Idempotent per `ScenarioRepository.save` semantics (full-row upsert).
    /// Called from `setupUITestState()` before the `.ready` transition.
    public static func seed(into repository: any ScenarioRepository) async throws {
      let now = Date()
      let record = ScenarioRecord(
        id: homeSeedScenarioId,
        name: homeSeedScenarioName,
        yamlDefinition: homeSeedYAML,
        isPreset: false,
        createdAt: now,
        updatedAt: now
      )
      try await offMain { try repository.save(record) }
    }

    // NOTE: YAML is indentation-sensitive; do not reflow these multi-line
    // literals (the closing `"""` column is the baseline). swift-format
    // preserves multi-line strings but editor refactors can break them —
    // `StubScenarioSeederTests` catches any such regression quickly.

    /// YAML backing the Home-list seed row. Minimal but valid — parses
    /// through `ScenarioLoader`, satisfies `ScenarioValidator` (2 personas,
    /// 1 phase, rounds ≤ 30), and passes `ScenarioContentValidator`
    /// (English-only non-blocklisted text).
    static let homeSeedYAML: String = """
      id: ui_test_home_seed
      name: UITest Home Seed
      description: Seed scenario shown on the Home list under --ui-test.
      agents: 2
      rounds: 1
      context: UI test seed scenario for navigation coverage.
      personas:
        - name: Alice
          description: First seeded persona.
        - name: Bob
          description: Second seeded persona.
      phases:
        - type: speak_all
          prompt: Say hello.
          output:
            statement: string
      """

    /// YAML pre-filled into the scenario editor when
    /// `--ui-test-editor-seed-yaml` is present. Must round-trip through
    /// `loadFromTemplate → save` (loader regenerates the id to a fresh UUID;
    /// the name stays stable for assertion).
    public static let editorSeedYAML: String = """
      id: ui_test_editor_reload_seed
      name: UITest Editor Reload Seed
      description: Seed YAML pre-filled into the editor for #110.
      agents: 2
      rounds: 1
      context: UI test seed scenario for editor save reload coverage.
      personas:
        - name: Carol
          description: First editor-seed persona.
        - name: Dave
          description: Second editor-seed persona.
      phases:
        - type: speak_all
          prompt: Say hello.
          output:
            statement: string
      """
  }

#endif
