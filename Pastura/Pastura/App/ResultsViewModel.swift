import Foundation

/// ViewModel for past simulation results.
///
/// Two load modes — selected by the `scenarioId` argument:
///
/// - **Home** (`scenarioId == ""`): aggregates per-language scenario
///   variants under a single canonical group keyed by `sourceId ?? id`
///   (ADR-010 D4 cross-language aliasing, #392). Each canonical
///   group's section header is the device-locale variant's `name`,
///   falling back to the first available variant when the
///   device-language sibling isn't shipped (D6 line 217). Rows within
///   a group are sorted newest-first; row labels show the
///   simulation-time variant's `name` (un-translated) so the un-
///   translated conversation content stays internally consistent.
/// - **Detail** (`scenarioId != ""`): per-variant only — shows the one
///   scenario's simulations under a single group. Cross-variant
///   aggregation is intentionally Home-only so a user reading a JA
///   scenario's detail doesn't see EN sibling runs commingled. See
///   ``Route/results(scenarioId:)`` for the entry-point contract.
@Observable
final class ResultsViewModel {
  private(set) var groups: [ScenarioGroup] = []
  private(set) var isLoading = false
  private(set) var errorMessage: String?

  private let scenarioRepository: any ScenarioRepository
  private let simulationRepository: any SimulationRepository
  private let turnRepository: any TurnRepository

  /// One simulation row within a ``ScenarioGroup``.
  ///
  /// `variantName` is the simulation-time variant's display name —
  /// the `ScenarioRecord.name` of the variant whose `id` matches
  /// `record.scenarioId`. Kept un-translated (per-variant) so the
  /// label stays consistent with the run's recorded conversation
  /// content. When the variant is later renamed by the user, the
  /// label reflects the current name at view time (matching the
  /// section-name behavior in Phase 1).
  struct SimulationRow: Identifiable, Sendable {
    let record: SimulationRecord
    let variantName: String
    var id: String { record.id }
  }

  /// One section in the results list.
  ///
  /// `sectionName` is the device-locale variant's `name` for Home
  /// aggregation, or the single variant's `name` for Detail.
  /// `canonicalKey` is `sourceId ?? id` — distinct from per-language
  /// `id` only for aggregated groups.
  struct ScenarioGroup: Identifiable, Sendable {
    let sectionName: String
    let canonicalKey: String
    let rows: [SimulationRow]
    var id: String { canonicalKey }
  }

  init(
    scenarioRepository: any ScenarioRepository,
    simulationRepository: any SimulationRepository,
    turnRepository: any TurnRepository
  ) {
    self.scenarioRepository = scenarioRepository
    self.simulationRepository = simulationRepository
    self.turnRepository = turnRepository
  }

  /// Loads results into ``groups``. `scenarioId == ""` triggers Home
  /// aggregation; any non-empty id triggers Detail per-variant.
  ///
  /// - Parameter deviceLanguage: Overridable for tests. Production
  ///   call-sites use the default (``LocaleResolver/deviceDefault(preferredLocalizations:)``).
  func load(
    scenarioId: String,
    deviceLanguage: String = LocaleResolver.deviceDefault()
  ) async {
    isLoading = true
    errorMessage = nil

    do {
      if scenarioId.isEmpty {
        groups = try await loadHomeAggregated(deviceLanguage: deviceLanguage)
      } else {
        groups = try await loadDetailPerVariant(scenarioId: scenarioId)
      }
    } catch {
      errorMessage = String(localized: "Failed to load results: \(error.localizedDescription)")
    }

    isLoading = false
  }

  /// Home aggregation. Buckets `fetchAll()` by canonical key
  /// (`sourceId ?? id`) — mirrors ``HomeViewModel/presetsResolvedForLanguage(_:deviceLanguage:)``'s
  /// convention so the two consumers can migrate together when
  /// ADR-010 D6's eventual `ScenarioRepository.variants(of:)`
  /// primitive lands.
  ///
  /// Per-variant section-header selection uses ``ScenarioYAMLLanguage/parse(_:)``
  /// for the variant's `language`. Row variant names are taken from
  /// the already-fetched `ScenarioRecord.name` — no extra DB hit
  /// per row.
  private func loadHomeAggregated(deviceLanguage: String) async throws -> [ScenarioGroup] {
    let scenarios = try await offMain { [scenarioRepository] in
      try scenarioRepository.fetchAll()
    }

    let grouped = Dictionary(grouping: scenarios) { $0.sourceId ?? $0.id }

    var result: [ScenarioGroup] = []
    for (canonicalKey, variants) in grouped {
      // Pick the device-locale variant for the section header.
      // Falls back to first variant when the device-language sibling
      // isn't in the group (D6 line 217 "falls back to any available
      // variant if the device-default's variant is absent").
      let variantsWithLang = variants.map {
        (record: $0, lang: ScenarioYAMLLanguage.parse($0.yamlDefinition))
      }
      let headerVariant =
        variantsWithLang.first(where: { $0.lang == deviceLanguage })?.record
        ?? variantsWithLang.first?.record
      guard let headerVariant else { continue }

      // Fan-out: fetch sims per variant. Row's variantName uses the
      // already-fetched ScenarioRecord.name — no extra DB query per
      // row (avoids the Dependency-Rule violation of pushing the
      // lookup into ResultsView). N+1 trips are bounded: ≤ 2-3
      // variants × ≤ ~8-12 canonical groups in practice — when ADR-010
      // D6's `variants(of:)` ships, this loop can co-migrate to a
      // batched `fetchByScenarioIds([String])` if perf becomes a
      // concern.
      var rows: [SimulationRow] = []
      for variant in variants {
        let sims = try await offMain { [simulationRepository] in
          try simulationRepository.fetchByScenarioId(variant.id)
        }
        for sim in sims {
          rows.append(SimulationRow(record: sim, variantName: variant.name))
        }
      }

      guard !rows.isEmpty else { continue }
      rows.sort { $0.record.createdAt > $1.record.createdAt }
      result.append(
        ScenarioGroup(
          sectionName: headerVariant.name,
          canonicalKey: canonicalKey,
          rows: rows
        ))
    }

    // Surface orphaned runs (scenarioId == nil) whose source scenario was
    // deleted. The scenario-driven loop above can't reach them, and they
    // carry no live `sourceId`/`id`, so they group under a reserved canonical
    // key (NUL-prefixed) that cannot collide with a live group, and are
    // appended after the live groups regardless of name ordering.
    let orphanGroups = try await orphanedGroups()

    // Stable cross-group order keyed by canonical id so reloads
    // don't flicker. Orphaned (deleted-scenario) groups always sort last.
    return result.sorted { $0.canonicalKey < $1.canonicalKey }
      + orphanGroups.sorted { $0.sectionName < $1.sectionName }
  }

  /// Reserved canonical-key prefix for orphaned-run groups. The leading NUL
  /// guarantees no collision with a live scenario's `sourceId ?? id`.
  private static let orphanCanonicalKeyPrefix = "\u{0}orphan:"

  /// Builds groups for orphaned runs (`scenarioId IS NULL`), bucketed by the
  /// scenario name captured in each run's snapshot.
  private func orphanedGroups() async throws -> [ScenarioGroup] {
    let orphans = try await offMain { [simulationRepository] in
      try simulationRepository.fetchOrphaned()
    }
    guard !orphans.isEmpty else { return [] }

    let byName = Dictionary(grouping: orphans) {
      $0.scenarioNameSnapshot ?? String(localized: "Deleted scenario")
    }
    return byName.map { name, sims in
      let rows =
        sims
        .map { SimulationRow(record: $0, variantName: name) }
        .sorted { $0.record.createdAt > $1.record.createdAt }
      return ScenarioGroup(
        sectionName: name,
        canonicalKey: Self.orphanCanonicalKeyPrefix + name,
        rows: rows)
    }
  }

  /// Detail path: shows only this scenario's simulations. No cross-
  /// variant aggregation by design — a user on a JA `ScenarioDetailView`
  /// sees only JA runs even when an EN sibling exists. Cross-variant
  /// browsing is reserved for the Home entry point.
  private func loadDetailPerVariant(scenarioId: String) async throws -> [ScenarioGroup] {
    let scenario = try await offMain { [scenarioRepository] in
      try scenarioRepository.fetchById(scenarioId)
    }
    let sims = try await offMain { [simulationRepository] in
      try simulationRepository.fetchByScenarioId(scenarioId)
    }
    guard !sims.isEmpty else { return [] }

    let name = scenario?.name ?? String(localized: "Unknown")
    let canonical = scenario?.sourceId ?? scenarioId

    let rows =
      sims
      .map { SimulationRow(record: $0, variantName: name) }
      .sorted { $0.record.createdAt > $1.record.createdAt }

    return [
      ScenarioGroup(sectionName: name, canonicalKey: canonical, rows: rows)
    ]
  }

  /// Loads all turn records for a simulation (for result detail replay).
  func loadTurns(simulationId: String) async -> [TurnRecord] {
    do {
      return try await offMain { [turnRepository] in
        try turnRepository.fetchBySimulationId(simulationId)
      }
    } catch {
      errorMessage = String(localized: "Failed to load turns: \(error.localizedDescription)")
      return []
    }
  }

  /// Decodes the SimulationState from a record's stateJSON.
  func decodeState(from record: SimulationRecord) -> SimulationState? {
    guard let data = record.stateJSON.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(SimulationState.self, from: data)
  }
}
