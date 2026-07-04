import Foundation

/// Deterministic "who is #1" ordering shared by the result card
/// (`SimulationResultCard.Model`) and viewer-prediction scoring
/// (`ViewerPredictionLogic`), introduced in #915 so the displayed leader and
/// the scored leader can never diverge.
///
/// Highest value wins; ties break by name ascending, giving a stable
/// run-to-run winner (a bare `.max` would pick a dictionary-order-dependent
/// tie-winner that could disagree with the card).
nonisolated public enum RankingOrder {
  /// Whether `lhs` outranks `rhs`: higher value first, then name ascending as
  /// the deterministic tiebreak. Usable directly as a `sorted(by:)` predicate.
  public static func isOrderedBefore(
    lhsName: String, lhsValue: Int, rhsName: String, rhsValue: Int
  ) -> Bool {
    lhsValue != rhsValue ? lhsValue > rhsValue : lhsName < rhsName
  }

  /// The single leader among `roster` by `values` (missing keys count as 0),
  /// or `nil` when `roster` is empty.
  public static func leader(
    values: [String: Int], among roster: [String]
  ) -> String? {
    guard !roster.isEmpty else { return nil }
    return roster.sorted {
      isOrderedBefore(
        lhsName: $0, lhsValue: values[$0] ?? 0,
        rhsName: $1, rhsValue: values[$1] ?? 0)
    }.first
  }
}
