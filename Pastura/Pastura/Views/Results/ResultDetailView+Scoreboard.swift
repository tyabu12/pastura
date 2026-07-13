import SwiftUI

/// Final scores + elimination for a past run's scoreboard, reconstructed from
/// the persisted ``SimulationState``. Built only when the run has a **rankable**
/// score (at least one non-zero) — parity with the live
/// ``SimulationView`` card gate, which hides the scoreboard for a vote-only
/// outcome that would otherwise render misleading all-zero rows.
///
/// `nonisolated` (pure value type + factory over nonisolated collections) so the
/// gate logic is unit-testable without a MainActor hop.
nonisolated struct ScoreboardSnapshot {
  let scores: [String: Int]
  let eliminated: [String: Bool]

  /// Returns a snapshot when at least one score is non-zero, else `nil`
  /// (empty scores or an all-zero / vote-only run → no scoreboard affordance).
  static func rankable(
    scores: [String: Int],
    eliminated: [String: Bool]
  ) -> ScoreboardSnapshot? {
    guard scores.values.contains(where: { $0 != 0 }) else { return nil }
    return ScoreboardSnapshot(scores: scores, eliminated: eliminated)
  }
}

extension ResultDetailView {
  /// Decodes the run's final ``SimulationState`` from the persisted record and
  /// builds the scoreboard snapshot, or `nil` when the run has no rankable
  /// score / can't be decoded. Resolved once in ``loadData()`` (a single
  /// main-thread decode, mirroring ``resolveIsResumable(_:)``) and cached into
  /// ``scoreboard`` so the toolbar gate + sheet never re-decode `stateJSON`.
  func resolveScoreboard(_ record: SimulationRecord?) -> ScoreboardSnapshot? {
    guard let record, let state = decodeState(from: record) else { return nil }
    return ScoreboardSnapshot.rankable(
      scores: state.scores, eliminated: state.eliminated)
  }

  /// Scoreboard toolbar button — shown only for a run with a rankable score
  /// (`scoreboard != nil`). Mirrors the live ``SimulationView`` control-bar
  /// affordance (`chart.bar.fill` → ``ScoreboardSheet``).
  @ToolbarContentBuilder
  var scoreboardToolbarItem: some ToolbarContent {
    if scoreboard != nil {
      ToolbarItem(placement: .primaryAction) {
        Button {
          showScoreboard = true
        } label: {
          Image(systemName: "chart.bar.fill")
        }
        .accessibilityLabel(String(localized: "Scoreboard"))
        .accessibilityIdentifier("resultDetail.scoreboardButton")
      }
      .hidingPasturaSharedBackground()
    }
  }
}
