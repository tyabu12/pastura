import Foundation
import GRDB
import Testing

@testable import Pastura

/// Cross-language Past Results grouping by `ScenarioRecord.sourceId`
/// (ADR-010 D4). The grouping path activates when Step D ships
/// per-language sibling presets (e.g., `word_wolf` + `word_wolf_en`
/// installed side-by-side with `sourceId == "word_wolf"` on both),
/// at which point Past Results queries can aggregate simulations
/// across language variants by `sourceId`.
///
/// **Phase 1 / C-2 baseline (current state):** the only `word_wolf`
/// preset shipped installs with `sourceId == nil` (bundled-preset
/// convention; only gallery imports set sourceId — verified by
/// `ScenarioRepositoryTests.fetchBySourceFindsGalleryRow`). The
/// id-equality path is therefore the only Past Results lookup in
/// production. See
/// `ScenarioRepositoryTests.fetchByIdResolvesPhase1BaselinePresetWordWolf`
/// for the id-equality unit test that confirms the C-1 wrapping did
/// not break that path.
///
/// **Scaffold tests below are `.disabled`** until Step D's per-language
/// installer wiring lands. Activation checklist:
/// - [ ] `PresetLoader` (or its successor) writes `sourceId` on
///   bundled-preset installs for both `word_wolf` and `word_wolf_en`.
/// - [ ] At least one Past Results consumer queries
///   `ScenarioRepository.fetchBySource(...)` (already implemented per
///   `ScenarioRepositoryTests.fetchBySourceFindsGalleryRow`) with a
///   `sourceType` other than `gallery` — likely a new
///   `ScenarioSourceType.preset` case or a sourceId-only lookup.
/// - [ ] Remove `.disabled(...)` traits below and run.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct PastResultsLanguageCompatTests {

  private func makeRepo() throws -> GRDBScenarioRepository {
    let manager = try DatabaseManager.inMemory()
    return GRDBScenarioRepository(dbWriter: manager.dbWriter)
  }

  private func makePresetRecord(
    id: String, name: String, language: String, sourceId: String?
  ) -> ScenarioRecord {
    ScenarioRecord(
      id: id, name: name,
      yamlDefinition: "id: \(id)\nlanguage: \(language)\nname: \(name)\n",
      isPreset: true, createdAt: Date(), updatedAt: Date(),
      sourceType: nil, sourceId: sourceId, sourceHash: nil)
  }

  @Test(
    .disabled(
      "Activates when Step D ships *_en presets and the installer sets sourceId on bundled presets — see ADR-010 D4."
    ))
  func perLanguagePresetsShareSourceIdAfterStepD() throws {
    // Step D will ship `word_wolf_en` alongside `word_wolf`, both
    // with `sourceId == "word_wolf"` per ADR-010 D4. The id-equality
    // lookups continue to find each language variant individually,
    // and a sourceId-based aggregation path (TBD by Step D) finds
    // both for cross-language Past Results grouping.
    let repo = try makeRepo()
    try repo.save(
      makePresetRecord(
        id: "word_wolf", name: "ワードウルフ",
        language: "ja", sourceId: "word_wolf"))
    try repo.save(
      makePresetRecord(
        id: "word_wolf_en", name: "Word Wolf",
        language: "en", sourceId: "word_wolf"))

    // id-equality continues to work per language.
    #expect(try repo.fetchById("word_wolf")?.sourceId == "word_wolf")
    #expect(try repo.fetchById("word_wolf_en")?.sourceId == "word_wolf")

    // Cross-language aggregation by sourceId. Exact API shape
    // depends on Step D's installer changes (likely a new
    // ScenarioSourceType case, or a sourceId-only fetch method on
    // ScenarioRepository). The placeholder below pins intent; the
    // assertion is left to Step D's implementer.
    let all = try repo.fetchAll().filter { $0.sourceId == "word_wolf" }
    #expect(all.count == 2)
  }
}
