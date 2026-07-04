import Foundation
import GRDB

/// Repository for persisting and retrieving viewer-prediction records (#915).
///
/// Predictions are written at most once per run (only when answered), so
/// per-simulation lookups return a single optional record. The streak query
/// powers the "連続的中" indicator on the result card.
nonisolated public protocol PredictionRepository: Sendable {
  /// Saves a single answered prediction.
  func save(_ record: PredictionRecord) throws

  /// Fetches the prediction for a simulation, or `nil` when the run had none
  /// (skipped, disabled, or a non-prediction scenario).
  func fetchBySimulationId(_ simulationId: String) throws -> PredictionRecord?

  /// Fetches predictions for many simulations at once, keyed by
  /// `simulationId`. Used by the Past Results list projection to attach a
  /// hit/miss badge per row without an N+1 query.
  func fetchBySimulationIds(
    _ simulationIds: [String]
  ) throws -> [String: PredictionRecord]

  /// The current consecutive-hit streak: counts hits from the most recent
  /// prediction backwards, stopping at the first miss. Returns `0` when the
  /// latest prediction was a miss or none exist.
  func currentStreak() throws -> Int
}

/// GRDB-backed implementation of `PredictionRepository`.
nonisolated public final class GRDBPredictionRepository: PredictionRepository, Sendable {
  private let dbWriter: any DatabaseWriter

  public init(dbWriter: any DatabaseWriter) {
    self.dbWriter = dbWriter
  }

  public func save(_ record: PredictionRecord) throws {
    try dbWriter.write { db in
      try record.insert(db)
    }
  }

  public func fetchBySimulationId(
    _ simulationId: String
  ) throws -> PredictionRecord? {
    try dbWriter.read { db in
      try PredictionRecord
        .filter(Column("simulationId") == simulationId)
        .fetchOne(db)
    }
  }

  public func fetchBySimulationIds(
    _ simulationIds: [String]
  ) throws -> [String: PredictionRecord] {
    guard !simulationIds.isEmpty else { return [:] }
    return try dbWriter.read { db in
      let records =
        try PredictionRecord
        .filter(simulationIds.contains(Column("simulationId")))
        .fetchAll(db)
      // At most one row per simulationId, so keying is unambiguous.
      return Dictionary(records.map { ($0.simulationId, $0) }) { first, _ in first }
    }
  }

  public func currentStreak() throws -> Int {
    try dbWriter.read { db in
      // Most-recent-first; `id` breaks any createdAt tie deterministically.
      let hits =
        try Bool.fetchAll(
          db,
          PredictionRecord
            .select(Column("isHit"))
            .order(Column("createdAt").desc, Column("id").desc))
      var streak = 0
      for hit in hits {
        guard hit else { break }
        streak += 1
      }
      return streak
    }
  }
}
