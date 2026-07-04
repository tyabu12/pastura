import Foundation
import GRDB

/// Database record type for the `prediction_records` table (#915).
///
/// Each record captures one *answered* viewer prediction: before a
/// simulation reveals its first vote tally, the app asks the viewer to
/// predict an outcome ("who is the wolf?" / "who is #1?"). The answer and
/// the ground truth — both computed at the reveal moment (see
/// `ViewerPredictionLogic`) — are frozen into a row here so the result card
/// and Past Results can show a hit/miss badge and a running streak without
/// replaying events.
///
/// Only answered predictions produce a row. Skipped / timed-out /
/// backgrounded predictions leave no row (an in-memory latch prevents a
/// same-run re-ask, and the fresh-`run()`-only interception means a resumed
/// run never asks), so both `predictedAgent` and `actualAgent` are always
/// populated — there is no skip sentinel.
nonisolated public struct PredictionRecord: Codable, Sendable, Equatable,
  FetchableRecord, PersistableRecord {
  public static let databaseTableName = "prediction_records"

  public var id: String
  public var simulationId: String
  /// Which question was asked. Stored as a raw string for forward compat;
  /// the typed vocabulary is `ViewerPredictionQuestion.Kind` ("wolf" /
  /// "topVote").
  public var questionKind: String
  /// The agent the viewer picked.
  public var predictedAgent: String
  /// The ground-truth agent computed at reveal time (the minority-word
  /// holder for "wolf", the top-tally agent for "topVote").
  public var actualAgent: String
  /// `predictedAgent == actualAgent`, frozen at capture so historical rows
  /// stay stable even if scoring semantics later change.
  public var isHit: Bool
  public var createdAt: Date

  public init(
    id: String,
    simulationId: String,
    questionKind: String,
    predictedAgent: String,
    actualAgent: String,
    isHit: Bool,
    createdAt: Date
  ) {
    self.id = id
    self.simulationId = simulationId
    self.questionKind = questionKind
    self.predictedAgent = predictedAgent
    self.actualAgent = actualAgent
    self.isHit = isHit
    self.createdAt = createdAt
  }
}
