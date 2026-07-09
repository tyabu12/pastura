import Foundation
import GRDB
import Testing
import os

@testable import Pastura

/// Keyset-pagination, name-filter, re-entrancy, and incremental reappear-refresh
/// tests for ``ResultsViewModel``'s aggregate path (#586). Sibling extension on
/// the same suite — see `testing.md` § "Splitting a Suite Across Files". Helpers
/// are file-scope (the suite's `makeResultsSUT` builds at the default page size;
/// these tests need a small page size to drive multi-page behavior without
/// seeding hundreds of runs).
///
/// Pagination is asserted on the flattened row stream (`sections.flatMap rows`)
/// rather than per-scenario groups: P5 groups by date, so runs seeded at the
/// same instant share one section and the meaningful contract is the
/// newest-first row order / count across `loadMore`.
extension ResultsViewModelTests {

  // MARK: - Keyset pagination + load-more

  @Test func aggregatePaginatesAcrossPagesWithLoadMore() async throws {
    let env = try makePagedSUT(pageSize: 2)
    // 5 runs at distinct times (all in one ancient date bucket — the row order,
    // not the bucket, is what pagination guarantees).
    for index in 1...5 {
      try seedPagedScenario(env.scenarioRepo, id: "s\(index)", name: "Scenario \(index)")
      try seedPagedRun(env.simRepo, id: "r\(index)", scenarioId: "s\(index)", at: Double(index))
    }

    await env.sut.load(scope: .aggregate)
    #expect(rowIds(env.sut) == ["r5", "r4"])
    #expect(env.sut.hasMore)

    await env.sut.loadMore()
    #expect(rowIds(env.sut) == ["r5", "r4", "r3", "r2"])
    #expect(env.sut.hasMore)

    await env.sut.loadMore()
    #expect(rowIds(env.sut) == ["r5", "r4", "r3", "r2", "r1"])
    #expect(env.sut.hasMore == false)

    // Exhausted — a further loadMore is a no-op.
    await env.sut.loadMore()
    #expect(rowIds(env.sut).count == 5)
  }

  /// Runs in the same date bucket whose rows straddle a page boundary must
  /// reassemble into a single section as the older page loads — the stable
  /// bucket key coalesces them rather than spawning a duplicate section
  /// (critic Warning 3: multi-page same-bucket merge).
  @Test func aggregateSameWeekRunsMergeAcrossPages() async throws {
    let env = try makePagedSUT(pageSize: 2)
    try seedPagedScenario(env.scenarioRepo, id: "s", name: "Scenario")
    // Three runs, all earlier this week (not today) relative to resultsTestNow
    // (2026-06-17): 06-16, 06-15, 06-14. Ids are assigned so their lexical
    // order DISAGREES with the date order — newest (06-16) gets the lexically
    // smallest id "d16" only by date, so a regression from createdAt-desc to
    // id-asc sorting would reorder the rows and fail the assertion.
    try seedPagedRun(env.simRepo, id: "d16", scenarioId: "s", on: resultsTestDate(2026, 6, 16))
    try seedPagedRun(env.simRepo, id: "d15", scenarioId: "s", on: resultsTestDate(2026, 6, 15))
    try seedPagedRun(env.simRepo, id: "d14", scenarioId: "s", on: resultsTestDate(2026, 6, 14))

    await env.sut.load(scope: .aggregate)
    // Page 1: two of the three week runs, single "week" section, newest-first
    // (date-desc) — NOT id-asc, which would be ["d14", "d15"].
    #expect(env.sut.sections.count == 1)
    #expect(env.sut.sections.first?.key == "week")
    #expect(rowIds(env.sut) == ["d16", "d15"])

    await env.sut.loadMore()
    // Page 2 brings the third — still ONE "week" section, newest-first.
    #expect(env.sut.sections.count == 1)
    #expect(env.sut.sections.first?.key == "week")
    #expect(rowIds(env.sut) == ["d16", "d15", "d14"])
  }

  // MARK: - Name filter

  @Test func aggregateFilterNarrowsThenClears() async throws {
    let env = try makePagedSUT(pageSize: 50)
    try seedPagedScenario(env.scenarioRepo, id: "a", name: "Alpha Game")
    try seedPagedScenario(env.scenarioRepo, id: "b", name: "Beta Game")
    try seedPagedRun(env.simRepo, id: "ra", scenarioId: "a", at: 2)
    try seedPagedRun(env.simRepo, id: "rb", scenarioId: "b", at: 1)

    await env.sut.load(scope: .aggregate)
    #expect(Set(rowIds(env.sut)) == ["ra", "rb"])

    await env.sut.applyFilter("alpha")
    #expect(rowIds(env.sut) == ["ra"])

    // Clearing the filter restores the full window.
    await env.sut.applyFilter("")
    #expect(Set(rowIds(env.sut)) == ["ra", "rb"])
  }

  // MARK: - Re-entrancy

  /// Two overlapping `loadMore()` calls must load exactly one page — the
  /// `isLoadingMore` re-entrancy guard prevents a double-append at the same
  /// cursor.
  ///
  /// The concurrency is made **deterministic** (a `GatedSimulationRepository`
  /// parks the first `loadMore`'s page read in-flight) rather than relying on
  /// two `async let` children genuinely overlapping — under scheduler pressure
  /// (CI + coverage) the children can serialize, and two *sequential*
  /// `loadMore`s correctly load two pages (5 rows), which flaked this test
  /// (#1005). Parking guarantees the second call hits the guard while the first
  /// is still in `fetchNextPage`, so it exercises the real guard:
  /// reverting `!isLoadingMore` from ``ResultsViewModel/loadMore()`` makes the
  /// second call fetch the same cursor page, yielding 6 duplicated rows and
  /// failing both assertions below.
  @Test func aggregateConcurrentLoadMoreLoadsOnePageOnly() async throws {
    let db = try DatabaseManager.inMemory()
    let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
    let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
    for index in 1...5 {
      try seedPagedScenario(scenarioRepo, id: "s\(index)", name: "Scenario \(index)")
      try seedPagedRun(simRepo, id: "r\(index)", scenarioId: "s\(index)", at: Double(index))
    }
    let gated = GatedSimulationRepository(base: simRepo)
    let sut = ResultsViewModel(
      scenarioRepository: scenarioRepo,
      simulationRepository: gated,
      turnRepository: turnRepo,
      pageSize: 2,
      now: { resultsTestNow },
      calendar: resultsTestCalendar)

    await sut.load(scope: .aggregate)
    #expect(rowIds(sut).count == 2)
    #expect(sut.hasMore)

    // Arm the gate so the *next* page read — the first loadMore's fetch — parks
    // in-flight. The initial load above already ran unparked.
    gated.armNextFetch()

    // loadMore A sets `isLoadingMore` synchronously (before its first await),
    // then parks inside `fetchNextPage`.
    let first = Task { await sut.loadMore() }
    await gated.awaitFetchEntered()  // A is now genuinely in-flight

    // loadMore B hits the re-entrancy guard synchronously (`isLoadingMore ==
    // true`) and returns without fetching.
    await sut.loadMore()

    // Release A so it folds its single page in.
    gated.releaseParkedFetch()
    await first.value

    // Exactly one extra page (2 rows) — not two pages, no duplicate rows.
    let ids = rowIds(sut)
    #expect(ids.count == 4)
    #expect(Set(ids).count == ids.count)
  }

  /// A filter change that lands while an auto-fired `loadMore` is in flight must
  /// win — the stale (unfiltered) page is discarded by the generation guard
  /// rather than folded into the freshly-filtered window.
  @Test func aggregateFilterSupersedesInFlightLoadMore() async throws {
    let env = try makePagedSUT(pageSize: 2)
    try seedPagedScenario(env.scenarioRepo, id: "alpha", name: "Alpha")
    try seedPagedScenario(env.scenarioRepo, id: "beta", name: "Beta")
    try seedPagedRun(env.simRepo, id: "alpha1", scenarioId: "alpha", at: 4)
    try seedPagedRun(env.simRepo, id: "beta1", scenarioId: "beta", at: 3)
    try seedPagedRun(env.simRepo, id: "alpha2", scenarioId: "alpha", at: 2)
    try seedPagedRun(env.simRepo, id: "beta2", scenarioId: "beta", at: 1)

    await env.sut.load(scope: .aggregate)
    #expect(env.sut.hasMore)

    // Interleave a load-more with a filter change.
    async let more: Void = env.sut.loadMore()
    async let filter: Void = env.sut.applyFilter("alpha")
    _ = await (more, filter)

    // Whatever the interleaving, the final window reflects the "alpha" filter —
    // no stale Beta rows leaked in from the discarded loadMore page.
    #expect(Set(rowIds(env.sut)) == ["alpha1", "alpha2"])
  }

  // MARK: - Incremental reappear refresh

  /// After a per-run delete (the #545 reappear trigger), the incremental
  /// refresh re-reads the loaded depth from the top — dropping the deleted run,
  /// preserving depth, and recomputing the cursor so a later `loadMore` neither
  /// duplicates nor skips.
  @Test func aggregateRefreshAfterDeletePreservesDepthAndCursor() async throws {
    let env = try makePagedSUT(pageSize: 2)
    for index in 1...5 {
      try seedPagedScenario(env.scenarioRepo, id: "s\(index)", name: "Scenario \(index)")
      try seedPagedRun(env.simRepo, id: "r\(index)", scenarioId: "s\(index)", at: Double(index))
    }

    await env.sut.load(scope: .aggregate)  // r5, r4
    await env.sut.loadMore()  // + r3, r2 → depth 4 loaded, a 5th remains

    // Delete a loaded run, then reappear-refresh.
    try env.simRepo.delete("r4")
    await env.sut.refreshOnReappear(scope: .aggregate)

    var ids = rowIds(env.sut)
    #expect(!ids.contains("r4"))
    #expect(Set(ids) == ["r5", "r3", "r2", "r1"])  // depth refilled to 4 from the top
    #expect(Set(ids).count == ids.count)

    // Cursor was recomputed from the refreshed window — a further loadMore finds
    // nothing older and adds no duplicate.
    await env.sut.loadMore()
    ids = rowIds(env.sut)
    #expect(Set(ids) == ["r5", "r3", "r2", "r1"])
    #expect(Set(ids).count == ids.count)
  }
}

// MARK: - File-scope helpers

@MainActor
private func rowIds(_ sut: ResultsViewModel) -> [String] {
  sut.sections.flatMap { $0.rows.map(\.id) }
}

private struct PagedResultsSUT {
  let db: DatabaseManager
  let sut: ResultsViewModel
  let scenarioRepo: GRDBScenarioRepository
  let simRepo: GRDBSimulationRepository
}

@MainActor
private func makePagedSUT(pageSize: Int) throws -> PagedResultsSUT {
  let db = try DatabaseManager.inMemory()
  let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
  let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
  let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
  let sut = ResultsViewModel(
    scenarioRepository: scenarioRepo,
    simulationRepository: simRepo,
    turnRepository: turnRepo,
    pageSize: pageSize,
    now: { resultsTestNow },
    calendar: resultsTestCalendar)
  return PagedResultsSUT(db: db, sut: sut, scenarioRepo: scenarioRepo, simRepo: simRepo)
}

private func seedPagedScenario(
  _ repo: GRDBScenarioRepository, id: String, name: String
) throws {
  try repo.save(
    ScenarioRecord(
      id: id, name: name,
      yamlDefinition: "id: \(id)\nname: \(name)\n",
      isPreset: false, createdAt: Date(), updatedAt: Date()))
}

private func seedPagedRun(
  _ repo: GRDBSimulationRepository, id: String, scenarioId: String, at offset: Double
) throws {
  try seedPagedRun(repo, id: id, scenarioId: scenarioId, on: Date(timeIntervalSince1970: offset))
}

private func seedPagedRun(
  _ repo: GRDBSimulationRepository, id: String, scenarioId: String, on when: Date
) throws {
  try repo.save(
    SimulationRecord(
      id: id, scenarioId: scenarioId,
      status: SimulationStatus.completed.rawValue,
      currentRound: 1, currentPhaseIndex: 0,
      stateJSON: "{}", configJSON: nil,
      createdAt: when, updatedAt: when))
}

/// A ``SimulationRepository`` decorator that can hold **one**
/// ``fetchRecentRunPage(nameQuery:before:limit:)`` call parked mid-flight, so
/// ``ResultsViewModel/loadMore()``'s `isLoadingMore` re-entrancy guard is
/// exercised deterministically instead of relying on `async let` children
/// happening to overlap (#1005). Every other call — and every fetch before
/// ``armNextFetch()`` — delegates straight to `base`.
///
/// Mechanism: `loadMore` sets `isLoadingMore` synchronously and only then hits
/// its first `await` (the off-main `fetchRecentRunPage` read, which this gate
/// parks). Parking that read therefore holds `isLoadingMore == true` while a
/// second `loadMore` runs its guard — mirroring the deterministic-parking
/// pattern in `.claude/rules/testing.md` § "Parking a run mid-flight". The
/// synchronous protocol method can't `await`, so the park is a
/// `DispatchSemaphore` block on the off-main `Task.detached` thread (bounded by
/// the suite's `.timeLimit`); entry is signalled via a continuation so the test
/// side never blocks a thread.
private final class GatedSimulationRepository: SimulationRepository, @unchecked Sendable {
  private let base: any SimulationRepository

  private struct GateState {
    var armed = false
    var parkedOnce = false
    var didEnter = false
    var enteredContinuation: CheckedContinuation<Void, Never>?
  }
  private let state = OSAllocatedUnfairLock(uncheckedState: GateState())
  private let releaseGate = DispatchSemaphore(value: 0)

  init(base: any SimulationRepository) {
    self.base = base
  }

  /// Arms the gate so the next `fetchRecentRunPage` parks. Call **after** the
  /// initial page load so only the loadMore fetch is affected.
  func armNextFetch() {
    state.withLock { $0.armed = true }
  }

  /// Suspends until the parked fetch has entered — guaranteeing `isLoadingMore`
  /// is set, since `loadMore` sets it synchronously before its first await.
  func awaitFetchEntered() async {
    await withCheckedContinuation { continuation in
      let alreadyEntered = state.withLock { gate -> Bool in
        if gate.didEnter { return true }
        gate.enteredContinuation = continuation
        return false
      }
      if alreadyEntered { continuation.resume() }
    }
  }

  /// Releases the parked fetch so it completes.
  func releaseParkedFetch() {
    releaseGate.signal()
  }

  func fetchRecentRunPage(
    nameQuery: String?, before: SimulationPageCursor?, limit: Int
  ) throws -> [PastRunListItem] {
    let shouldPark = state.withLock { gate -> Bool in
      guard gate.armed, !gate.parkedOnce else { return false }
      gate.parkedOnce = true
      return true
    }
    if shouldPark {
      // Signal entry (resume outside the lock) then block until released.
      let continuation = state.withLock { gate -> CheckedContinuation<Void, Never>? in
        gate.didEnter = true
        defer { gate.enteredContinuation = nil }
        return gate.enteredContinuation
      }
      continuation?.resume()
      releaseGate.wait()
    }
    return try base.fetchRecentRunPage(nameQuery: nameQuery, before: before, limit: limit)
  }

  // MARK: - Straight delegation

  func save(_ record: SimulationRecord) throws { try base.save(record) }
  func fetchById(_ id: String) throws -> SimulationRecord? { try base.fetchById(id) }
  func fetchByScenarioId(_ scenarioId: String) throws -> [SimulationRecord] {
    try base.fetchByScenarioId(scenarioId)
  }
  func fetchRunList(scenarioId: String) throws -> [PastRunListItem] {
    try base.fetchRunList(scenarioId: scenarioId)
  }
  func fetchOrphaned() throws -> [SimulationRecord] { try base.fetchOrphaned() }
  func fetchByStatus(_ status: SimulationStatus) throws -> [SimulationRecord] {
    try base.fetchByStatus(status)
  }
  func completedRunCountsByScenarioId() throws -> [String: Int] {
    try base.completedRunCountsByScenarioId()
  }
  func updateState(
    _ id: String, stateJSON: String, currentRound: Int, currentPhaseIndex: Int
  ) throws {
    try base.updateState(
      id, stateJSON: stateJSON, currentRound: currentRound, currentPhaseIndex: currentPhaseIndex)
  }
  func updateStatus(_ id: String, status: SimulationStatus) throws {
    try base.updateStatus(id, status: status)
  }
  func updateDegradedTurnCount(_ id: String, count: Int) throws {
    try base.updateDegradedTurnCount(id, count: count)
  }
  func totalRunCount(nameQuery: String?) throws -> Int {
    try base.totalRunCount(nameQuery: nameQuery)
  }
  func delete(_ id: String) throws { try base.delete(id) }
  func deleteAll() throws { try base.deleteAll() }
  func pastResultsByteCount() throws -> Int64 { try base.pastResultsByteCount() }
}
