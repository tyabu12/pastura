import Foundation
import Testing

@testable import Pastura

/// Total-count tests for ``SimulationRepository/totalRunCount(nameQuery:)``
/// (P5 History screen-title "N 回の記録" subtitle). Sibling extension on the
/// same suite — see `testing.md` § "Splitting a Suite Across Files".
/// Helpers live at file scope; `makePagingRepos` / `scenario` / `run` are
/// reused from `SimulationRepositoryTests+RunListPaging.swift` (file-private
/// there, so identical local helpers are defined here).
extension SimulationRepositoryTests {

  // MARK: - Unfiltered count

  @Test func totalRunCountUnfilteredEqualsAllSeededRuns() throws {
    let env = try makeTotalCountRepos()
    try env.scenarios.save(totalCountScenario(id: "s1", name: "Prisoner"))
    // Live-scenario run
    try env.sims.save(totalCountRun(id: "r1", scenarioId: "s1", at: 10))
    try env.sims.save(totalCountRun(id: "r2", scenarioId: "s1", at: 20))
    // Orphaned run: no scenarioId, carries a name snapshot
    try env.sims.save(
      totalCountRun(id: "r_orphan", scenarioId: nil, at: 5, nameSnapshot: "Old Scenario"))

    #expect(try env.sims.totalRunCount(nameQuery: nil) == 3)
  }

  @Test func totalRunCountIncludesOrphanedRunsInUnfilteredTotal() throws {
    let env = try makeTotalCountRepos()
    // Only an orphan — no live scenario
    try env.sims.save(
      totalCountRun(id: "orphan", scenarioId: nil, at: 10, nameSnapshot: "Gone"))

    // The orphan must count toward the unfiltered total (it appears in the
    // P5 date-grouped list), so count == 1, not 0.
    #expect(try env.sims.totalRunCount(nameQuery: nil) == 1)
  }

  @Test func totalRunCountReturnsZeroWhenEmpty() throws {
    let env = try makeTotalCountRepos()
    #expect(try env.sims.totalRunCount(nameQuery: nil) == 0)
  }

  // MARK: - Filtered count: live scenario name

  @Test func totalRunCountFiltersByLiveScenarioName() throws {
    let env = try makeTotalCountRepos()
    try env.scenarios.save(totalCountScenario(id: "prison", name: "Prisoner's Dilemma"))
    try env.scenarios.save(totalCountScenario(id: "wolf", name: "Word Wolf"))
    try env.sims.save(totalCountRun(id: "r1", scenarioId: "prison", at: 10))
    try env.sims.save(totalCountRun(id: "r2", scenarioId: "prison", at: 20))
    try env.sims.save(totalCountRun(id: "r3", scenarioId: "wolf", at: 30))

    // Case-insensitive substring match on "prison" → 2 runs
    #expect(try env.sims.totalRunCount(nameQuery: "prison") == 2)
    #expect(try env.sims.totalRunCount(nameQuery: "wolf") == 1)
  }

  // MARK: - Filtered count: orphan name snapshot

  @Test func totalRunCountFiltersByOrphanNameSnapshot() throws {
    let env = try makeTotalCountRepos()
    try env.scenarios.save(totalCountScenario(id: "live", name: "Unrelated"))
    try env.sims.save(totalCountRun(id: "r_live", scenarioId: "live", at: 10))
    // Orphan carrying a searchable snapshot
    try env.sims.save(
      totalCountRun(
        id: "r_orphan", scenarioId: nil, at: 5, nameSnapshot: "Deleted Wolf"))

    // "wolf" matches the snapshot, not the live scenario name
    #expect(try env.sims.totalRunCount(nameQuery: "wolf") == 1)
    // "unrelated" matches the live run only
    #expect(try env.sims.totalRunCount(nameQuery: "unrelated") == 1)
  }

  // MARK: - Blank / whitespace query behaves like nil

  @Test func totalRunCountBlankQueryReturnsUnfilteredTotal() throws {
    let env = try makeTotalCountRepos()
    try env.scenarios.save(totalCountScenario(id: "s1", name: "Alpha"))
    try env.sims.save(totalCountRun(id: "r1", scenarioId: "s1", at: 10))
    try env.sims.save(totalCountRun(id: "r2", scenarioId: "s1", at: 20))

    #expect(try env.sims.totalRunCount(nameQuery: "   ") == 2)
    #expect(try env.sims.totalRunCount(nameQuery: "") == 2)
  }
}

// MARK: - File-scope helpers

private struct TotalCountRepos {
  let scenarios: GRDBScenarioRepository
  let sims: GRDBSimulationRepository
}

private func makeTotalCountRepos() throws -> TotalCountRepos {
  let manager = try DatabaseManager.inMemory()
  return TotalCountRepos(
    scenarios: GRDBScenarioRepository(dbWriter: manager.dbWriter),
    sims: GRDBSimulationRepository(dbWriter: manager.dbWriter))
}

private func totalCountScenario(id: String, name: String) -> ScenarioRecord {
  ScenarioRecord(
    id: id, name: name,
    yamlDefinition: "id: \(id)\nname: \(name)\n",
    isPreset: false, createdAt: Date(), updatedAt: Date())
}

private func totalCountRun(
  id: String,
  scenarioId: String?,
  at offset: Double,
  nameSnapshot: String? = nil
) -> SimulationRecord {
  SimulationRecord(
    id: id, scenarioId: scenarioId,
    status: SimulationStatus.completed.rawValue,
    currentRound: 1, currentPhaseIndex: 0,
    stateJSON: "{}", configJSON: nil,
    createdAt: Date(timeIntervalSince1970: offset),
    updatedAt: Date(timeIntervalSince1970: offset),
    scenarioNameSnapshot: nameSnapshot)
}
