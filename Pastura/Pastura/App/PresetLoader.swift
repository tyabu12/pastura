import Foundation
import os

/// Loads bundled YAML preset scenarios into the database on first launch.
///
/// Lives in App/ (not Data/) because it depends on both Engine (ScenarioLoader
/// for YAML parsing to extract names) and Data (ScenarioRepository for persistence).
/// Data/ can only depend on Models, so this bridging logic belongs in App/.
nonisolated enum PresetLoader {
  private static let logger = Logger(
    subsystem: "app.pastura.Pastura", category: "PresetLoader")

  /// File names (without extension) of bundled preset YAML files.
  ///
  /// Per ADR-010 D3 sibling-files layout: JA siblings retain the
  /// no-suffix filename (Phase 1 convention); EN siblings carry the
  /// `_en` suffix. The canonical id used for cross-language `sourceId`
  /// grouping (D4) is the JA filename — see ``canonicalSourceId(for:)``.
  static let presetFileNames = [
    "prisoners_dilemma",
    "bokete",
    "word_wolf",
    "target_score_race",
    "last_fable",
    "prisoners_dilemma_en",
    "bokete_en",
    "word_wolf_en",
    "target_score_race_en",
    "last_fable_en"
  ]

  /// Loads all bundled presets into the repository if they don't already exist.
  ///
  /// Safe to call on every app launch — skips presets that are already saved.
  /// Logs warnings for missing or unparseable files but does not throw,
  /// since preset loading failure should not prevent app launch.
  ///
  /// **ADR-010 D4 `sourceId` wiring**: new inserts carry a canonical
  /// `sourceId` derived from `scenario.id` minus its `_<language>`
  /// suffix when present. Both JA and EN siblings of the same preset
  /// share that canonical id, unlocking cross-language Past Results
  /// grouping (the consumer surface that aggregates by `sourceId` is
  /// tracked as a follow-up issue).
  ///
  /// **No backfill for pre-Step-D rows** (ADR-010 D11 row 351): if a
  /// row already exists with `sourceId == nil` from a Phase 1 / C-1 /
  /// C-2 install, this method does NOT update it. The install-base
  /// reset called out in release notes absorbs the schema gap; the
  /// install base is effectively zero in practice.
  static func loadPresetsIfNeeded(
    repository: any ScenarioRepository,
    bundle: Bundle = .main
  ) {
    let loader = ScenarioLoader()

    for fileName in presetFileNames {
      guard let url = bundle.url(forResource: fileName, withExtension: "yaml") else {
        Self.logger.error(
          "PresetLoader: \(fileName, privacy: .public).yaml not found in bundle")
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
          updatedAt: Date(),
          sourceId: canonicalSourceId(for: scenario),
          language: scenario.language
        )
        try repository.save(record)
      } catch {
        Self.logger.error(
          "PresetLoader: failed to load \(fileName, privacy: .public): \(String(describing: error), privacy: .public)"
        )
      }
    }
  }

  /// Derives the cross-language canonical `sourceId` from a parsed
  /// scenario per ADR-010 D4.
  ///
  /// JA siblings (no language suffix on filename / id) keep their id
  /// as the canonical key. Non-JA siblings strip the `_<language>`
  /// suffix — `word_wolf_en` → `word_wolf`. Defensive: when the
  /// suffix is absent (malformed id / mismatched filename), the
  /// scenario's literal id passes through unchanged so cross-language
  /// grouping degrades gracefully to id-equality.
  internal static func canonicalSourceId(for scenario: Scenario) -> String {
    let suffix = "_\(scenario.language)"
    guard scenario.id.hasSuffix(suffix) else { return scenario.id }
    return String(scenario.id.dropLast(suffix.count))
  }
}
