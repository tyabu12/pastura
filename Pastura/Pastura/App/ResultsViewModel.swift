import Foundation

/// ViewModel for past simulation results.
///
/// Two load modes — selected by the ``ResultsScope`` argument:
///
/// - **Aggregate** (``ResultsScope/aggregate``): the History-tab root — a
///   paginated global recency window over **all** runs (#586), grouped into
///   **date sections** (Today / This Week / This Month / older "Month [Year]"
///   headings, Home redesign P5). Runs are fetched newest-first one keyset page
///   at a time; each run is its own row (no scenario-level collapsing). Row
///   labels show the simulation-time variant's `name` (un-translated), falling
///   back to the captured ``PastRunListItem/scenarioNameSnapshot`` for a run
///   whose scenario was deleted. ``totalRunCount`` backs the screen-title
///   "N records" subtitle. An optional free-text scenario-name filter narrows
///   the window (pushed into SQL so it reaches un-loaded runs).
/// - **Detail** (``ResultsScope/scenario(_:)``): per-variant only — shows the
///   one scenario's simulations under a single section. A user reading a JA
///   scenario's detail doesn't see EN sibling runs commingled. See
///   ``Route/results(scenarioId:)`` for the entry-point contract.
///
/// History note: the aggregate path previously collapsed same-scenario
/// language siblings into one section (ADR-010 D4 / #392). P5 replaced that
/// scenario-keyed grouping with date sections; D4's `sourceId` canonical link
/// still backs the **detail** path and the data model, but the History-tab
/// cross-language consumer was retired here.
@Observable
final class ResultsViewModel {
  private(set) var sections: [ResultSection] = []
  /// Total runs matching the active filter — backs the aggregate screen-title
  /// "N records" subtitle. Equals the number of rows the list renders (P5
  /// shows every run, so no count/list divergence). Unused by the detail path.
  private(set) var totalRunCount = 0
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
  /// Clock + calendar for date bucketing — injectable so day/week/month
  /// boundaries are deterministic in tests (production uses the live clock and
  /// `Calendar.current`).
  private let now: () -> Date
  private let calendar: Calendar

  // Aggregate pagination state.
  private var nameQuery: String = ""
  /// Accumulated light items across loaded pages, global newest-first. P5 keeps
  /// every run (no dangling-scenarioId drop), so this is the full window.
  private var loadedRuns: [PastRunListItem] = []
  /// Keyset cursor = the last row of the last fetched page, so the next page
  /// resumes correctly on the composite `(createdAt DESC, id DESC)` order.
  private var cursor: SimulationPageCursor?
  /// Cumulative count of rows fetched — the depth a reappear-refresh re-reads
  /// from the top so the user's scroll position survives.
  private var loadedRawCount = 0
  /// Monotonic load-cycle stamp. Bumped whenever the window is reset
  /// (`reloadAggregate` / `applyFilter` / `refreshAggregatePreservingDepth`).
  /// An in-flight `loadMore` captures the stamp and discards a page whose stamp
  /// is stale — so a filter change (or reappear-refresh) that lands while the
  /// auto-firing load-more sentinel is mid-fetch can't fold an
  /// old-query/old-cursor page into the freshly-reset window.
  private var loadGeneration = 0
  /// Live scenarios by id — bounded (small rows), kept to resolve each run's
  /// per-variant row label. The scenario set is invariant while typing a
  /// filter, so the index is built once and reused across keystrokes (#678).
  private var scenarioById: [String: ScenarioSummary] = [:]
  /// `true` once ``scenarioById`` has been built — the filter path reuses it
  /// rather than re-`fetchAllSummaries()`-ing per keystroke.
  private var scenarioIndexBuilt = false
  /// Resolves + memoizes each row's `agentCount` / total-rounds `N` from the
  /// run's scenario YAML (snapshot-first). See ``RunScenarioMetaResolver``.
  private var metaResolver = RunScenarioMetaResolver()

  // `SimulationRow` / `ResultSection` (the list's value types) live in
  // `ResultsViewModel+Rows.swift`.

  init(
    scenarioRepository: any ScenarioRepository,
    simulationRepository: any SimulationRepository,
    turnRepository: any TurnRepository,
    pageSize: Int = 50,
    now: @escaping () -> Date = { Date() },
    calendar: Calendar = .current
  ) {
    self.scenarioRepository = scenarioRepository
    self.simulationRepository = simulationRepository
    self.turnRepository = turnRepository
    self.pageSize = pageSize
    self.now = now
    self.calendar = calendar
  }

  /// Loads results into ``sections``. ``ResultsScope/aggregate`` resets the
  /// keyset window and loads its first page; ``ResultsScope/scenario(_:)``
  /// loads the one scenario's runs (un-paginated).
  ///
  /// - Parameter showLoading: When `false`, the `isLoading` spinner state is
  ///   left untouched so the call refreshes ``sections`` in place without
  ///   flashing the full-screen `ProgressView` (the Detail reappear path).
  func load(scope: ResultsScope, showLoading: Bool = true) async {
    if showLoading { isLoading = true }
    errorMessage = nil

    do {
      switch scope {
      case .aggregate:
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

  /// Loads the next page of the aggregate window. No-op when no more pages
  /// exist or a fetch is already in flight. If a window reset (filter /
  /// refresh) supersedes this call mid-fetch, the stale page is discarded.
  func loadMore() async {
    guard hasMore, !isLoadingMore else { return }
    isLoadingMore = true
    let generation = loadGeneration
    do {
      try await fetchNextPage(generation: generation)
      if generation == loadGeneration { rebuildSections() }
    } catch {
      // Suppress an error from a page that a window reset already superseded —
      // it no longer corresponds to the live window.
      if generation == loadGeneration { errorMessage = Self.failureMessage(error) }
    }
    isLoadingMore = false
  }

  /// Applies (or clears) the scenario-name filter and reloads the aggregate
  /// window from the top. No spinner — the prior sections stay visible until
  /// the new page resolves. No-op when the query is unchanged.
  func applyFilter(_ query: String) async {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed != nameQuery else { return }
    nameQuery = trimmed
    errorMessage = nil
    do {
      // Reuse the index — the scenario set is invariant while typing (#678).
      try await reloadAggregate(rebuildIndex: false)
    } catch {
      errorMessage = Self.failureMessage(error)
    }
  }

  /// Re-fetches in place when the list reappears (e.g. after a per-run delete
  /// pops back). For aggregate, the currently-loaded depth is re-read from the
  /// top so a deleted run drops out without resetting the user's scroll
  /// position (#586). For detail, a silent full reload.
  func refreshOnReappear(scope: ResultsScope) async {
    errorMessage = nil
    switch scope {
    case .aggregate:
      do {
        try await refreshAggregatePreservingDepth()
      } catch {
        errorMessage = Self.failureMessage(error)
      }
    case .scenario:
      await load(scope: scope, showLoading: false)
    }
  }

  // MARK: - Aggregate (paginated recency window)

  /// Resets the window and loads the first page. `rebuildIndex: false` reuses
  /// the scenario index (filter path, #678) — see ``scenarioIndexBuilt``.
  private func reloadAggregate(rebuildIndex: Bool = true) async throws {
    loadGeneration += 1
    let generation = loadGeneration
    if rebuildIndex || !scenarioIndexBuilt {
      try await refreshScenarioIndex()
      guard generation == loadGeneration else { return }
    }
    loadedRuns = []
    cursor = nil
    loadedRawCount = 0
    hasMore = true
    try await loadTotalRunCount(generation: generation)
    guard generation == loadGeneration else { return }
    try await fetchNextPage(generation: generation)
    guard generation == loadGeneration else { return }
    rebuildSections()
  }

  /// Fetches the next keyset page and folds it into the window. Every fetched
  /// row is visible (P5 keeps all runs), so a single page either makes progress
  /// or signals the end — no dangling-row drain loop is needed.
  private func fetchNextPage(generation: Int) async throws {
    guard hasMore else { return }
    let query = nameQuery.isEmpty ? nil : nameQuery
    let cursorSnapshot = cursor
    let limit = pageSize
    let rawPage = try await offMain { [simulationRepository] in
      try simulationRepository.fetchRecentRunPage(
        nameQuery: query, before: cursorSnapshot, limit: limit)
    }
    // A window reset (filter / refresh) landed during the fetch — this page was
    // read against a now-stale query/cursor, so drop it rather than fold it
    // into the reset window.
    guard generation == loadGeneration else { return }
    ingest(rawPage)
  }

  /// Folds a freshly-fetched page into the window: advances `hasMore` and the
  /// keyset `cursor` off the row count / last row, and appends every row.
  private func ingest(_ rawPage: [PastRunListItem]) {
    loadedRawCount += rawPage.count
    hasMore = rawPage.count == pageSize
    if let last = rawPage.last {
      cursor = SimulationPageCursor(createdAt: last.createdAt, id: last.id)
    }
    loadedRuns += rawPage
  }

  /// Re-reads the loaded depth from the top, recomputing `cursor` + `hasMore`
  /// from the re-fetched window. Keyset tolerates a cursor that points at a
  /// since-deleted row (it is still a valid `<` boundary), so a delete between
  /// pages cannot corrupt a subsequent ``loadMore()``. The re-read depth is
  /// unbounded by design (it preserves the user's scroll position); memory
  /// stays light because the repository still projects `stateJSON` away per
  /// row.
  private func refreshAggregatePreservingDepth() async throws {
    loadGeneration += 1
    let generation = loadGeneration
    try await refreshScenarioIndex()
    guard generation == loadGeneration else { return }
    try await loadTotalRunCount(generation: generation)
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
    loadedRuns = rawPage
    rebuildSections()
  }

  /// Loads the filtered total-run count (off the main actor). Guarded by the
  /// generation stamp so a stale window-reset's count can't overwrite a newer
  /// one.
  private func loadTotalRunCount(generation: Int) async throws {
    let query = nameQuery.isEmpty ? nil : nameQuery
    let count = try await offMain { [simulationRepository] in
      try simulationRepository.totalRunCount(nameQuery: query)
    }
    guard generation == loadGeneration else { return }
    totalRunCount = count
  }

  /// Reloads the bounded scenario index used for per-row labels. Uses the
  /// `yamlDefinition`-excluding ``ScenarioSummary`` projection — the row label
  /// only needs `name`, so the heavy YAML never crosses into memory (#679); the
  /// heavy run rows page in lazily.
  private func refreshScenarioIndex() async throws {
    let scenarios = try await offMain { [scenarioRepository] in
      try scenarioRepository.fetchAllSummaries()
    }
    scenarioById = Dictionary(
      scenarios.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    scenarioIndexBuilt = true
  }

  /// The per-variant display label for a run's row — the live scenario `name`,
  /// falling back to the captured snapshot for a deleted scenario, then a
  /// generic placeholder. Never empty, so no run is dropped from the list (P5
  /// retired the prior dangling-scenarioId hide).
  private func variantName(for item: PastRunListItem) -> String {
    if let scenarioId = item.scenarioId, let scenario = scenarioById[scenarioId] {
      return scenario.name
    }
    return item.scenarioNameSnapshot ?? String(localized: "Deleted scenario")
  }

  /// Re-buckets the full accumulated window into date sections. Sections appear
  /// in the recency order their most-recent run was first seen (``loadedRuns``
  /// is global newest-first), so older pages extend existing sections downward
  /// and only introduce new (older) sections below.
  private func rebuildSections() {
    let currentDate = now()
    // Resolve each run's scenario meta (snapshot-first, live YAML as the pre-v7
    // fallback) in one pass; the resolver rebuilds its memo to this key set.
    let metaById = metaResolver.resolve(
      loadedRuns.map { (id: $0.id, yaml: yamlSource(for: $0)) })
    var order: [String] = []
    var titleByKey: [String: String] = [:]
    var rowsByKey: [String: [SimulationRow]] = [:]
    for item in loadedRuns {
      // Resolve the (cheap) key per run, but the display title — whose older
      // "Month" headings build a DateFormatter — only once per distinct key.
      let key = ResultsRowFormat.bucketKey(
        for: item.createdAt, now: currentDate, calendar: calendar)
      if rowsByKey[key] == nil {
        order.append(key)
        rowsByKey[key] = []
        titleByKey[key] =
          ResultsRowFormat.dateBucket(
            for: item.createdAt, now: currentDate, calendar: calendar
          ).title
      }
      let meta = metaById[item.id] ?? .unknown
      rowsByKey[key]?.append(
        SimulationRow(
          item: item, variantName: variantName(for: item),
          agentCount: meta.agentCount, totalRounds: meta.rounds))
    }
    sections = order.compactMap { key in
      guard let rows = rowsByKey[key], !rows.isEmpty else { return nil }
      return ResultSection(key: key, title: titleByKey[key] ?? "", rows: rows)
    }
  }

  /// The YAML a run's meta resolves from in the aggregate list — its captured
  /// `scenarioYamlSnapshot` only. The bounded scenario index is the
  /// `yamlDefinition`-excluding ``ScenarioSummary`` projection (#679/#700: no
  /// bulk YAML in the list's memory), so there is no live-YAML fallback here — a
  /// pre-v7 run with no snapshot resolves to `nil`, degrading to name-only. The
  /// per-scenario **detail** path keeps a live fallback (it already fetches that
  /// one scenario's full record, see ``loadDetailPerVariant(scenarioId:)``).
  private func yamlSource(for item: PastRunListItem) -> String? {
    item.scenarioYamlSnapshot
  }

  // MARK: - Detail (per-variant, un-paginated)

  /// Detail path: shows only this scenario's simulations as lightweight rows
  /// under a single section. No cross-variant aggregation by design — a user on
  /// a JA `ScenarioDetailView` sees only JA runs even when an EN sibling exists.
  private func loadDetailPerVariant(scenarioId: String) async throws {
    let scenario = try await offMain { [scenarioRepository] in
      try scenarioRepository.fetchById(scenarioId)
    }
    let items = try await offMain { [simulationRepository] in
      try simulationRepository.fetchRunList(scenarioId: scenarioId)
    }
    guard !items.isEmpty else {
      sections = []
      totalRunCount = 0
      return
    }

    let name = scenario?.name ?? String(localized: "Unknown")
    let canonical = scenario?.sourceId ?? scenarioId
    // `fetchRunList` already returns newest-first; no re-sort needed. Resolve
    // each run's meta snapshot-first, with this scenario's live YAML as the
    // pre-v7 fallback.
    let liveYAML = scenario?.yamlDefinition
    let metaById = metaResolver.resolve(
      items.map { (id: $0.id, yaml: $0.scenarioYamlSnapshot ?? liveYAML) })
    let rows = items.map { item -> SimulationRow in
      let meta = metaById[item.id] ?? .unknown
      return SimulationRow(
        item: item, variantName: name,
        agentCount: meta.agentCount, totalRounds: meta.rounds)
    }
    sections = [ResultSection(key: canonical, title: name, rows: rows)]
    totalRunCount = items.count
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
