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

    let all = try repo.fetchAllSummaries()
    #expect(all.count == 12)

    let presets = try repo.fetchPresets()
    #expect(presets.count == 12)

    let ids = Set(presets.map(\.id))
    // JA siblings (Phase 1 baseline, retained)
    #expect(ids.contains("prisoners_dilemma"))
    #expect(ids.contains("bokete"))
    #expect(ids.contains("word_wolf"))
    #expect(ids.contains("target_score_race"))
    #expect(ids.contains("last_fable"))
    #expect(ids.contains("souzoku_kaigi"))
    // EN siblings (Step D, ADR-010 D3 sibling-files layout)
    #expect(ids.contains("prisoners_dilemma_en"))
    #expect(ids.contains("bokete_en"))
    #expect(ids.contains("word_wolf_en"))
    #expect(ids.contains("target_score_race_en"))
    #expect(ids.contains("last_fable_en"))
    #expect(ids.contains("souzoku_kaigi_en"))
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
    #expect(try repo.fetchAllSummaries().count == 12)
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
    #expect(try repo.fetchById("last_fable")?.sourceId == "last_fable")
    #expect(try repo.fetchById("souzoku_kaigi")?.sourceId == "souzoku_kaigi")

    // EN siblings: `_en` suffix stripped to match the JA canonical id.
    #expect(try repo.fetchById("word_wolf_en")?.sourceId == "word_wolf")
    #expect(try repo.fetchById("bokete_en")?.sourceId == "bokete")
    #expect(try repo.fetchById("prisoners_dilemma_en")?.sourceId == "prisoners_dilemma")
    #expect(try repo.fetchById("target_score_race_en")?.sourceId == "target_score_race")
    #expect(try repo.fetchById("last_fable_en")?.sourceId == "last_fable")
    #expect(try repo.fetchById("souzoku_kaigi_en")?.sourceId == "souzoku_kaigi")
  }

  /// ADR-010 D6 denormalization: `PresetLoader` writes each preset's
  /// `language` column from the parsed `Scenario.language`, so Home /
  /// Past Results can collapse variants without parsing YAML (#679).
  @Test func presetsWriteLanguageColumnOnInsert() throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)

    PresetLoader.loadPresetsIfNeeded(
      repository: repo,
      bundle: Bundle(for: DatabaseManager.self)
    )

    #expect(try repo.fetchById("word_wolf")?.language == "ja")
    #expect(try repo.fetchById("prisoners_dilemma")?.language == "ja")
    #expect(try repo.fetchById("last_fable")?.language == "ja")
    #expect(try repo.fetchById("souzoku_kaigi")?.language == "ja")
    #expect(try repo.fetchById("word_wolf_en")?.language == "en")
    #expect(try repo.fetchById("prisoners_dilemma_en")?.language == "en")
    #expect(try repo.fetchById("last_fable_en")?.language == "en")
    #expect(try repo.fetchById("souzoku_kaigi_en")?.language == "en")
    // Every bundled preset carries a non-nil language column.
    #expect(try repo.fetchAllSummaries().allSatisfy { $0.language != nil })
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

    for canonical in [
      "word_wolf", "bokete", "prisoners_dilemma", "target_score_race", "last_fable",
      "souzoku_kaigi"
    ] {
      let ja = try repo.fetchById(canonical)
      let en = try repo.fetchById("\(canonical)_en")
      #expect(ja?.sourceId == canonical, "JA \(canonical) sourceId")
      #expect(en?.sourceId == canonical, "EN \(canonical) sourceId")
      // Cross-language grouping reachable by sourceId — distinct PKs,
      // shared canonical key.
      let bySourceId = try repo.fetchAllSummaries().filter { $0.sourceId == canonical }
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

    let all = try repo.fetchAllSummaries()
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

  /// #607 canary: every bundled preset's `output:` keys must be ASCII
  /// identifiers. A CJK / multi-byte output key would emit as a GBNF JSON-key
  /// literal and crash llama.cpp's sampler at accept-time on-device. The
  /// presets are all ASCII today (`statement`, `inner_thought`, `action`,
  /// `vote`, `reason`); this fails at build/test time if a future preset ships
  /// a non-ASCII key, rather than at device run time. `validateForCommit`
  /// already enforces this transitively, but this asserts the rule directly.
  @Test func presetOutputFieldNamesAreAsciiIdentifiers() throws {
    let loader = ScenarioLoader()
    let bundle = Bundle(for: DatabaseManager.self)

    #expect(PresetLoader.presetFileNames.count >= 10)

    for fileName in PresetLoader.presetFileNames {
      guard let url = bundle.url(forResource: fileName, withExtension: "yaml") else {
        Issue.record("Missing preset: \(fileName).yaml")
        continue
      }
      let yaml = try String(contentsOf: url, encoding: .utf8)
      let scenario = try loader.load(yaml: yaml)
      // Flatten top-level phases plus conditional then/else sub-phases
      // (depth-1) so a hostile key buried in a branch is caught too.
      let allPhases =
        scenario.phases + scenario.phases.flatMap { ($0.thenPhases ?? []) + ($0.elsePhases ?? []) }
      for phase in allPhases {
        for name in phase.outputSchema?.keys ?? [:].keys {
          #expect(
            ScenarioConventions.isValidFieldName(name),
            "\(fileName).yaml: output key '\(name)' is not an ASCII identifier")
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
    #expect(PresetLoader.presetFileNames.count >= 10)

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

  /// #881 Stage 3 change-detector: the demonstrated brevity-override gain lives
  /// entirely in `last_fable`'s `speak_all` `max_sentences: 6`. Value-level
  /// preset content is otherwise unguarded (`presets.md` — the fixture suites
  /// key on ids / schema shape / placeholder tokens, not scalar values), so a
  /// future `git add -A` catalog re-serialization or an editor round-trip could
  /// silently drop the key with every other gate green. A failure here is NOT a
  /// bug: it means the override drifted — confirm the change was intended, then
  /// update the expected value. (`view-testing.md` § change-detector tripwire.)
  @Test func lastFableSpeakAllPinsMaxSentencesOverride() throws {
    let loader = ScenarioLoader()
    let bundle = Bundle(for: DatabaseManager.self)

    // Both ja + en siblings carry the mechanic (presets.md ja/en parity),
    // though the lever is empirically ja-only.
    for fileName in ["last_fable", "last_fable_en"] {
      guard let url = bundle.url(forResource: fileName, withExtension: "yaml") else {
        Issue.record("Missing preset: \(fileName).yaml")
        continue
      }
      let yaml = try String(contentsOf: url, encoding: .utf8)
      let scenario = try loader.load(yaml: yaml)
      guard let speakAll = scenario.phases.first(where: { $0.type == .speakAll }) else {
        Issue.record("\(fileName).yaml: no speak_all phase")
        continue
      }
      #expect(
        speakAll.maxSentences == 6,
        "\(fileName).yaml speak_all max_sentences drifted from 6 (got \(speakAll.maxSentences.map(String.init) ?? "nil")) — see #881 Stage 3"
      )
    }
  }

  /// `souzoku_kaigi` is the first bundled preset to use the `Persona.secret`
  /// field (#1149 / PR #1141). ja/en parity for `secret:` presence is
  /// otherwise only code-review-gated — `presets.md` § "ja/en parity" mandates
  /// structural sync, but the fixture suites key on ids / schema shape /
  /// placeholder tokens, not `secret:` presence — so a future edit dropping a
  /// secret from one sibling would slip past every automated gate. A failure
  /// here is NOT a bug: confirm the change was intended, then update.
  /// (`view-testing.md` § change-detector tripwire.)
  @Test func souzokuKaigiSiblingsPinSecretParity() throws {
    let loader = ScenarioLoader()
    let bundle = Bundle(for: DatabaseManager.self)

    var personaCounts: [String: Int] = [:]
    for fileName in ["souzoku_kaigi", "souzoku_kaigi_en"] {
      guard let url = bundle.url(forResource: fileName, withExtension: "yaml") else {
        Issue.record("Missing preset: \(fileName).yaml")
        continue
      }
      let yaml = try String(contentsOf: url, encoding: .utf8)
      let scenario = try loader.load(yaml: yaml)
      personaCounts[fileName] = scenario.personas.count
      #expect(scenario.personas.count == 5, "\(fileName).yaml expected 5 personas")
      for persona in scenario.personas {
        #expect(
          persona.secret?.isEmpty == false,
          "\(fileName).yaml persona \(persona.name) missing secret — ja/en secret parity (#1149)"
        )
      }
    }
    // Structural parity: both siblings carry the same persona count.
    #expect(personaCounts["souzoku_kaigi"] == personaCounts["souzoku_kaigi_en"])
  }
}
