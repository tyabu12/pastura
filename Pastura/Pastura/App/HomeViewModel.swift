import Foundation

/// Display model for the Home "paused scenario" resume card (ADR-016 P2).
///
/// Display-only in P2 — the resume action itself (DB rehydration of the
/// paused run) lands in P3. Built from the most-recent paused
/// `SimulationRecord` joined with its live scenario name (snapshot fallback
/// for orphaned runs) and the cached ``ScenarioRowMetadata``.
nonisolated struct PausedScenarioSummary: Equatable, Identifiable {
  /// The paused run's id — also the card's stable identity.
  let runId: String
  /// The source scenario's id, or nil when the scenario was deleted
  /// (orphaned run). Carried for the P3 resume hand-off; in P2 only the
  /// snapshot-resolved ``name`` is shown.
  let scenarioId: String?
  let name: String
  let agentCount: Int?
  let rounds: Int?
  let currentRound: Int
  let description: String?

  var id: String { runId }
}

/// ViewModel for the home screen scenario list.
///
/// Fetches scenarios from the repository and splits them into presets
/// and user-created groups. Supports pull-to-refresh and deletion.
/// Also exposes a set of scenario ids with a pending gallery update,
/// populated from the cached gallery index.
///
/// **Preset variant collapsing (ADR-010 D6).** Bundled presets ship in
/// per-language sibling files (Step D); this VM surfaces ONE row per
/// canonical `sourceId`, picking the device-language variant via
/// ``LocaleResolver``. When the device-language variant is absent the
/// picker falls back to any available variant (D6 line 217). User-
/// authored scenarios are not collapsed — only bundled presets share
/// a canonical id across languages.
@Observable
final class HomeViewModel {
  private(set) var presets: [ScenarioRecord] = []
  private(set) var userScenarios: [ScenarioRecord] = []
  private(set) var isLoading = false
  private(set) var errorMessage: String?

  /// Resolved per-row display metadata, keyed by ``ScenarioRecord/id``.
  /// Rebuilt on every ``loadScenarios()`` from the collapsed (ADR-010 D6)
  /// preset set plus the user scenarios. A row whose YAML fails to parse
  /// gets a name-only ``ScenarioRowMetadata`` and **never** sets
  /// ``errorMessage`` — one broken preset must not blank the whole list.
  /// The consuming View (row secondary line, ADR-016 D3) lands in P2.
  private(set) var rowMetadata: [String: ScenarioRowMetadata] = [:]

  /// Completed-run count per displayed row, keyed by ``ScenarioRecord/id``.
  /// Aggregated across ADR-010 D6 language variants by `sourceId`, so a row
  /// shows the total "観察回数" across every variant of its canonical
  /// scenario (a run of the EN variant still counts on the displayed JA row).
  /// Empty when no ``SimulationRepository`` is injected (fixture tests that
  /// don't exercise counts). Recomputed on every ``loadScenarios()``.
  private(set) var observationCounts: [String: Int] = [:]

  /// `ScenarioRecord.id`s for rows whose `sourceHash` differs from the
  /// cached gallery's `yaml_sha256`. Empty when no cache exists. The view
  /// reads this as an inline badge on each row.
  private(set) var galleryUpdateBadges: Set<String> = []

  /// The most-recent paused run surfaced as the Home "resume" card, or nil
  /// when nothing is paused (card hidden — d3-without). Recomputed on every
  /// ``loadScenarios()``; nil unless a ``SimulationRepository`` is injected.
  /// Display-only in P2 — the resume action lands in P3 (ADR-016 §4).
  private(set) var pausedSummary: PausedScenarioSummary?

  private let repository: any ScenarioRepository

  /// Optional — supplies completed-run counts for ``observationCounts``.
  /// Defaults to `nil` so existing fixture tests keep their two-arg-free
  /// construction; a pure-data repository has no test-isolation hazard
  /// (cf. `.claude/rules/swiftui-traps.md` § "inject at View boundary",
  /// which targets *side-effecting* services, not immutable repositories).
  private let simulationRepository: (any SimulationRepository)?

  /// In-process parse memo keyed by `id` + `updatedAt`. See
  /// ``ScenarioRowMetadataCache`` for the keying / invalidation contract.
  private var metadataCache = ScenarioRowMetadataCache()

  init(
    repository: any ScenarioRepository,
    simulationRepository: (any SimulationRepository)? = nil
  ) {
    self.repository = repository
    self.simulationRepository = simulationRepository
  }

  func loadScenarios() async {
    isLoading = true
    errorMessage = nil
    // Reset so the "recomputed on every load" contract holds even when no
    // SimulationRepository is injected (the recompute below is gated on it).
    observationCounts = [:]
    pausedSummary = nil

    do {
      let all = try await offMain { [repository] in
        try repository.fetchAll()
      }
      let allPresets = all.filter(\.isPreset)
      presets = Self.presetsResolvedForLanguage(
        allPresets, deviceLanguage: LocaleResolver.deviceDefault())
      userScenarios = all.filter { !$0.isPreset }
      // Resolve metadata on the *collapsed* (D6) preset rows + user rows —
      // never the pre-collapse variant set — so the metadata keys stay a
      // subset of the displayed row ids and language/variant selection is
      // never re-derived from the heavy parse (ADR-010 D6 non-interference).
      let loader = ScenarioLoader()
      rowMetadata = metadataCache.resolve(presets + userScenarios) { record in
        Self.parseRowMetadata(record, loader: loader)
      }
      // Observation counts are display garnish — a failed count read must not
      // blank the list (try?), so it's kept out of the batch error path.
      if let simulationRepository {
        let completed =
          (try? await offMain { [simulationRepository] in
            try simulationRepository.completedRunCountsByScenarioId()
          }) ?? [:]
        observationCounts = Self.aggregateObservationCounts(
          completedByScenarioId: completed,
          scenarios: all,
          displayedRows: presets + userScenarios)
        // Paused runs feed the "resume" card (ADR-016 P2, display-only —
        // rehydration is P3). Same garnish-not-critical posture as counts:
        // a failed read swallows to [] and the card simply hides, never
        // blanking the list. `makePausedSummary` re-ranks by `updatedAt`
        // (most recently interrupted), not the fetch's `createdAt` order.
        let pausedRuns =
          (try? await offMain { [simulationRepository] in
            try simulationRepository.fetchByStatus(.paused)
          }) ?? []
        pausedSummary = Self.makePausedSummary(
          pausedRuns: pausedRuns,
          scenariosById: Dictionary(
            all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
          rowMetadata: rowMetadata)
      }
    } catch {
      errorMessage = String(
        format: String(localized: "Failed to load scenarios: %@"), error.localizedDescription)
    }

    isLoading = false
  }

  /// Builds the "resume" card model from `pausedRuns`: picks the most
  /// recently *interrupted* run — the one with the latest `updatedAt`, since
  /// a pause is the run's last write — and resolves its display name +
  /// metadata. `fetchByStatus` orders by `createdAt`, so the pick re-ranks
  /// by `updatedAt` rather than taking `.first` (a run created earlier but
  /// paused more recently should win). Returns nil when nothing is paused or
  /// the name can't be resolved (card hidden).
  ///
  /// Name resolution prefers the live scenario (`scenariosById`), falling
  /// back to the run's `scenarioNameSnapshot` for orphaned runs whose
  /// scenario was deleted. Metadata (`agentCount` / `rounds` / `description`)
  /// comes from the displayed-row ``rowMetadata`; absent for a paused run on
  /// a non-displayed preset variant, in which case the card degrades to
  /// name-only — same posture as a name-only row.
  nonisolated static func makePausedSummary(
    pausedRuns: [SimulationRecord],
    scenariosById: [String: ScenarioRecord],
    rowMetadata: [String: ScenarioRowMetadata]
  ) -> PausedScenarioSummary? {
    guard let run = pausedRuns.max(by: { $0.updatedAt < $1.updatedAt }) else { return nil }
    let metadata = run.scenarioId.flatMap { rowMetadata[$0] }
    let liveName = run.scenarioId.flatMap { scenariosById[$0]?.name }
    guard let name = liveName ?? run.scenarioNameSnapshot, !name.isEmpty else {
      return nil
    }
    return PausedScenarioSummary(
      runId: run.id,
      scenarioId: run.scenarioId,
      name: name,
      agentCount: metadata?.agentCount,
      rounds: metadata?.rounds,
      currentRound: run.currentRound,
      description: metadata?.description)
  }

  /// ADR-010 D6 variant collapsing: groups bundled presets by canonical
  /// `sourceId` (legacy rows with `sourceId == nil` group by `id`),
  /// then surfaces the device-language variant per group. Falls back to
  /// any available variant when the device-language sibling isn't
  /// shipped (D6 line 217 "falls back to any available variant if the
  /// device-default's variant is absent").
  ///
  /// Per-variant language read goes through ``ScenarioYAMLLanguage/parse(_:)``
  /// (light top-level Yams parse, `"ja"` fallback on malformed YAML —
  /// see that type's doc-comment for the failure-mode contract). The
  /// same helper is reused by ``ResultsViewModel`` for cross-language
  /// section-header selection (#392), so when ADR-010 D6's eventual
  /// `ScenarioRepository.variants(of:)` lands, both consumers can
  /// migrate together.
  internal static func presetsResolvedForLanguage(
    _ presets: [ScenarioRecord],
    deviceLanguage: String
  ) -> [ScenarioRecord] {
    let grouped = Dictionary(grouping: presets) { $0.sourceId ?? $0.id }

    var resolved: [ScenarioRecord] = []
    for (_, variants) in grouped {
      let withLang = variants.map {
        (record: $0, lang: ScenarioYAMLLanguage.parse($0.yamlDefinition))
      }
      let picked =
        withLang.first(where: { $0.lang == deviceLanguage })?.record
        ?? withLang.first?.record
      if let picked { resolved.append(picked) }
    }

    // Stable order — sort by canonical key so reloads don't flicker.
    return resolved.sorted { ($0.sourceId ?? $0.id) < ($1.sourceId ?? $1.id) }
  }

  /// Parses a record's stored YAML into ``ScenarioRowMetadata`` via the full
  /// ``ScenarioLoader`` schema gate. On any parse / validation failure the row
  /// **degrades to name-only** — the `try?` keeps the failure local so it can
  /// never reach the batch ``errorMessage`` path in ``loadScenarios()`` (one
  /// broken preset must not blank the whole list). This is the heavy parse the
  /// ``ScenarioRowMetadataCache`` memoizes; the light ``ScenarioYAMLLanguage``
  /// parse used for D6 variant selection is unaffected.
  internal static func parseRowMetadata(
    _ record: ScenarioRecord, loader: ScenarioLoader
  ) -> ScenarioRowMetadata {
    guard let scenario = try? loader.load(yaml: record.yamlDefinition) else {
      return ScenarioRowMetadata(name: record.name)
    }
    return ScenarioRowMetadata(
      name: record.name,
      agentCount: scenario.agentCount,
      rounds: scenario.rounds,
      description: scenario.description
    )
  }

  /// Projects per-variant completed-run counts onto the displayed (collapsed)
  /// rows, summing across ADR-010 D6 language variants by canonical key
  /// (`sourceId ?? id`). A run recorded against the EN variant therefore
  /// counts on the displayed JA row, matching ADR-010 D4's cross-variant
  /// aggregation intent. Every displayed row gets an entry (0 when it has no
  /// completed runs).
  internal static func aggregateObservationCounts(
    completedByScenarioId: [String: Int],
    scenarios: [ScenarioRecord],
    displayedRows: [ScenarioRecord]
  ) -> [String: Int] {
    // Each concrete scenario id → its canonical D6 key.
    let canonicalKey = Dictionary(
      scenarios.map { ($0.id, $0.sourceId ?? $0.id) },
      uniquingKeysWith: { first, _ in first })

    // Roll per-variant counts up to the canonical key.
    var byCanonical: [String: Int] = [:]
    for (scenarioId, count) in completedByScenarioId {
      guard let key = canonicalKey[scenarioId] else { continue }
      byCanonical[key, default: 0] += count
    }

    // Project onto the displayed rows by their own canonical key.
    var result: [String: Int] = [:]
    for row in displayedRows {
      result[row.id] = byCanonical[row.sourceId ?? row.id] ?? 0
    }
    return result
  }

  func deleteScenario(_ id: String) async {
    do {
      try await offMain { [repository] in
        try repository.delete(id)
      }
      userScenarios.removeAll { $0.id == id }
    } catch {
      errorMessage = String(
        format: String(localized: "Failed to delete scenario: %@"), error.localizedDescription)
    }
  }

  /// Recomputes `galleryUpdateBadges` by comparing each locally-stored
  /// gallery row's `sourceHash` with the hash from the cached gallery
  /// index. Non-gallery rows and rows lacking a `sourceId` are ignored.
  /// Silent no-op when no cached index is available.
  func refreshGalleryUpdateBadges(using service: any GalleryService) async {
    // Cache read is file I/O — dispatch off MainActor to avoid blocking
    // list rendering on a synchronous disk read. Double-optional: inner
    // nil = no cache file, outer nil = offMain threw.
    let fetched = try? await offMain { [service] in try service.loadCachedIndex() }
    guard let cached = fetched.flatMap({ $0 }) else {
      galleryUpdateBadges = []
      return
    }
    let hashBySourceId = Dictionary(
      uniqueKeysWithValues: cached.scenarios.map { ($0.id, $0.yamlSHA256) })
    var ids: Set<String> = []
    // Only `userScenarios` can be gallery-sourced — presets are bundled.
    for record in userScenarios
    where record.sourceType == ScenarioSourceType.gallery {
      guard
        let sourceId = record.sourceId,
        let galleryHash = hashBySourceId[sourceId]
      else { continue }
      if record.sourceHash != galleryHash {
        ids.insert(record.id)
      }
    }
    galleryUpdateBadges = ids
  }
}
