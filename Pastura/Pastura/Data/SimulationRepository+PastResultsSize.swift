import Foundation
import GRDB

// Split out of `SimulationRepository.swift` to keep it under the
// file_length cap (#770). `nonisolated` on the extension is load-bearing:
// `GRDBSimulationRepository` is a `nonisolated` Data-layer type, but a
// plain sibling-file extension inherits the project's default MainActor
// isolation and would break `nonisolated` callers (see
// `.claude/rules/swift-isolation.md` Pattern 3).
nonisolated extension GRDBSimulationRepository {
  public func pastResultsByteCount() throws -> Int64 {
    try dbWriter.read { db in
      // Sum the UTF-8 byte length of each result table's payload + snapshot
      // TEXT columns. `CAST(col AS BLOB)` makes `LENGTH` count bytes, not
      // characters; `COALESCE(col, '')` guards the nullable columns (a NULL
      // term would poison the row sum); the outer `COALESCE(SUM(...), 0)`
      // returns 0 for an empty table (SUM over zero rows is NULL). Omitted
      // columns (id / FK / integer / timestamp / short labels such as
      // `status`, `modelIdentifier`, `llmBackend`, `agentName`) are
      // byte-negligible next to the JSON payloads (ADR-015 §2). `?? 0` is a
      // belt-and-suspenders floor — the COALESCEs already guarantee a row.
      let sql = """
        SELECT
          (SELECT COALESCE(SUM(
             LENGTH(CAST(stateJSON AS BLOB))
             + LENGTH(CAST(COALESCE(configJSON, '') AS BLOB))
             + LENGTH(CAST(COALESCE(scenarioYamlSnapshot, '') AS BLOB))
             + LENGTH(CAST(COALESCE(scenarioNameSnapshot, '') AS BLOB))
             + LENGTH(CAST(COALESCE(scenarioCategorySnapshot, '') AS BLOB))
           ), 0) FROM simulations)
        + (SELECT COALESCE(SUM(
             LENGTH(CAST(rawOutput AS BLOB))
             + LENGTH(CAST(parsedOutputJSON AS BLOB))
             + LENGTH(CAST(COALESCE(phasePathJSON, '') AS BLOB))
           ), 0) FROM turns)
        + (SELECT COALESCE(SUM(
             LENGTH(CAST(payloadJSON AS BLOB))
             + LENGTH(CAST(COALESCE(phasePathJSON, '') AS BLOB))
           ), 0) FROM code_phase_events)
        """
      return try Int64.fetchOne(db, sql: sql) ?? 0
    }
  }
}
