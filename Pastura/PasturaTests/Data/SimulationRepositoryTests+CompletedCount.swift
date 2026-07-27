import Foundation
import Testing

@testable import Pastura

/// Completed-count tests for
/// ``SimulationRepository/completedRunCount(excludingRunId:)`` (the in-app
/// review prompt's engagement threshold). Sibling extension on the same
/// suite — see `testing.md` § "Splitting a Suite Across Files". Helpers are
/// file-scope and local (`makeCompletedCountRepos` / `completedCountScenario`
/// / `completedCountRun`).
///
/// Runs are seeded against a **live** scenario except where a test explicitly
/// exercises the orphan shape, so
/// ``completedRunCountIncludesOrphanedCompletedRuns`` is a real negative
/// control: it mixes both populations, and only the orphan half moves if a
/// `scenarioId IS NOT NULL` predicate is ever copied over from
/// ``completedRunCountsByScenarioId()``.
extension SimulationRepositoryTests {

  /// Pins the empty-DB contract (0, not a throw) for the very first launch —
  /// the state every new user is in. Weak by construction: it also passes
  /// against a `return 0` stub, so it is a contract pin, not a guard.
  @Test func completedRunCountReturnsZeroWhenEmpty() throws {
    let env = try makeCompletedCountRepos()
    #expect(try env.sims.completedRunCount(excludingRunId: nil) == 0)
  }

  @Test func completedRunCountCountsOnlyCompletedRuns() throws {
    let env = try makeCompletedCountRepos()
    try env.scenarios.save(completedCountScenario(id: "s1"))
    try env.sims.save(completedCountRun(id: "r1", scenarioId: "s1", status: .completed))
    try env.sims.save(completedCountRun(id: "r2", scenarioId: "s1", status: .completed))
    try env.sims.save(completedCountRun(id: "r3", scenarioId: "s1", status: .completed))
    try env.sims.save(completedCountRun(id: "r4", scenarioId: "s1", status: .paused))

    #expect(try env.sims.completedRunCount(excludingRunId: nil) == 3)
  }

  @Test func completedRunCountExcludesTheGivenRunId() throws {
    let env = try makeCompletedCountRepos()
    try env.scenarios.save(completedCountScenario(id: "s1"))
    try env.sims.save(completedCountRun(id: "r1", scenarioId: "s1", status: .completed))
    try env.sims.save(completedCountRun(id: "r2", scenarioId: "s1", status: .completed))
    try env.sims.save(completedCountRun(id: "r3", scenarioId: "s1", status: .completed))

    #expect(try env.sims.completedRunCount(excludingRunId: "r1") == 2)
  }

  @Test func completedRunCountExcludingUnmatchedIdLeavesTotalUnchanged() throws {
    let env = try makeCompletedCountRepos()
    try env.scenarios.save(completedCountScenario(id: "s1"))
    try env.sims.save(completedCountRun(id: "r1", scenarioId: "s1", status: .completed))
    try env.sims.save(completedCountRun(id: "r2", scenarioId: "s1", status: .completed))
    try env.sims.save(completedCountRun(id: "r3", scenarioId: "s1", status: .completed))

    #expect(try env.sims.completedRunCount(excludingRunId: "no-such-id") == 3)
  }

  // MARK: - Orphaned-run regression guard

  @Test func completedRunCountIncludesOrphanedCompletedRuns() throws {
    let env = try makeCompletedCountRepos()
    try env.scenarios.save(completedCountScenario(id: "s1"))
    // One live-scenario run + one orphan (scenarioId NULL, the ON DELETE SET
    // NULL shape since v7). Both must count: `completedRunCount` is a lifetime
    // total, not a per-scenario aggregate. A `scenarioId IS NOT NULL` predicate
    // would return 1 here — which is exactly what this mixed population
    // detects, and what an all-orphan fixture could not distinguish from the
    // neighbouring tests.
    try env.sims.save(completedCountRun(id: "r_live", scenarioId: "s1", status: .completed))
    try env.sims.save(completedCountRun(id: "r_orphan", scenarioId: nil, status: .completed))

    #expect(try env.sims.completedRunCount(excludingRunId: nil) == 2)
  }
}

// MARK: - File-scope helpers

private struct CompletedCountRepos {
  let scenarios: GRDBScenarioRepository
  let sims: GRDBSimulationRepository
}

private func makeCompletedCountRepos() throws -> CompletedCountRepos {
  let manager = try DatabaseManager.inMemory()
  return CompletedCountRepos(
    scenarios: GRDBScenarioRepository(dbWriter: manager.dbWriter),
    sims: GRDBSimulationRepository(dbWriter: manager.dbWriter))
}

private func completedCountScenario(id: String) -> ScenarioRecord {
  ScenarioRecord(
    id: id, name: "Scenario \(id)",
    yamlDefinition: "id: \(id)\nname: Scenario \(id)\n",
    isPreset: false, createdAt: Date(), updatedAt: Date())
}

private func completedCountRun(
  id: String,
  scenarioId: String?,
  status: SimulationStatus
) -> SimulationRecord {
  SimulationRecord(
    id: id, scenarioId: scenarioId,
    status: status.rawValue,
    currentRound: 1, currentPhaseIndex: 0,
    stateJSON: "{}", configJSON: nil,
    createdAt: Date(), updatedAt: Date(),
    scenarioNameSnapshot: nil)
}
