import Foundation

@testable import Pastura

/// Preset fixture helpers for `HomeViewModelTests`, split out to keep the main
/// suite under swiftlint's `type_body_length`. Internal (not `private`) so the
/// sibling-file suite can call them (see `.claude/rules/testing.md`).
extension HomeViewModelTests {
  /// Bundled-preset summary with a denormalized `language` column (#679 reads
  /// the column, not the YAML).
  func makePreset(id: String, language: String?, sourceId: String?) -> ScenarioSummary {
    ScenarioSummary(id: id, name: id, isPreset: true, sourceId: sourceId, language: language)
  }

  /// DB-savable bundled-preset record carrying the denormalized `language`
  /// column — for the integration tests that round-trip through the repository
  /// (collapse reads the column off `fetchAllSummaries`, not the YAML).
  func makePresetRecord(id: String, language: String, sourceId: String?) -> ScenarioRecord {
    ScenarioRecord(
      id: id, name: id, yamlDefinition: "id: \(id)\nlanguage: \(language)\nname: \(id)\n",
      isPreset: true, createdAt: Date(), updatedAt: Date(),
      sourceType: nil, sourceId: sourceId, sourceHash: nil, language: language)
  }
}
