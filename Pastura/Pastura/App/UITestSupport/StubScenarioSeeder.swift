#if DEBUG

  import Foundation

  /// UI-test-only seeding helpers.
  ///
  /// Two orthogonal responsibilities:
  /// 1. ``seed(into:language:)`` — inserts a known `ScenarioRecord` into the
  ///    in-memory DB so `HomeView` shows at least one tappable row. Used by
  ///    ``BackGestureTests`` and ``EditorReloadTests`` for a deterministic
  ///    "before" count.
  /// 2. ``editorSeedYAML`` — a minimal YAML string passed to
  ///    `Route.editor(templateYAML:)` via `AppDependencies.uiTestEditorSeedYAML`.
  ///    Pre-verified to pass both `ScenarioValidator` and
  ///    `ScenarioContentValidator` after `ScenarioEditorViewModel.loadFromTemplate`'s
  ///    UUID regeneration (see `StubScenarioSeederTests`).
  ///
  /// **Display copy is per-language** (see `StubScenarioSeeder+Localized.swift`):
  /// the seeded rows are photographed for the App Store screenshots
  /// (`StoreScreenshotTests` shot 02 / 05), so a ja-locale capture must not show
  /// English scenario names. Ids, `agents`, `rounds`, and phase shape are
  /// identical across languages — only the human-readable text differs — so
  /// every accessibility anchor and round-count invariant is language-independent.
  ///
  /// Distinct from ``StubGalleryService/canaryYAML`` (id `ui_test_canary`,
  /// used by the Shared Scenarios install-flow canary) — the seeds here use
  /// `ui_test_home_seed` / `ui_test_editor_reload_seed` to keep provenance
  /// obvious to future maintainers. The *ids* carry that provenance, which is
  /// why the display names can read as ordinary scenarios (they are shipped in
  /// store screenshots) without costing traceability.
  nonisolated public enum StubScenarioSeeder {
    /// Scenario id for the Home-list seed row. Stable so tests can target
    /// `home.scenarioListCell.ui_test_home_seed` by identifier.
    public static let homeSeedScenarioId = "ui_test_home_seed"

    /// Scenario name carried by ``editorSeedYAML``. `EditorReloadTests`
    /// asserts this label appears on Home after the editor save → pop →
    /// reload chain. Deliberately **not** localized: it is matched as a literal
    /// string by that UI test, which runs in the default (en) locale.
    public static let editorSeedScenarioName = "UITest Editor Reload Seed"

    /// Inserts the Home-list seed scenario into the repository.
    ///
    /// Idempotent per `ScenarioRepository.save` semantics (full-row upsert).
    /// Called from `setupUITestState()` before the `.ready` transition.
    ///
    /// - Parameter language: Display-copy language. Production callers take the
    ///   default; tests pin it explicitly to stay deterministic across runner
    ///   locales (same convention as `BundledDemoReplaySource.loadAll`).
    public static func seed(
      into repository: any ScenarioRepository,
      language: String = LocaleResolver.deviceDefault()
    ) async throws {
      let now = Date()
      let fixture = homeSeed(language: language)
      let record = ScenarioRecord(
        id: homeSeedScenarioId,
        name: fixture.name,
        yamlDefinition: fixture.yaml,
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

    /// English copy for the Home-list seed row. Minimal but valid — parses
    /// through `ScenarioLoader`, satisfies `ScenarioValidator` (2 personas,
    /// 1 phase, rounds ≤ 30), and passes `ScenarioContentValidator`.
    static let homeSeedYAMLEn: String = """
      id: ui_test_home_seed
      language: en
      name: Hello, Pasture
      description: A two-agent warm-up — the smallest scenario you can build.
      agents: 2
      rounds: 1
      context: Two agents meet in the pasture and exchange their first greetings.
      personas:
        - name: Ivy
          description: Always the first to say hello.
        - name: Sky
          description: Reads the room before speaking.
      phases:
        - type: speak_all
          prompt: Say hello.
          output:
            statement: string
      """

    /// YAML pre-filled into the scenario editor when
    /// `--ui-test-editor-seed-yaml` is present. Must round-trip through
    /// `loadFromTemplate → save` (loader regenerates the id to a fresh UUID;
    /// the name stays stable for assertion). Not localized — see
    /// ``editorSeedScenarioName``; this fixture is never photographed.
    public static let editorSeedYAML: String = """
      id: ui_test_editor_reload_seed
      language: ja
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

    // MARK: - Rich Home seed (--ui-test-seed-home-rich)

    /// Canonical id for the gallery-sourced "Word Wolf" user row in the rich
    /// Home seed. Also the scenario that ``StubPausedRunSeeder`` references for
    /// its resume-card fixture, so every ``richWordWolf(language:)`` variant
    /// defines `rounds: 5` (≥ 2) — the resume card's progress line needs
    /// `currentRound < rounds`.
    public static let richWordWolfScenarioId = "ui_test_home_wordwolf"

    /// `rounds` baked into every ``richWordWolf(language:)`` variant. Exposed so
    /// ``StubPausedRunSeeder`` can pick a `currentRound < rounds` without
    /// re-parsing the YAML. Language-independent by construction — the
    /// per-language validation loop in `StubScenarioSeederTests` asserts it.
    public static let richWordWolfRounds = 5

    /// Seeds the richer Home fixture the ui-tour and App Store screenshots use:
    /// two bundled presets (so the "Preset" badge and a multi-row card render)
    /// plus a gallery-sourced user scenario (a "shared" install shown alongside
    /// the always-present ``homeSeedScenarioId`` row). Opt-in via the
    /// `--ui-test-seed-home-rich` launch argument; plain `--ui-test` keeps the
    /// minimal single-row seed so navigation tests stay deterministic.
    ///
    /// Idempotent per `ScenarioRepository.save` (full-row upsert) — safe to
    /// re-run after an in-test app relaunch.
    ///
    /// - Parameter language: see ``seed(into:language:)``.
    public static func seedRichHome(
      into repository: any ScenarioRepository,
      language: String = LocaleResolver.deviceDefault()
    ) async throws {
      let now = Date()
      let dilemma = richDilemma(language: language)
      let desert = richDesert(language: language)
      let wordWolf = richWordWolf(language: language)
      let records: [ScenarioRecord] = [
        ScenarioRecord(
          id: "ui_test_preset_dilemma", name: dilemma.name,
          yamlDefinition: dilemma.yaml, isPreset: true,
          createdAt: now, updatedAt: now),
        ScenarioRecord(
          id: "ui_test_preset_desert", name: desert.name,
          yamlDefinition: desert.yaml, isPreset: true,
          createdAt: now, updatedAt: now),
        ScenarioRecord(
          id: richWordWolfScenarioId, name: wordWolf.name,
          yamlDefinition: wordWolf.yaml, isPreset: false,
          createdAt: now, updatedAt: now,
          // sourceType "gallery" makes this read as a Shared-Scenarios install
          // (a "共有シナリオ") on the Home list. sourceId is a stub — the
          // --ui-test StubGalleryService index doesn't carry it, so no spurious
          // "Update" badge surfaces (refreshGalleryUpdateBadges finds no match).
          sourceType: ScenarioSourceType.gallery,
          sourceId: "ui_test_gallery_wordwolf",
          sourceHash: String(repeating: "0", count: 64))
      ]
      try await offMain {
        for record in records { try repository.save(record) }
      }
    }

    /// English preset fixture: 2 agents, 10 rounds. inferences = 2×10 = 20
    /// (< 50 warn).
    static let richDilemmaYAMLEn: String = """
      id: ui_test_preset_dilemma
      language: en
      name: Prisoner's Dilemma
      description: Cooperate or defect — watch trust build or break over repeated rounds.
      agents: 2
      rounds: 10
      context: Two agents repeatedly choose to cooperate or defect.
      personas:
        - name: Alice
          description: Tends to cooperate when trust is high.
        - name: Bob
          description: Weighs short-term gain against reputation.
      phases:
        - type: speak_all
          prompt: State your choice and reasoning.
          output:
            statement: string
      """

    /// English preset fixture: 3 agents, 8 rounds. inferences = 3×8 = 24
    /// (< 50 warn).
    static let richDesertYAMLEn: String = """
      id: ui_test_preset_desert
      language: en
      name: Desert Survival
      description: Stranded survivors rank their gear and reach consensus to make it out.
      agents: 3
      rounds: 8
      context: Three survivors must agree on how to prioritize limited supplies.
      personas:
        - name: Carol
          description: Pragmatic and risk-averse.
        - name: Dave
          description: Optimistic and quick to act.
        - name: Erin
          description: Methodical, insists on a shared plan.
      phases:
        - type: speak_all
          prompt: Argue for your supply priority.
          output:
            statement: string
      """

    /// English gallery-sourced user fixture: 4 agents, 5 rounds.
    /// inferences = 4×5 = 20. ``StubPausedRunSeeder`` references this scenario,
    /// so `rounds` stays ≥ 2.
    static let richWordWolfYAMLEn: String = """
      id: ui_test_home_wordwolf
      language: en
      name: Word Wolf
      description: Find the minority who was handed a different word — a hidden-role talk game.
      agents: 4
      rounds: 5
      context: Players discuss their secret word to expose the odd one out.
      personas:
        - name: Alice
          description: Asks probing questions early.
        - name: Bob
          description: Keeps a low profile to avoid suspicion.
        - name: Carol
          description: Builds on others' clues.
        - name: Dave
          description: Bluffs confidently when cornered.
      phases:
        - type: speak_all
          prompt: Describe your word without naming it.
          output:
            statement: string
      """
  }

#endif
