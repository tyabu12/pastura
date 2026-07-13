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
  /// Delegates to `RankingOrder` (Models) so the comparator has a single
  /// definition shared with the result card and viewer-prediction scoring
  /// (#1087) — the displayed/predicted leader can't diverge from the eliminated
  /// agent. Returns the full `(key, value)` element so a call site that needs
  /// the vote count (e.g. `EliminateHandler`'s `.elimination` event) can read
  /// `.value` without a second lookup.
  static func winner(_ voteResults: [String: Int]) -> (key: String, value: Int)? {
    guard let key = RankingOrder.leader(values: voteResults, among: Array(voteResults.keys)),
      let value = voteResults[key]
    else { return nil }
    return (key, value)
  }
}
