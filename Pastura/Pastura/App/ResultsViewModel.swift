import Foundation

/// ViewModel for past simulation results.
///
/// Two load modes — selected by the ``ResultsScope`` argument:
///
/// - **Aggregate** (``ResultsScope/aggregate``): a paginated global recency
///   window over **all** runs (#586). Runs are fetched newest-first one keyset
///   page at a time and bucketed into canonical groups keyed by `sourceId ?? id`
///   (ADR-010 D4 cross-language aliasing, #392). Each canonical group's section
///   header is the device-locale variant's `name`, falling back to the first
///   available variant when the device-language sibling isn't shipped. Rows
///   within a group stay newest-first; row labels show the simulation-time
///   variant's `name` (un-translated). Groups are ordered by their most-recent
///   run, so loading an older page can move an already-shown group up the list,
///   and NULL-`scenarioId` orphan runs interleave by recency rather than always
///   sorting last. An optional free-text scenario-name filter narrows the
///   window (pushed into SQL so it reaches un-loaded runs).
/// - **Detail** (``ResultsScope/scenario(_:)``): per-variant only — shows
///   the one scenario's simulations under a single group. Cross-variant
///   aggregation is intentionally limited to ``ResultsScope/aggregate`` so
///   a user reading a JA scenario's detail doesn't see EN sibling runs
///   commingled. See ``Route/results(scenarioId:)`` for the entry-point contract.
@Observable
final class ResultsViewModel {
  private(set) var groups: [ScenarioGroup] = []
  private(set) var isLoading = false
  /// `true` while a ``loadMore()`` page fetch is in flight — drives the
  /// load-more affordance's spinner and guards against re-entrant fetches.
  private(set) var isLoadingMore = false
  /// `true` when more aggregate pages may exist (the last raw page filled the
  /// limit). Always `false` for the un-paginated Detail scope.
  private(set) var hasMore = false
  private(set) var errorMessage: String?

  private let scenarioRepository: any ScenarioRepository
  private let simulationRepository: any SimulationRepository
  private let turnRepository: any TurnRepository
  /// Page size for the aggregate keyset window. Injectable so tests can drive
  /// multi-page behavior without seeding hundreds of runs.
  private let pageSize: Int

  // Aggregate pagination state.
  private var nameQuery: String = ""
  private var deviceLanguage: String = LocaleResolver.deviceDefault()
  /// Accumulated **visible** light items across loaded pages (dangling-
  /// scenarioId rows already dropped), global newest-first.
  private var loadedRuns: [PastRunListItem] = []
  /// Keyset cursor = the last **raw** row of the last fetched page (regardless
  /// of visibility), so the next page resumes correctly even past filtered rows.
  private var cursor: SimulationPageCursor?
  /// Cumulative count of **raw** rows fetched — the depth a reappear-refresh
  /// re-reads from the top so the user's scroll position survives.
  private var loadedRawCount = 0
  /// Monotonic load-cycle stamp. Bumped whenever the window is reset
  /// (`reloadAggregate` / `applyFilter` / `refreshAggregatePreservingDepth`).
  /// An in-flight `loadMore`/drain captures the stamp and discards a page whose
  /// stamp is stale — so a filter change (or reappear-refresh) that lands while
  /// the auto-firing load-more sentinel is mid-fetch can't fold an
  /// old-query/old-cursor page into the freshly-reset window.
  private var loadGeneration = 0
  /// Live scenarios by id — bounded (small rows), kept for canonical-key
  /// bucketing and device-locale header resolution.
  private var scenarioById: [String: ScenarioRecord] = [:]
  /// Precomputed device-locale section header per live canonical key.
  private var headerNameByCanonicalKey: [String: String] = [:]

  /// One simulation row within a ``ScenarioGroup``.
  ///
  /// `variantName` is the simulation-time variant's display name — the
  /// `ScenarioRecord.name` of the variant whose `id` matches the run's
  /// `scenarioId`. Kept un-translated (per-variant) so the label stays
  /// consistent with the run's recorded conversation content.
  struct SimulationRow: Identifiable, Sendable {
    let item: PastRunListItem
    let variantName: String
    var id: String { item.id }
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
    turnRepository: any TurnRepository,
    pageSize: Int = 50
  ) {
    self.scenarioRepository = scenarioRepository
    self.simulationRepository = simulationRepository
    self.turnRepository = turnRepository
    self.pageSize = pageSize
  }

  /// Loads results into ``groups``. ``ResultsScope/aggregate`` resets the
  /// keyset window and loads its first visible page; ``ResultsScope/scenario(_:)``
  /// loads the one scenario's runs (un-paginated).
  ///
  /// - Parameters:
  ///   - deviceLanguage: Overridable for tests. Production call-sites use the
  ///     default (``LocaleResolver/deviceDefault(preferredLocalizations:)``).
  ///   - showLoading: When `false`, the `isLoading` spinner state is left
  ///     untouched so the call refreshes ``groups`` in place without flashing
  ///     the full-screen `ProgressView` (the Detail reappear-refresh path).
  func load(
    scope: ResultsScope,
    deviceLanguage: String = LocaleResolver.deviceDefault(),
    showLoading: Bool = true
  ) async {
    if showLoading { isLoading = true }
    errorMessage = nil

    do {
      switch scope {
      case .aggregate:
        self.deviceLanguage = deviceLanguage
        try await reloadAggregate()
      case .scenario(let scenarioId):
        hasMore = false
        try await loadDetailPerVariant(scenarioId: scenarioId)
      }
    } catch {
      errorMessage = Self.failureMessage(error)
    }

    if showLoading { isLoading = false }
  }

  /// Loads the next visible page of the aggregate window. No-op when no more
  /// pages exist or a fetch is already in flight. If a window reset (filter /
  /// refresh) supersedes this call mid-fetch, the stale page is discarded.
  func loadMore() async {
    guard hasMore, !isLoadingMore else { return }
    isLoadingMore = true
    let generation = loadGeneration
    do {
      try await drainUntilVisibleProgress(generation: generation)
      if generation == loadGeneration { rebuildGroups() }
    } catch {
      // Suppress an error from a page that a window reset already superseded —
      // it no longer corresponds to the live window.
      if generation == loadGeneration { errorMessage = Self.failureMessage(error) }
    }
    isLoadingMore = false
  }

  /// Applies (or clears) the scenario-name filter and reloads the aggregate
  /// window from the top. No spinner — the prior groups stay visible until the
  /// new page resolves. No-op when the query is unchanged.
  func applyFilter(
    _ query: String,
    deviceLanguage: String = LocaleResolver.deviceDefault()
  ) async {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed != nameQuery else { return }
    nameQuery = trimmed
    self.deviceLanguage = deviceLanguage
    errorMessage = nil
    do {
      try await reloadAggregate()
    } catch {
      errorMessage = Self.failureMessage(error)
    }
  }

  /// Re-fetches in place when the list reappears (e.g. after a per-run delete
  /// pops back). For aggregate, the currently-loaded depth is re-read from the
  /// top so a deleted run drops out without resetting the user's scroll
  /// position (#586 incremental refresh of the #545 reappear-refresh). For
  /// detail, a silent full reload.
  func refreshOnReappear(
    scope: ResultsScope,
    deviceLanguage: String = LocaleResolver.deviceDefault()
  ) async {
    errorMessage = nil
    switch scope {
    case .aggregate:
      self.deviceLanguage = deviceLanguage
      do {
        try await refreshAggregatePreservingDepth()
      } catch {
        errorMessage = Self.failureMessage(error)
      }
    case .scenario:
      await load(scope: scope, deviceLanguage: deviceLanguage, showLoading: false)
    }
  }

  // MARK: - Aggregate (paginated recency window)

  /// Reserved canonical-key prefix for orphaned-run groups. The leading NUL
  /// guarantees no collision with a live scenario's `sourceId ?? id`.
  private static let orphanCanonicalKeyPrefix = "\u{0}orphan:"

  /// Resets the window and loads the first visible page.
  private func reloadAggregate() async throws {
    loadGeneration += 1
    let generation = loadGeneration
    try await refreshScenarioIndex()
    guard generation == loadGeneration else { return }
    loadedRuns = []
    cursor = nil
    loadedRawCount = 0
    hasMore = true
    try await drainUntilVisibleProgress(generation: generation)
    guard generation == loadGeneration else { return }
    rebuildGroups()
  }

  /// Fetches keyset pages until at least one new **visible** row is appended or
  /// no pages remain. A page made entirely of dangling-scenarioId (invisible)
  /// rows would otherwise stall the load-more affordance, so such pages are
  /// drained internally rather than surfaced one-at-a-time (#586 auto-drain).
  private func drainUntilVisibleProgress(generation: Int) async throws {
    let startCount = loadedRuns.count
    while loadedRuns.count == startCount && hasMore {
      let query = nameQuery.isEmpty ? nil : nameQuery
      let cursorSnapshot = cursor
      let limit = pageSize
      let rawPage = try await offMain { [simulationRepository] in
        try simulationRepository.fetchRecentRunPage(
          nameQuery: query, before: cursorSnapshot, limit: limit)
      }
      // A window reset (filter / refresh) landed during the fetch — this page
      // was read against a now-stale query/cursor, so drop it rather than fold
      // it into the reset window.
      guard generation == loadGeneration else { return }
      ingest(rawPage)
    }
  }

  /// Folds a freshly-fetched raw page into the window: advances `hasMore` and
  /// the keyset `cursor` off the **raw** row count / last raw row, and appends
  /// only the visible (non-dangling) rows to ``loadedRuns``.
  private func ingest(_ rawPage: [PastRunListItem]) {
    loadedRawCount += rawPage.count
    hasMore = rawPage.count == pageSize
    if let last = rawPage.last {
      cursor = SimulationPageCursor(createdAt: last.createdAt, id: last.id)
    }
    loadedRuns += rawPage.filter { bucket(for: $0) != nil }
  }

  /// Re-reads the loaded depth from the top, recomputing `cursor` + `hasMore`
  /// from the re-fetched window. Keyset tolerates a cursor that points at a
  /// since-deleted row (it is still a valid `< ` boundary), so a delete between
  /// pages cannot corrupt a subsequent ``loadMore()``. The re-read depth is
  /// unbounded by design (it preserves the user's scroll position); memory
  /// stays light because the repository still projects `stateJSON` away per
  /// row — only the top-3-score CPU cost scales with depth on this path.
  private func refreshAggregatePreservingDepth() async throws {
    loadGeneration += 1
    let generation = loadGeneration
    try await refreshScenarioIndex()
    guard generation == loadGeneration else { return }
    let depth = max(loadedRawCount, pageSize)
    let query = nameQuery.isEmpty ? nil : nameQuery
    let rawPage = try await offMain { [simulationRepository] in
      try simulationRepository.fetchRecentRunPage(nameQuery: query, before: nil, limit: depth)
    }
    guard generation == loadGeneration else { return }
    loadedRawCount = rawPage.count
    hasMore = rawPage.count == depth
    cursor = rawPage.last.map { SimulationPageCursor(createdAt: $0.createdAt, id: $0.id) }
    loadedRuns = rawPage.filter { bucket(for: $0) != nil }
    rebuildGroups()
  }

  /// Reloads the bounded scenario index + device-locale header map. Scenario
  /// rows are small (no `stateJSON`); the heavy run rows page in lazily.
  private func refreshScenarioIndex() async throws {
    let scenarios = try await offMain { [scenarioRepository] in
      try scenarioRepository.fetchAll()
    }
    scenarioById = Dictionary(
      scenarios.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    let grouped = Dictionary(grouping: scenarios) { $0.sourceId ?? $0.id }
    var headers: [String: String] = [:]
    for (canonicalKey, variants) in grouped {
      // Pick the device-locale variant for the section header, falling back to
      // the first available variant when the device-language sibling is absent.
      let variantsWithLang = variants.map {
        (record: $0, lang: ScenarioYAMLLanguage.parse($0.yamlDefinition))
      }
      let headerVariant =
        variantsWithLang.first(where: { $0.lang == deviceLanguage })?.record
        ?? variantsWithLang.first?.record
      if let headerVariant { headers[canonicalKey] = headerVariant.name }
    }
    headerNameByCanonicalKey = headers
  }

  /// Buckets a run to its canonical group + per-variant label. Returns `nil`
  /// for a **dangling** run (non-null `scenarioId` absent from the live index)
  /// so it stays invisible — preserving the prior structural contract that
  /// dangling runs never surface (the new direct-table query would otherwise
  /// return them).
  private func bucket(for item: PastRunListItem) -> (key: String, variantName: String)? {
    if let scenarioId = item.scenarioId {
      guard let scenario = scenarioById[scenarioId] else { return nil }
      return (scenario.sourceId ?? scenario.id, scenario.name)
    }
    // NULL scenarioId — a deleted-scenario orphan; key off the captured
    // snapshot under the reserved prefix so it cannot merge with a live group.
    let snapshot = item.scenarioNameSnapshot
    let name = snapshot ?? String(localized: "Deleted scenario")
    let keySuffix = snapshot ?? "\u{0}unnamed"
    return (Self.orphanCanonicalKeyPrefix + keySuffix, name)
  }

  /// Re-buckets the full accumulated visible window into canonical groups.
  /// Groups appear in the recency order their most-recent run was first seen
  /// (``loadedRuns`` is global newest-first), so older pages extend existing
  /// groups downward and only introduce new groups below.
  private func rebuildGroups() {
    var order: [String] = []
    var rowsByKey: [String: [SimulationRow]] = [:]
    for item in loadedRuns {
      guard let bucket = bucket(for: item) else { continue }
      if rowsByKey[bucket.key] == nil {
        order.append(bucket.key)
        rowsByKey[bucket.key] = []
      }
      rowsByKey[bucket.key]?.append(SimulationRow(item: item, variantName: bucket.variantName))
    }
    groups = order.compactMap { key in
      guard let rows = rowsByKey[key], !rows.isEmpty else { return nil }
      let header = headerNameByCanonicalKey[key] ?? rows[0].variantName
      return ScenarioGroup(sectionName: header, canonicalKey: key, rows: rows)
    }
  }

  // MARK: - Detail (per-variant, un-paginated)

  /// Detail path: shows only this scenario's simulations as lightweight rows.
  /// No cross-variant aggregation by design — a user on a JA `ScenarioDetailView`
  /// sees only JA runs even when an EN sibling exists.
  private func loadDetailPerVariant(scenarioId: String) async throws {
    let scenario = try await offMain { [scenarioRepository] in
      try scenarioRepository.fetchById(scenarioId)
    }
    let items = try await offMain { [simulationRepository] in
      try simulationRepository.fetchRunList(scenarioId: scenarioId)
    }
    guard !items.isEmpty else {
      groups = []
      return
    }

    let name = scenario?.name ?? String(localized: "Unknown")
    let canonical = scenario?.sourceId ?? scenarioId
    // `fetchRunList` already returns newest-first; no re-sort needed.
    let rows = items.map { SimulationRow(item: $0, variantName: name) }
    groups = [ScenarioGroup(sectionName: name, canonicalKey: canonical, rows: rows)]
  }

  // MARK: - Turns

  /// Loads all turn records for a simulation (for result detail replay).
  func loadTurns(simulationId: String) async -> [TurnRecord] {
    do {
      return try await offMain { [turnRepository] in
        try turnRepository.fetchBySimulationId(simulationId)
      }
    } catch {
      errorMessage = String(
        format: String(localized: "Failed to load turns: %@"), error.localizedDescription)
      return []
    }
  }

  private static func failureMessage(_ error: Error) -> String {
    String(
      format: String(localized: "Failed to load results: %@"), error.localizedDescription)
  }
}
