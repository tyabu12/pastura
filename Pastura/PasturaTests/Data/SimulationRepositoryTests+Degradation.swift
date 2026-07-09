import Foundation
import Testing

@testable import Pastura

/// ADR-021 D6 turn-degradation coverage for `SimulationRepository`, split into
/// a sibling extension per `.claude/rules/testing.md` § "Splitting a Suite
/// Across Files" — the main suite is at the `type_body_length` budget. An
/// `extension` of the existing suite (NOT a new `@Suite`) so it shares the
/// suite's `.serialized`-free unit isolation and the internal `makeRepos` /
/// `makeSimRecord` helpers.
extension SimulationRepositoryTests {
  @Test func updateDegradedTurnCountChangesOnlyThatColumn() throws {
    let (_, simRepo) = try makeRepos()
    try simRepo.save(makeSimRecord(status: .completed, stateJSON: #"{"scores":{}}"#))

    try simRepo.updateDegradedTurnCount("sim1", count: 4)

    let fetched = try simRepo.fetchById("sim1")
    #expect(fetched?.degradedTurnCount == 4)
    // Status and state remain untouched.
    #expect(fetched?.simulationStatus == .completed)
    #expect(fetched?.stateJSON == #"{"scores":{}}"#)
  }

  @Test func updateDegradedTurnCountThrowsForMissingRecord() throws {
    let (_, simRepo) = try makeRepos()
    #expect(throws: DataError.self) {
      try simRepo.updateDegradedTurnCount("nonexistent", count: 1)
    }
  }

  @Test func fetchRunListProjectsDegradedTurnCount() throws {
    let (_, simRepo) = try makeRepos()
    var record = makeSimRecord(id: "run1", status: .completed)
    record.degradedTurnCount = 3
    try simRepo.save(record)

    let items = try simRepo.fetchRunList(scenarioId: "s1")
    #expect(items.first?.degradedTurnCount == 3)
  }
}
