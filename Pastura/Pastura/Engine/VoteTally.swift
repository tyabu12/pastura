import Foundation

/// Vote-tally helpers shared across the engine's most-voted-agent sites.
///
/// Consolidates the canonical tie-break so a future change can't reintroduce
/// the per-launch divergence #1056/#1057 fixed: `EliminateHandler`,
/// `WordwolfJudgeLogic`, and `ConditionEvaluator`'s `vote_winner` derivation
/// all resolve a tie to the same agent.
nonisolated enum VoteTally {
  /// The winning agent by the canonical deterministic tie-break:
  /// (count desc, name desc). Returns `nil` for empty input.
  ///
  /// Returns the full `(key, value)` element so a call site that needs the
  /// vote count (e.g. `EliminateHandler`'s `.elimination` event) can read
  /// `.value` without a second lookup.
  static func winner(_ voteResults: [String: Int]) -> (key: String, value: Int)? {
    voteResults.sorted(by: { ($0.value, $0.key) > ($1.value, $1.key) }).first
  }
}
