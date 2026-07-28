import Foundation
import GRDB

// Split out of `SimulationRepository.swift` to keep it under the
// file_length cap. `nonisolated` on the extension is load-bearing:
// `GRDBSimulationRepository` is a `nonisolated` Data-layer type, but a
// plain sibling-file extension inherits the project's default MainActor
// isolation and would break `nonisolated` callers (see
// `.claude/rules/swift-isolation.md` Pattern 3).
nonisolated extension GRDBSimulationRepository {
  public func completedRunCount(excludingRunId: String?) throws -> Int {
    try dbWriter.read { db in
      // COUNT(*) aggregate, computed SQL-side. Deliberately no
      // `scenarioId IS NOT NULL` predicate (unlike
      // completedRunCountsByScenarioId()'s GROUP BY) — that predicate only
      // exists there to drop a null GROUP BY key; here it would silently
      // under-count orphaned runs (scenarioId NULL, the ON DELETE SET NULL
      // outcome since v7), which must still count toward this total.
      if let excludingRunId {
        return try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM simulations WHERE status = ? AND id <> ?",
          arguments: [SimulationStatus.completed.rawValue, excludingRunId]) ?? 0
      }
      return try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM simulations WHERE status = ?",
        arguments: [SimulationStatus.completed.rawValue]) ?? 0
    }
  }
}
