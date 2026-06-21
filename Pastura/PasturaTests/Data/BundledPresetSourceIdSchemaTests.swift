import Foundation
import GRDB
import Testing

@testable import Pastura

/// Schema-level invariant pin for ADR-010 D4 cross-language `sourceId`
/// aliasing. Step D's `PresetLoader` writes the canonical `sourceId`
/// on every bundled preset insert (Step D-3, #388 item 3); this suite
/// asserts the resulting data shape — both JA and EN siblings share
/// the canonical sourceId, and `fetchAllSummaries().filter` aggregates them
/// reachable by that single key.
///
/// **Scope is deliberately schema-only.** The Past Results UI
/// consumer that aggregates simulations across language variants
/// (e.g. a `ResultsView` query keyed by `sourceId` rather than the
/// per-language `scenarioId`) is NOT shipped in Step D — the data
/// layer is now ready but no production caller exercises the
/// cross-language grouping yet. The consumer surface is tracked
/// in #392 so "schema in place" stays distinct from "user-facing
/// aggregation".
///
/// **History:** this file is the rename of the pre-Step-D scaffold
/// `PastResultsLanguageCompatTests`. The original suite name promised
/// a Past Results UI consumer that the activation alone didn't
/// deliver; the schema-invariant framing here is the honest scope.
/// See the Step C-2 (#386) thread + ADR-010 D11 row 351 for the
/// migration posture this suite pins.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct BundledPresetSourceIdSchemaTests {

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

  /// ADR-010 D4 invariant — when `word_wolf` and `word_wolf_en`
  /// install side-by-side via Step D-3's `PresetLoader`, both rows
  /// carry `sourceId == "word_wolf"` (the canonical key, stripped of
  /// the `_en` suffix). The per-language `id` lookup continues to
  /// resolve each variant individually; the canonical `sourceId`
  /// aggregates both for cross-language grouping.
  @Test
  func perLanguagePresetsShareCanonicalSourceId() throws {
    let repo = try makeRepo()
    try repo.save(
      makePresetRecord(
        id: "word_wolf", name: "ワードウルフ",
        language: "ja", sourceId: "word_wolf"))
    try repo.save(
      makePresetRecord(
        id: "word_wolf_en", name: "Word Wolf",
        language: "en", sourceId: "word_wolf"))

    // Per-language id-equality continues to find each variant
    // individually (regression guard for the C-1 wrapping path).
    #expect(try repo.fetchById("word_wolf")?.sourceId == "word_wolf")
    #expect(try repo.fetchById("word_wolf_en")?.sourceId == "word_wolf")

    // Schema-level cross-language aggregation by canonical sourceId.
    // `fetchAllSummaries().filter` is the lowest-common-denominator query
    // shape — the data layer reaches both rows by sourceId regardless
    // of how a future consumer surfaces the aggregation (sourceId-
    // only fetch method, ScenarioSourceType.preset case, etc.).
    let aggregated = try repo.fetchAllSummaries().filter { $0.sourceId == "word_wolf" }
    #expect(aggregated.count == 2)
    let ids = Set(aggregated.map(\.id))
    #expect(ids == ["word_wolf", "word_wolf_en"])
  }
}
