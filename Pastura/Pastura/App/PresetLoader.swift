import Foundation

/// Loads bundled YAML preset scenarios into the database on first launch.
///
/// Lives in App/ (not Data/) because it depends on both Engine (ScenarioLoader
/// for YAML parsing to extract names) and Data (ScenarioRepository for persistence).
/// Data/ can only depend on Models, so this bridging logic belongs in App/.
nonisolated enum PresetLoader {
  /// File names (without extension) of bundled preset YAML files.
  static let presetFileNames = [
    "prisoners_dilemma",
    "bokete",
    "word_wolf",
    "target_score_race"
  ]

  /// Loads all bundled presets into the repository if they don't already exist.
  ///
  /// Safe to call on every app launch — skips presets that are already saved.
  /// Logs warnings for missing or unparseable files but does not throw,
  /// since preset loading failure should not prevent app launch.
  static func loadPresetsIfNeeded(
    repository: any ScenarioRepository,
    bundle: Bundle = .main
  ) {
    let loader = ScenarioLoader()

    for fileName in presetFileNames {
      guard let url = bundle.url(forResource: fileName, withExtension: "yaml") else {
        print("⚠️ PresetLoader: \(fileName).yaml not found in bundle")
        continue
      }

      do {
        // Skip if already in DB
        if try repository.fetchById(fileName) != nil {
          continue
        }

        let yaml = try String(contentsOf: url, encoding: .utf8)
        let scenario = try loader.load(yaml: yaml)

        let record = ScenarioRecord(
          id: scenario.id,
          name: scenario.name,
          yamlDefinition: yaml,
          isPreset: true,
          createdAt: Date(),
          updatedAt: Date()
        )
        try repository.save(record)
      } catch {
        print("⚠️ PresetLoader: failed to load \(fileName): \(error)")
      }
    }
  }
}
