import Foundation
import Testing

@testable import Pastura

/// Keyset-pagination + name-filter + lightweight-projection tests for
/// ``SimulationRepository/fetchRecentRunPage(nameQuery:before:limit:)`` and
/// ``SimulationRepository/fetchRunList(scenarioId:)`` (issue #586). Sibling
/// extension on the same suite — see `testing.md` § "Splitting a Suite Across
/// Files". Helpers live at file scope (the original suite's `makeRepos` /
/// `makeSimRecord` are `private`, so a sibling can't reach them).
extension SimulationRepositoryTests {

  // MARK: - Recency window + ordering

  @Test func fetchRecentRunPageReturnsNewestFirstAcrossScenarios() throws {
    let env = try makePagingRepos()
    try env.scenarios.save(scenario(id: "s1", name: "One"))
    try env.scenarios.save(scenario(id: "s2", name: "Two"))
    try env.sims.save(run(id: "old", scenarioId: "s1", at: 0))
    try env.sims.save(run(id: "mid", scenarioId: "s2", at: 100))
    try env.sims.save(run(id: "new", scenarioId: "s1", at: 200))

    let page = try env.sims.fetchRecentRunPage(nameQuery: nil, before: nil, limit: 10)

    #expect(page.map(\.id) == ["new", "mid", "old"])
  }

  // MARK: - Keyset pagination

  @Test func fetchRecentRunPagePaginatesWithoutOverlapOrGap() throws {
    let env = try makePagingRepos()
    try env.scenarios.save(scenario(id: "s1", name: "One"))
    for index in 0..<5 {
      try env.sims.save(run(id: "run\(index)", scenarioId: "s1", at: Double(index)))
    }

    var collected: [String] = []
    var cursor: SimulationPageCursor?
    while true {
      let page = try env.sims.fetchRecentRunPage(nameQuery: nil, before: cursor, limit: 2)
      collected += page.map(\.id)
      guard page.count == 2, let last = page.last else { break }
      cursor = SimulationPageCursor(createdAt: last.createdAt, id: last.id)
    }

    // Full coverage, newest-first, no duplicates.
    #expect(collected == ["run4", "run3", "run2", "run1", "run0"])
    #expect(Set(collected).count == collected.count)
  }

  /// The keyset tie-break (`createdAt = ? AND id < ?`) is the only non-trivial
  /// boundary: `createdAt` is stored at millisecond precision, so two runs can
  /// collapse to the same stored value. Here `run_m` and `run_n` share an
  /// instant straddling the page boundary; each must appear exactly once.
  @Test func fetchRecentRunPageSameMillisecondTieStraddlesPageBoundary() throws {
    let env = try makePagingRepos()
    try env.scenarios.save(scenario(id: "s1", name: "One"))
    let shared = Date(timeIntervalSince1970: 50)
    try env.sims.save(run(id: "run_old", scenarioId: "s1", at: 0))
    try env.sims.save(run(id: "run_m", scenarioId: "s1", at: shared))
    try env.sims.save(run(id: "run_n", scenarioId: "s1", at: shared))

    // Order: same-instant rows by id DESC → run_n, run_m, then run_old.
    let page1 = try env.sims.fetchRecentRunPage(nameQuery: nil, before: nil, limit: 2)
    #expect(page1.map(\.id) == ["run_n", "run_m"])

    let last = try #require(page1.last)
    let page2 = try env.sims.fetchRecentRunPage(
      nameQuery: nil,
      before: SimulationPageCursor(createdAt: last.createdAt, id: last.id),
      limit: 2)
    // run_m (same instant, id not < "run_m") must NOT reappear; run_old follows.
    #expect(page2.map(\.id) == ["run_old"])
  }

  /// A run inserted at the top of the stream between page fetches (e.g. a
  /// background sim completing, ADR-003) must not shift an in-progress keyset
  /// walk — the cursor is an absolute boundary, so the second page is
  /// unaffected and yields no duplicate.
  @Test func fetchRecentRunPageStableUnderConcurrentInsert() throws {
    let env = try makePagingRepos()
    try env.scenarios.save(scenario(id: "s1", name: "One"))
    try env.sims.save(run(id: "r1", scenarioId: "s1", at: 10))
    try env.sims.save(run(id: "r2", scenarioId: "s1", at: 20))
    try env.sims.save(run(id: "r3", scenarioId: "s1", at: 30))

    let page1 = try env.sims.fetchRecentRunPage(nameQuery: nil, before: nil, limit: 2)
    #expect(page1.map(\.id) == ["r3", "r2"])
    let last = try #require(page1.last)

    // Concurrent insert at the very top of the recency stream.
    try env.sims.save(run(id: "r4", scenarioId: "s1", at: 40))

    let page2 = try env.sims.fetchRecentRunPage(
      nameQuery: nil,
      before: SimulationPageCursor(createdAt: last.createdAt, id: last.id),
      limit: 2)
    // Only the older r1 — r4 belongs to a fresh-from-top fetch, not this walk.
    #expect(page2.map(\.id) == ["r1"])
  }

  // MARK: - Name filter

  @Test func fetchRecentRunPageFiltersByLiveScenarioName() throws {
    let env = try makePagingRepos()
    try env.scenarios.save(scenario(id: "ja", name: "ワードウルフ"))
    try env.scenarios.save(scenario(id: "en", name: "Word Wolf"))
    try env.sims.save(run(id: "sim_ja", scenarioId: "ja", at: 10))
    try env.sims.save(run(id: "sim_en", scenarioId: "en", at: 20))

    // ASCII case-folding: lowercase "word" matches "Word Wolf".
    let en = try env.sims.fetchRecentRunPage(nameQuery: "word", before: nil, limit: 10)
    #expect(en.map(\.id) == ["sim_en"])

    let ja = try env.sims.fetchRecentRunPage(nameQuery: "ウルフ", before: nil, limit: 10)
    #expect(ja.map(\.id) == ["sim_ja"])
  }

  @Test func fetchRecentRunPageFiltersOrphanByNameSnapshot() throws {
    let env = try makePagingRepos()
    try env.scenarios.save(scenario(id: "live", name: "Live Scenario"))
    try env.sims.save(run(id: "sim_live", scenarioId: "live", at: 10))
    // Orphaned run (scenarioId nil) carrying a name snapshot.
    try env.sims.save(
      run(id: "sim_orphan", scenarioId: nil, at: 20, nameSnapshot: "Deleted Wolf"))

    let page = try env.sims.fetchRecentRunPage(nameQuery: "wolf", before: nil, limit: 10)
    #expect(page.map(\.id) == ["sim_orphan"])
  }

  @Test func fetchRecentRunPageExcludesNullSnapshotOrphanUnderFilter() throws {
    let env = try makePagingRepos()
    try env.scenarios.save(scenario(id: "live", name: "Match Me"))
    try env.sims.save(run(id: "sim_live", scenarioId: "live", at: 10))
    // Nameless orphan — unreachable by any non-empty name query.
    try env.sims.save(run(id: "sim_nameless", scenarioId: nil, at: 20, nameSnapshot: nil))

    let page = try env.sims.fetchRecentRunPage(nameQuery: "match", before: nil, limit: 10)
    #expect(page.map(\.id) == ["sim_live"])
  }

  @Test func fetchRecentRunPageEscapesLikeWildcards() throws {
    let env = try makePagingRepos()
    try env.scenarios.save(scenario(id: "pct", name: "100% Effort"))
    try env.scenarios.save(scenario(id: "other", name: "Plain"))
    try env.sims.save(run(id: "sim_pct", scenarioId: "pct", at: 10))
    try env.sims.save(run(id: "sim_other", scenarioId: "other", at: 20))

    // "%" must match literally — not as a wildcard that would match both.
    let page = try env.sims.fetchRecentRunPage(nameQuery: "100%", before: nil, limit: 10)
    #expect(page.map(\.id) == ["sim_pct"])
  }

  @Test func fetchRecentRunPageEscapesUnderscoreAndBackslashWildcards() throws {
    let env = try makePagingRepos()
    // `_` is a single-char LIKE wildcard; a literal `_` must not match a
    // different character. `\` exercises the escape-char doubling path.
    try env.scenarios.save(scenario(id: "u", name: "a_b"))
    try env.scenarios.save(scenario(id: "x", name: "axb"))
    try env.scenarios.save(scenario(id: "bs", name: #"path\to"#))
    try env.sims.save(run(id: "sim_u", scenarioId: "u", at: 30))
    try env.sims.save(run(id: "sim_x", scenarioId: "x", at: 20))
    try env.sims.save(run(id: "sim_bs", scenarioId: "bs", at: 10))

    // Literal "a_b" matches only "a_b", not "axb".
    let underscore = try env.sims.fetchRecentRunPage(nameQuery: "a_b", before: nil, limit: 10)
    #expect(underscore.map(\.id) == ["sim_u"])

    // Literal backslash survives the ESCAPE doubling and matches.
    let backslash = try env.sims.fetchRecentRunPage(nameQuery: #"path\to"#, before: nil, limit: 10)
    #expect(backslash.map(\.id) == ["sim_bs"])
  }

  @Test func fetchRecentRunPageBlankQueryReturnsAll() throws {
    let env = try makePagingRepos()
    try env.scenarios.save(scenario(id: "s1", name: "One"))
    try env.sims.save(run(id: "a", scenarioId: "s1", at: 10))
    try env.sims.save(run(id: "b", scenarioId: "s1", at: 20))

    // Whitespace-only is treated as no filter.
    let page = try env.sims.fetchRecentRunPage(nameQuery: "   ", before: nil, limit: 10)
    #expect(Set(page.map(\.id)) == ["a", "b"])
  }

  // MARK: - Top-3 score projection

  @Test func fetchRecentRunPageProjectsTopThreeScoresHighestFirst() throws {
    let env = try makePagingRepos()
    try env.scenarios.save(scenario(id: "s1", name: "One"))
    let stateJSON = #"{"scores":{"Alice":10,"Bob":8,"Carol":12,"Dave":3}}"#
    try env.sims.save(run(id: "sim", scenarioId: "s1", at: 10, stateJSON: stateJSON))

    let page = try env.sims.fetchRecentRunPage(nameQuery: nil, before: nil, limit: 10)
    let scores = try #require(page.first).topScores
    #expect(scores.map(\.name) == ["Carol", "Alice", "Bob"])
    #expect(scores.map(\.value) == [12, 10, 8])
  }

  @Test func fetchRecentRunPageEmptyScoresProjectToNoChips() throws {
    let env = try makePagingRepos()
    try env.scenarios.save(scenario(id: "s1", name: "One"))
    try env.sims.save(run(id: "sim", scenarioId: "s1", at: 10, stateJSON: "{}"))

    let page = try env.sims.fetchRecentRunPage(nameQuery: nil, before: nil, limit: 10)
    #expect(try #require(page.first).topScores.isEmpty)
  }

  // MARK: - currentRound + scenario-YAML-snapshot projection (P5 PR2)

  @Test func fetchRecentRunPageProjectsCurrentRoundAndYamlSnapshot() throws {
    let env = try makePagingRepos()
    try env.scenarios.save(scenario(id: "s1", name: "One"))
    let snapshot = "id: s1\nname: One\nagents: 4\nrounds: 5\n"
    try env.sims.save(
      run(id: "sim", scenarioId: "s1", at: 10, currentRound: 3, yamlSnapshot: snapshot))

    let item = try #require(
      try env.sims.fetchRecentRunPage(nameQuery: nil, before: nil, limit: 10).first)
    #expect(item.currentRound == 3)
    #expect(item.scenarioYamlSnapshot == snapshot)
  }

  @Test func fetchRunListProjectsCurrentRoundAndYamlSnapshot() throws {
    let env = try makePagingRepos()
    try env.scenarios.save(scenario(id: "s1", name: "One"))
    let snapshot = "id: s1\nname: One\nagents: 4\nrounds: 5\n"
    try env.sims.save(
      run(id: "sim", scenarioId: "s1", at: 10, currentRound: 2, yamlSnapshot: snapshot))

    let item = try #require(try env.sims.fetchRunList(scenarioId: "s1").first)
    #expect(item.currentRound == 2)
    #expect(item.scenarioYamlSnapshot == snapshot)
  }

  /// A pre-v7 run (no captured snapshot) projects `nil` for the YAML snapshot
  /// — the App-layer resolver then falls back to the live scenario.
  @Test func fetchRecentRunPageProjectsNilSnapshotForPreV7Run() throws {
    let env = try makePagingRepos()
    try env.scenarios.save(scenario(id: "s1", name: "One"))
    try env.sims.save(run(id: "sim", scenarioId: "s1", at: 10, yamlSnapshot: nil))

    let item = try #require(
      try env.sims.fetchRecentRunPage(nameQuery: nil, before: nil, limit: 10).first)
    #expect(item.scenarioYamlSnapshot == nil)
  }

  // MARK: - Detail light fetch

  @Test func fetchRunListReturnsScenarioRunsNewestFirst() throws {
    let env = try makePagingRepos()
    try env.scenarios.save(scenario(id: "s1", name: "One"))
    try env.scenarios.save(scenario(id: "s2", name: "Two"))
    try env.sims.save(run(id: "a", scenarioId: "s1", at: 10))
    try env.sims.save(run(id: "b", scenarioId: "s1", at: 30))
    try env.sims.save(run(id: "other", scenarioId: "s2", at: 20))

    let list = try env.sims.fetchRunList(scenarioId: "s1")
    #expect(list.map(\.id) == ["b", "a"])
  }
}

// MARK: - File-scope helpers

private struct PagingRepos {
  let scenarios: GRDBScenarioRepository
  let sims: GRDBSimulationRepository
}

private func makePagingRepos() throws -> PagingRepos {
  let manager = try DatabaseManager.inMemory()
  return PagingRepos(
    scenarios: GRDBScenarioRepository(dbWriter: manager.dbWriter),
    sims: GRDBSimulationRepository(dbWriter: manager.dbWriter))
}

private func scenario(id: String, name: String) -> ScenarioRecord {
  ScenarioRecord(
    id: id, name: name,
    yamlDefinition: "id: \(id)\nname: \(name)\n",
    isPreset: false, createdAt: Date(), updatedAt: Date())
}

private func run(
  id: String,
  scenarioId: String?,
  at offset: Double,
  stateJSON: String = "{}",
  nameSnapshot: String? = nil,
  currentRound: Int = 1,
  yamlSnapshot: String? = nil
) -> SimulationRecord {
  run(
    id: id, scenarioId: scenarioId, at: Date(timeIntervalSince1970: offset),
    stateJSON: stateJSON, nameSnapshot: nameSnapshot,
    currentRound: currentRound, yamlSnapshot: yamlSnapshot)
}

private func run(
  id: String,
  scenarioId: String?,
  at createdAt: Date,
  stateJSON: String = "{}",
  nameSnapshot: String? = nil,
  currentRound: Int = 1,
  yamlSnapshot: String? = nil
) -> SimulationRecord {
  SimulationRecord(
    id: id, scenarioId: scenarioId,
    status: SimulationStatus.completed.rawValue,
    currentRound: currentRound, currentPhaseIndex: 0,
    stateJSON: stateJSON, configJSON: nil,
    createdAt: createdAt, updatedAt: createdAt,
    scenarioYamlSnapshot: yamlSnapshot,
    scenarioNameSnapshot: nameSnapshot)
}
