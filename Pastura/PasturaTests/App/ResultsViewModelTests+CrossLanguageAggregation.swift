import Foundation
import GRDB
import Testing

@testable import Pastura

/// Cross-language aggregation tests for ``ResultsViewModel``. Sibling
/// extension on the same suite — see `testing.md` § "Splitting a Suite
/// Across Files".
///
/// Covers ADR-010 D4 / D6 behavior surfaced in the Home Past Results
/// list (#392):
///
/// - JA + EN variants sharing a canonical `sourceId` collapse to one
///   group; the section header uses the device-locale variant's name
///   (with first-variant fallback). Rows preserve the simulation-time
///   variant's own `name` (un-translated).
/// - Detail entry-point keeps per-variant scoping — a JA scenario id
///   does not surface EN sibling runs.
/// - Orphaned simulations (sims whose `scenarioId` references a
///   scenario absent from `scenarios`) are silently invisible — the
///   `for scenario in scenarios` iteration in `loadHomeAggregated`
///   never reaches them. Schema-level `ON DELETE CASCADE` is the first
///   line of defense; this test pins the second line by planting an
///   orphan via `PRAGMA foreign_keys = OFF` direct write.
extension ResultsViewModelTests {

  // MARK: - Helpers specific to aggregation

  fileprivate func seedScenario(
    scenarioRepo: GRDBScenarioRepository,
    id: String, name: String, language: String, sourceId: String?
  ) throws {
    try scenarioRepo.save(
      ScenarioRecord(
        id: id, name: name,
        yamlDefinition: "id: \(id)\nlanguage: \(language)\nname: \(name)\n",
        isPreset: true, createdAt: Date(), updatedAt: Date(),
        sourceType: nil, sourceId: sourceId, sourceHash: nil
      ))
  }

  fileprivate func seedSimulation(
    simRepo: GRDBSimulationRepository,
    id: String, scenarioId: String, createdAt: Date = Date()
  ) throws {
    try simRepo.save(
      SimulationRecord(
        id: id, scenarioId: scenarioId,
        status: SimulationStatus.completed.rawValue,
        currentRound: 1, currentPhaseIndex: 0,
        stateJSON: "{}", configJSON: nil,
        createdAt: createdAt, updatedAt: createdAt
      ))
  }

  // MARK: - Aggregation

  @Test func loadAllAggregatesJAAndENVariantsByCanonicalSourceId() async throws {
    let env = try makeResultsSUT()

    try seedScenario(
      scenarioRepo: env.scenarioRepo,
      id: "word_wolf", name: "ワードウルフ", language: "ja", sourceId: "word_wolf")
    try seedScenario(
      scenarioRepo: env.scenarioRepo,
      id: "word_wolf_en", name: "Word Wolf", language: "en", sourceId: "word_wolf")
    try seedSimulation(simRepo: env.simRepo, id: "sim_ja_1", scenarioId: "word_wolf")
    try seedSimulation(simRepo: env.simRepo, id: "sim_ja_2", scenarioId: "word_wolf")
    try seedSimulation(simRepo: env.simRepo, id: "sim_en_1", scenarioId: "word_wolf_en")

    await env.sut.load(scenarioId: "", deviceLanguage: "ja")

    #expect(env.sut.groups.count == 1)
    let group = try #require(env.sut.groups.first)
    #expect(group.canonicalKey == "word_wolf")
    #expect(group.rows.count == 3)
    let simIds = Set(group.rows.map { $0.record.id })
    #expect(simIds == ["sim_ja_1", "sim_ja_2", "sim_en_1"])
  }

  @Test func loadAllPicksJAVariantNameForSectionOnJADevice() async throws {
    let env = try makeResultsSUT()

    try seedScenario(
      scenarioRepo: env.scenarioRepo,
      id: "word_wolf", name: "ワードウルフ", language: "ja", sourceId: "word_wolf")
    try seedScenario(
      scenarioRepo: env.scenarioRepo,
      id: "word_wolf_en", name: "Word Wolf", language: "en", sourceId: "word_wolf")
    try seedSimulation(simRepo: env.simRepo, id: "sim1", scenarioId: "word_wolf")

    await env.sut.load(scenarioId: "", deviceLanguage: "ja")

    #expect(env.sut.groups.first?.sectionName == "ワードウルフ")
  }

  @Test func loadAllPicksENVariantNameForSectionOnENDevice() async throws {
    let env = try makeResultsSUT()

    try seedScenario(
      scenarioRepo: env.scenarioRepo,
      id: "word_wolf", name: "ワードウルフ", language: "ja", sourceId: "word_wolf")
    try seedScenario(
      scenarioRepo: env.scenarioRepo,
      id: "word_wolf_en", name: "Word Wolf", language: "en", sourceId: "word_wolf")
    try seedSimulation(simRepo: env.simRepo, id: "sim1", scenarioId: "word_wolf_en")

    await env.sut.load(scenarioId: "", deviceLanguage: "en")

    #expect(env.sut.groups.first?.sectionName == "Word Wolf")
  }

  /// D6 line 217 fallback — device-locale variant absent in group,
  /// header falls back to the only available variant. Reproduces the
  /// "EN device, only JA preset installed" shape.
  @Test func loadAllFallsBackToFirstVariantWhenDeviceLocaleVariantMissing() async throws {
    let env = try makeResultsSUT()

    try seedScenario(
      scenarioRepo: env.scenarioRepo,
      id: "word_wolf", name: "ワードウルフ", language: "ja", sourceId: "word_wolf")
    try seedSimulation(simRepo: env.simRepo, id: "sim1", scenarioId: "word_wolf")

    await env.sut.load(scenarioId: "", deviceLanguage: "en")

    #expect(env.sut.groups.first?.sectionName == "ワードウルフ")
  }

  /// nil `sourceId` (user-authored, legacy, YAML import) → canonical
  /// key is the per-language `id`, solo group. No aggregation with
  /// other nil-sourceId scenarios.
  @Test func loadAllSolosUserAuthoredNilSourceIdScenarios() async throws {
    let env = try makeResultsSUT()

    try seedScenario(
      scenarioRepo: env.scenarioRepo,
      id: "user_a", name: "User A", language: "ja", sourceId: nil)
    try seedScenario(
      scenarioRepo: env.scenarioRepo,
      id: "user_b", name: "User B", language: "ja", sourceId: nil)
    try seedSimulation(simRepo: env.simRepo, id: "sim_a", scenarioId: "user_a")
    try seedSimulation(simRepo: env.simRepo, id: "sim_b", scenarioId: "user_b")

    await env.sut.load(scenarioId: "", deviceLanguage: "ja")

    #expect(env.sut.groups.count == 2)
    let canonicalKeys = Set(env.sut.groups.map(\.canonicalKey))
    #expect(canonicalKeys == ["user_a", "user_b"])
  }

  /// Both variants exist, only one has runs. Group still aggregates
  /// (header picks device-locale variant from all available variants);
  /// rows only include sims for variants that actually have runs.
  @Test func loadAllAggregatesGroupHeaderEvenWhenOnlyOneVariantHasRuns() async throws {
    let env = try makeResultsSUT()

    try seedScenario(
      scenarioRepo: env.scenarioRepo,
      id: "word_wolf", name: "ワードウルフ", language: "ja", sourceId: "word_wolf")
    try seedScenario(
      scenarioRepo: env.scenarioRepo,
      id: "word_wolf_en", name: "Word Wolf", language: "en", sourceId: "word_wolf")
    // Only the EN variant has runs.
    try seedSimulation(simRepo: env.simRepo, id: "sim_en_1", scenarioId: "word_wolf_en")

    await env.sut.load(scenarioId: "", deviceLanguage: "ja")

    #expect(env.sut.groups.count == 1)
    let group = try #require(env.sut.groups.first)
    // Section header still picks the JA variant (device locale).
    #expect(group.sectionName == "ワードウルフ")
    // Rows only include the EN sim.
    #expect(group.rows.count == 1)
    #expect(group.rows.first?.record.id == "sim_en_1")
    #expect(group.rows.first?.variantName == "Word Wolf")
  }

  /// Row `variantName` mirrors the simulation-time variant's
  /// `ScenarioRecord.name`. JA sim → JA name; EN sim → EN name, even
  /// in the same aggregated group.
  @Test func loadAllRowVariantNameMirrorsSimulationTimeName() async throws {
    let env = try makeResultsSUT()

    try seedScenario(
      scenarioRepo: env.scenarioRepo,
      id: "word_wolf", name: "ワードウルフ", language: "ja", sourceId: "word_wolf")
    try seedScenario(
      scenarioRepo: env.scenarioRepo,
      id: "word_wolf_en", name: "Word Wolf", language: "en", sourceId: "word_wolf")
    try seedSimulation(simRepo: env.simRepo, id: "sim_ja", scenarioId: "word_wolf")
    try seedSimulation(simRepo: env.simRepo, id: "sim_en", scenarioId: "word_wolf_en")

    await env.sut.load(scenarioId: "", deviceLanguage: "ja")

    let rows = try #require(env.sut.groups.first?.rows)
    let nameById = Dictionary(uniqueKeysWithValues: rows.map { ($0.record.id, $0.variantName) })
    #expect(nameById["sim_ja"] == "ワードウルフ")
    #expect(nameById["sim_en"] == "Word Wolf")
  }

  /// Orphan sim: `scenarioId` references a scenario absent from the
  /// `scenarios` table. Planted via `PRAGMA foreign_keys = OFF` direct
  /// write (production schema's `ON DELETE CASCADE` makes natural orphan
  /// creation impossible through repositories). Contract: the
  /// `loadHomeAggregated` `for scenario in scenarios` iteration never
  /// reaches the orphan, so it is silently invisible.
  @Test func loadAllSkipsOrphanedSimulation() async throws {
    let env = try makeResultsSUT()

    try seedScenario(
      scenarioRepo: env.scenarioRepo,
      id: "owned", name: "Owned", language: "ja", sourceId: nil)
    try seedSimulation(simRepo: env.simRepo, id: "sim_owned", scenarioId: "owned")

    // Plant orphan via direct DB write bypassing FK enforcement.
    // SQLite ignores `PRAGMA foreign_keys` inside a transaction, so use
    // `writeWithoutTransaction` to take the FK pragma in autocommit mode.
    try await env.db.dbWriter.writeWithoutTransaction { db in
      try db.execute(sql: "PRAGMA foreign_keys = OFF")
      try db.execute(
        sql: """
          INSERT INTO simulations
          (id, scenarioId, status, currentRound, currentPhaseIndex,
           stateJSON, configJSON, createdAt, updatedAt)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          "sim_orphan", "deleted_scenario",
          SimulationStatus.completed.rawValue,
          1, 0, "{}", nil, Date(), Date()
        ])
      try db.execute(sql: "PRAGMA foreign_keys = ON")
    }

    await env.sut.load(scenarioId: "", deviceLanguage: "ja")

    #expect(env.sut.groups.count == 1)
    let allRowIds = env.sut.groups.flatMap { $0.rows.map(\.record.id) }
    #expect(allRowIds == ["sim_owned"])
    #expect(!allRowIds.contains("sim_orphan"))
  }

  // MARK: - Detail entry-point — per-variant only

  /// The #392 cross-variant pin: a JA `Route.results(scenarioId:)` push
  /// from a JA `ScenarioDetailView` MUST surface only JA runs, even
  /// when an EN sibling has its own runs. Cross-variant aggregation is
  /// reserved for the Home entry-point.
  @Test func loadDetailDoesNotAggregateCrossLanguageSiblings() async throws {
    let env = try makeResultsSUT()

    try seedScenario(
      scenarioRepo: env.scenarioRepo,
      id: "word_wolf", name: "ワードウルフ", language: "ja", sourceId: "word_wolf")
    try seedScenario(
      scenarioRepo: env.scenarioRepo,
      id: "word_wolf_en", name: "Word Wolf", language: "en", sourceId: "word_wolf")
    try seedSimulation(simRepo: env.simRepo, id: "sim_en", scenarioId: "word_wolf_en")

    // Open Detail for the JA variant — EN sibling has runs but JA does not.
    await env.sut.load(scenarioId: "word_wolf")

    // No JA runs → empty groups. EN sibling's run is NOT visible from
    // this entry-point.
    #expect(env.sut.groups.isEmpty)
  }
}
