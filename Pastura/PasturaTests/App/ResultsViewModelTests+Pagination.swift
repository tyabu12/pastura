import Foundation
import GRDB
import Testing

@testable import Pastura

/// Keyset-pagination, name-filter, auto-drain, re-entrancy, and incremental
/// reappear-refresh tests for ``ResultsViewModel``'s aggregate path (#586).
/// Sibling extension on the same suite — see `testing.md` § "Splitting a Suite
/// Across Files". Helpers are file-scope (the suite's `makeResultsSUT` builds
/// at the default page size; these tests need a small page size to drive
/// multi-page behavior without seeding hundreds of runs).
extension ResultsViewModelTests {

  // MARK: - Keyset pagination + load-more

  @Test func aggregatePaginatesAcrossPagesWithLoadMore() async throws {
    let env = try makePagedSUT(pageSize: 2)
    // 5 scenarios, one run each, distinct times → 5 single-row groups.
    for index in 1...5 {
      try seedPagedScenario(env.scenarioRepo, id: "s\(index)", name: "Scenario \(index)")
      try seedPagedRun(env.simRepo, id: "r\(index)", scenarioId: "s\(index)", at: Double(index))
    }

    await env.sut.load(scope: .aggregate, deviceLanguage: "ja")
    #expect(env.sut.groups.count == 2)
    #expect(env.sut.hasMore)
    #expect(env.sut.groups.map(\.canonicalKey) == ["s5", "s4"])

    await env.sut.loadMore()
    #expect(env.sut.groups.count == 4)
    #expect(env.sut.hasMore)

    await env.sut.loadMore()
    #expect(env.sut.groups.map(\.canonicalKey) == ["s5", "s4", "s3", "s2", "s1"])
    #expect(env.sut.hasMore == false)

    // Exhausted — a further loadMore is a no-op.
    await env.sut.loadMore()
    #expect(env.sut.groups.count == 5)
  }

  /// A canonical group whose runs straddle a page boundary must reassemble
  /// into a single group as the older page loads (critic Axis 1 — the
  /// row-paginated / group-displayed seam).
  @Test func aggregateGroupSplitAcrossPagesReassembles() async throws {
    let env = try makePagedSUT(pageSize: 2)
    try seedPagedScenario(env.scenarioRepo, id: "A", name: "Alpha")
    try seedPagedScenario(env.scenarioRepo, id: "B", name: "Beta")
    // Global recency: A@5, B@4, A@3 → A's runs straddle the 2-row boundary.
    try seedPagedRun(env.simRepo, id: "a_new", scenarioId: "A", at: 5)
    try seedPagedRun(env.simRepo, id: "b_mid", scenarioId: "B", at: 4)
    try seedPagedRun(env.simRepo, id: "a_old", scenarioId: "A", at: 3)

    await env.sut.load(scope: .aggregate, deviceLanguage: "ja")
    // Page 1: A has only its newest run so far.
    #expect(env.sut.groups.first { $0.canonicalKey == "A" }?.rows.count == 1)

    await env.sut.loadMore()
    // Page 2 brings A's older run — the group reassembles to two rows,
    // newest-first, still a single group.
    let groupA = try #require(env.sut.groups.first { $0.canonicalKey == "A" })
    #expect(groupA.rows.map(\.id) == ["a_new", "a_old"])
    #expect(env.sut.groups.first { $0.canonicalKey == "B" }?.rows.count == 1)
    #expect(env.sut.groups.count == 2)
  }

  // MARK: - Auto-drain invisible (dangling) pages

  /// A full page of dangling-scenarioId (invisible) runs must not stall the
  /// window — `loadMore`/first-load drain past it to surface the visible runs
  /// beneath (critic Axis 2).
  @Test func aggregateDrainsAllDanglingPageToSurfaceVisibleRun() async throws {
    let env = try makePagedSUT(pageSize: 2)
    try seedPagedScenario(env.scenarioRepo, id: "owned", name: "Owned")
    // Visible run is the OLDEST; two newer dangling runs fill the first page.
    try seedPagedRun(env.simRepo, id: "visible", scenarioId: "owned", at: 1)
    try plantDanglingRun(env.db, id: "ghost_a", at: 3)
    try plantDanglingRun(env.db, id: "ghost_b", at: 2)

    await env.sut.load(scope: .aggregate, deviceLanguage: "ja")

    // The all-dangling first page was drained internally; the visible run
    // surfaced rather than the list stalling empty.
    #expect(env.sut.groups.count == 1)
    let allRowIds = env.sut.groups.flatMap { $0.rows.map(\.id) }
    #expect(allRowIds == ["visible"])
  }

  // MARK: - Name filter

  @Test func aggregateFilterNarrowsThenClears() async throws {
    let env = try makePagedSUT(pageSize: 50)
    try seedPagedScenario(env.scenarioRepo, id: "a", name: "Alpha Game")
    try seedPagedScenario(env.scenarioRepo, id: "b", name: "Beta Game")
    try seedPagedRun(env.simRepo, id: "ra", scenarioId: "a", at: 2)
    try seedPagedRun(env.simRepo, id: "rb", scenarioId: "b", at: 1)

    await env.sut.load(scope: .aggregate, deviceLanguage: "ja")
    #expect(env.sut.groups.count == 2)

    await env.sut.applyFilter("alpha", deviceLanguage: "ja")
    #expect(env.sut.groups.map(\.canonicalKey) == ["a"])

    // Clearing the filter restores the full window.
    await env.sut.applyFilter("", deviceLanguage: "ja")
    #expect(env.sut.groups.count == 2)
  }

  // MARK: - Re-entrancy

  /// Two concurrent `loadMore()` calls must load exactly one page — the
  /// `isLoadingMore` guard prevents a double-append at the same cursor
  /// (critic Axis 4).
  @Test func aggregateConcurrentLoadMoreLoadsOnePageOnly() async throws {
    let env = try makePagedSUT(pageSize: 2)
    for index in 1...5 {
      try seedPagedScenario(env.scenarioRepo, id: "s\(index)", name: "Scenario \(index)")
      try seedPagedRun(env.simRepo, id: "r\(index)", scenarioId: "s\(index)", at: Double(index))
    }

    await env.sut.load(scope: .aggregate, deviceLanguage: "ja")
    #expect(env.sut.groups.count == 2)

    async let first: Void = env.sut.loadMore()
    async let second: Void = env.sut.loadMore()
    _ = await (first, second)

    // Exactly one extra page (2 rows) — not two pages, no duplicate rows.
    let ids = env.sut.groups.flatMap { $0.rows.map(\.id) }
    #expect(ids.count == 4)
    #expect(Set(ids).count == ids.count)
  }

  /// A filter change that lands while an auto-fired `loadMore` is in flight
  /// must win — the stale (unfiltered) page is discarded by the generation
  /// guard rather than folded into the freshly-filtered window (review Warning).
  @Test func aggregateFilterSupersedesInFlightLoadMore() async throws {
    let env = try makePagedSUT(pageSize: 2)
    try seedPagedScenario(env.scenarioRepo, id: "alpha", name: "Alpha")
    try seedPagedScenario(env.scenarioRepo, id: "beta", name: "Beta")
    try seedPagedRun(env.simRepo, id: "alpha1", scenarioId: "alpha", at: 4)
    try seedPagedRun(env.simRepo, id: "beta1", scenarioId: "beta", at: 3)
    try seedPagedRun(env.simRepo, id: "alpha2", scenarioId: "alpha", at: 2)
    try seedPagedRun(env.simRepo, id: "beta2", scenarioId: "beta", at: 1)

    await env.sut.load(scope: .aggregate, deviceLanguage: "ja")
    #expect(env.sut.hasMore)

    // Interleave a load-more with a filter change.
    async let more: Void = env.sut.loadMore()
    async let filter: Void = env.sut.applyFilter("alpha", deviceLanguage: "ja")
    _ = await (more, filter)

    // Whatever the interleaving, the final window reflects the "alpha" filter —
    // no stale Beta rows leaked in from the discarded loadMore page.
    let canonicalKeys = Set(env.sut.groups.map(\.canonicalKey))
    #expect(canonicalKeys == ["alpha"])
    let ids = env.sut.groups.flatMap { $0.rows.map(\.id) }
    #expect(Set(ids) == ["alpha1", "alpha2"])
  }

  // MARK: - Incremental reappear refresh

  /// After a per-run delete (the #545 reappear trigger), the incremental
  /// refresh re-reads the loaded depth from the top — dropping the deleted run,
  /// preserving depth, and recomputing the cursor so a later `loadMore` neither
  /// duplicates nor skips (critic Axis 6).
  @Test func aggregateRefreshAfterDeletePreservesDepthAndCursor() async throws {
    let env = try makePagedSUT(pageSize: 2)
    for index in 1...5 {
      try seedPagedScenario(env.scenarioRepo, id: "s\(index)", name: "Scenario \(index)")
      try seedPagedRun(env.simRepo, id: "r\(index)", scenarioId: "s\(index)", at: Double(index))
    }

    await env.sut.load(scope: .aggregate, deviceLanguage: "ja")  // r5, r4
    await env.sut.loadMore()  // + r3, r2 → depth 4 loaded, a 5th remains

    // Delete a loaded run, then reappear-refresh.
    try env.simRepo.delete("r4")
    await env.sut.refreshOnReappear(scope: .aggregate, deviceLanguage: "ja")

    var ids = env.sut.groups.flatMap { $0.rows.map(\.id) }
    #expect(!ids.contains("r4"))
    #expect(Set(ids) == ["r5", "r3", "r2", "r1"])  // depth refilled to 4 from the top
    #expect(Set(ids).count == ids.count)

    // Cursor was recomputed from the refreshed window — a further loadMore
    // finds nothing older and adds no duplicate.
    await env.sut.loadMore()
    ids = env.sut.groups.flatMap { $0.rows.map(\.id) }
    #expect(Set(ids) == ["r5", "r3", "r2", "r1"])
    #expect(Set(ids).count == ids.count)
  }
}

// MARK: - File-scope helpers

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
    pageSize: pageSize)
  return PagedResultsSUT(db: db, sut: sut, scenarioRepo: scenarioRepo, simRepo: simRepo)
}

private func seedPagedScenario(
  _ repo: GRDBScenarioRepository, id: String, name: String, language: String = "ja"
) throws {
  try repo.save(
    ScenarioRecord(
      id: id, name: name,
      yamlDefinition: "id: \(id)\nlanguage: \(language)\nname: \(name)\n",
      isPreset: false, createdAt: Date(), updatedAt: Date()))
}

private func seedPagedRun(
  _ repo: GRDBSimulationRepository, id: String, scenarioId: String, at offset: Double
) throws {
  let when = Date(timeIntervalSince1970: offset)
  try repo.save(
    SimulationRecord(
      id: id, scenarioId: scenarioId,
      status: SimulationStatus.completed.rawValue,
      currentRound: 1, currentPhaseIndex: 0,
      stateJSON: "{}", configJSON: nil,
      createdAt: when, updatedAt: when))
}

/// Plants a run whose non-null `scenarioId` references no live scenario — a
/// dangling row only reachable by bypassing FK enforcement (production schema
/// makes it impossible). Used to exercise the invisible-dangling contract.
private func plantDanglingRun(_ db: DatabaseManager, id: String, at offset: Double) throws {
  let when = Date(timeIntervalSince1970: offset)
  // SQLite ignores `PRAGMA foreign_keys` inside a transaction, so take the
  // pragma in autocommit mode via `writeWithoutTransaction`.
  try db.dbWriter.writeWithoutTransaction { db in
    try db.execute(sql: "PRAGMA foreign_keys = OFF")
    try db.execute(
      sql: """
        INSERT INTO simulations
        (id, scenarioId, status, currentRound, currentPhaseIndex,
         stateJSON, configJSON, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
      arguments: [
        id, "ghost_scenario", SimulationStatus.completed.rawValue,
        1, 0, "{}", nil, when, when
      ])
    try db.execute(sql: "PRAGMA foreign_keys = ON")
  }
}
