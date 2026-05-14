import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct PresetLoaderTests {
  @Test func loadPresetsCreatesRecordsInEmptyDB() throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)

    PresetLoader.loadPresetsIfNeeded(
      repository: repo,
      bundle: Bundle(for: DatabaseManager.self)
    )

    let all = try repo.fetchAll()
    #expect(all.count == 8)

    let presets = try repo.fetchPresets()
    #expect(presets.count == 8)

    let ids = Set(presets.map(\.id))
    // JA siblings (Phase 1 baseline, retained)
    #expect(ids.contains("prisoners_dilemma"))
    #expect(ids.contains("bokete"))
    #expect(ids.contains("word_wolf"))
    #expect(ids.contains("target_score_race"))
    // EN siblings (Step D, ADR-010 D3 sibling-files layout)
    #expect(ids.contains("prisoners_dilemma_en"))
    #expect(ids.contains("bokete_en"))
    #expect(ids.contains("word_wolf_en"))
    #expect(ids.contains("target_score_race_en"))
  }

  @Test func loadPresetsSkipsExistingRecords() throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)

    // Load once
    PresetLoader.loadPresetsIfNeeded(
      repository: repo,
      bundle: Bundle(for: DatabaseManager.self)
    )
    let first = try repo.fetchById("prisoners_dilemma")
    let firstDate = first?.createdAt

    // Load again — should not overwrite
    PresetLoader.loadPresetsIfNeeded(
      repository: repo,
      bundle: Bundle(for: DatabaseManager.self)
    )
    let second = try repo.fetchById("prisoners_dilemma")

    #expect(second?.createdAt == firstDate)
    #expect(try repo.fetchAll().count == 8)
  }

  /// ADR-010 D4: per-language sibling presets share a canonical
  /// `sourceId` (the JA filename / id without `_<lang>` suffix). The
  /// `id` column remains per-language; `sourceId` is the cross-language
  /// grouping key for Past Results aggregation surfaces (consumer
  /// surface deferred per #388 item 7 tracking issue).
  @Test func presetsWriteCanonicalSourceIdOnInsert() throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)

    PresetLoader.loadPresetsIfNeeded(
      repository: repo,
      bundle: Bundle(for: DatabaseManager.self)
    )

    // JA siblings: id == sourceId (no suffix to strip).
    #expect(try repo.fetchById("word_wolf")?.sourceId == "word_wolf")
    #expect(try repo.fetchById("bokete")?.sourceId == "bokete")
    #expect(try repo.fetchById("prisoners_dilemma")?.sourceId == "prisoners_dilemma")
    #expect(try repo.fetchById("target_score_race")?.sourceId == "target_score_race")

    // EN siblings: `_en` suffix stripped to match the JA canonical id.
    #expect(try repo.fetchById("word_wolf_en")?.sourceId == "word_wolf")
    #expect(try repo.fetchById("bokete_en")?.sourceId == "bokete")
    #expect(try repo.fetchById("prisoners_dilemma_en")?.sourceId == "prisoners_dilemma")
    #expect(try repo.fetchById("target_score_race_en")?.sourceId == "target_score_race")
  }

  /// Cross-language grouping invariant: for each canonical id, both
  /// language siblings carry the same `sourceId`. This is the
  /// schema-level pin for ADR-010 D4; the production Past Results UI
  /// consumer that aggregates by this key is tracked separately and
  /// not part of Step D.
  @Test func perLanguageSiblingsShareSourceId() throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)

    PresetLoader.loadPresetsIfNeeded(
      repository: repo,
      bundle: Bundle(for: DatabaseManager.self)
    )

    for canonical in ["word_wolf", "bokete", "prisoners_dilemma", "target_score_race"] {
      let ja = try repo.fetchById(canonical)
      let en = try repo.fetchById("\(canonical)_en")
      #expect(ja?.sourceId == canonical, "JA \(canonical) sourceId")
      #expect(en?.sourceId == canonical, "EN \(canonical) sourceId")
      // Cross-language grouping reachable by sourceId — distinct PKs,
      // shared canonical key.
      let bySourceId = try repo.fetchAll().filter { $0.sourceId == canonical }
      #expect(bySourceId.count == 2)
    }
  }

  @Test func loadPresetsMarksRecordsAsPreset() throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)

    PresetLoader.loadPresetsIfNeeded(
      repository: repo,
      bundle: Bundle(for: DatabaseManager.self)
    )

    let all = try repo.fetchAll()
    for record in all {
      #expect(record.isPreset == true)
    }
  }

  /// Regression test for the word_wolf bug: an `assign` phase whose `source`
  /// resolves to `.arrayOfDictionaries` in `scenario.extraData` MUST use
  /// `target: "random_one"`. Using `target: "all"` produces empty assignments
  /// because the handler expects a flat array when distributing to all agents.
  @Test func assignPhaseWithDictSourceMustUseRandomOneTarget() throws {
    let loader = ScenarioLoader()
    let bundle = Bundle(for: DatabaseManager.self)

    for fileName in PresetLoader.presetFileNames {
      guard let url = bundle.url(forResource: fileName, withExtension: "yaml") else {
        continue  // Missing file is caught by presetYAMLsAreParseable
      }
      let yaml = try String(contentsOf: url, encoding: .utf8)
      let scenario = try loader.load(yaml: yaml)

      for (index, phase) in scenario.phases.enumerated() {
        guard phase.type == .assign, let sourceKey = phase.source else {
          continue
        }
        let extraValue = scenario.extraData[sourceKey]
        if case .arrayOfDictionaries = extraValue {
          #expect(
            phase.target == .randomOne,
            "\(fileName).yaml phase[\(index)]: assign with arrayOfDictionaries source '\(sourceKey)' must use target 'random_one', got '\(phase.target?.rawValue ?? "nil")'"
          )
        }
      }
    }
  }

  @Test func presetYAMLsAreParseable() throws {
    let loader = ScenarioLoader()
    let bundle = Bundle(for: DatabaseManager.self)

    for fileName in PresetLoader.presetFileNames {
      let url = bundle.url(forResource: fileName, withExtension: "yaml")
      #expect(url != nil, "Missing preset: \(fileName).yaml")

      if let url {
        let yaml = try String(contentsOf: url, encoding: .utf8)
        let scenario = try loader.load(yaml: yaml)
        #expect(!scenario.name.isEmpty)
        #expect(scenario.agentCount >= 2)
        #expect(!scenario.phases.isEmpty)
      }
    }
  }

  /// Regression guard for the "speak_all missing statement" bug class
  /// (#318 / #343). Asserts every bundled preset survives the strict
  /// commit-time gate — the same gate `ScenarioEditorViewModel.save()`
  /// runs when a user clones a preset via "Use as Template" and saves.
  /// A canonical-field omission slipping into a preset YAML would block
  /// that flow on every cloned copy.
  @Test func presetYAMLsPassValidateForCommit() throws {
    let loader = ScenarioLoader()
    let validator = ScenarioValidator()
    let bundle = Bundle(for: DatabaseManager.self)

    // Phantom-pass guard — if `presetFileNames` is ever emptied or the
    // bundle resource group is misnamed, an empty iteration would
    // trivially pass without auditing anything.
    #expect(PresetLoader.presetFileNames.count >= 8)

    for fileName in PresetLoader.presetFileNames {
      guard let url = bundle.url(forResource: fileName, withExtension: "yaml") else {
        Issue.record("Missing preset: \(fileName).yaml")
        continue
      }
      let yaml = try String(contentsOf: url, encoding: .utf8)
      let scenario = try loader.load(yaml: yaml)
      #expect(throws: Never.self) {
        _ = try validator.validateForCommit(scenario)
      }
    }
  }
}
