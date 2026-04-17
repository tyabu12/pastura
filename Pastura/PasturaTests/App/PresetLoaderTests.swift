import Foundation
import Testing

@testable import Pastura

struct PresetLoaderTests {
  @Test func loadPresetsCreatesRecordsInEmptyDB() throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)

    PresetLoader.loadPresetsIfNeeded(
      repository: repo,
      bundle: Bundle(for: DatabaseManager.self)
    )

    let all = try repo.fetchAll()
    #expect(all.count == 3)

    let presets = try repo.fetchPresets()
    #expect(presets.count == 3)

    let ids = Set(presets.map(\.id))
    #expect(ids.contains("prisoners_dilemma"))
    #expect(ids.contains("bokete"))
    #expect(ids.contains("word_wolf"))
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
    #expect(try repo.fetchAll().count == 3)
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
}
